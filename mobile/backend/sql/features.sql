-- Collaboration/publication operations. No consumer can grant staff roles.
create table public.cc_posts(id uuid primary key default gen_random_uuid(),author_id uuid not null references public.cc_profiles(id),share_id uuid not null references public.cc_shared_cards(id),title text not null check(length(title) between 1 and 160),snapshot jsonb not null,status text not null default 'pending' check(status in ('pending','published','rejected','removed')),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index cc_public_feed on public.cc_posts(created_at desc,id) where status='published';
create table public.cc_comments(id uuid primary key default gen_random_uuid(),post_id uuid not null references public.cc_posts(id) on delete cascade,author_id uuid not null references public.cc_profiles(id),body text not null check(length(body) between 1 and 2000),status text not null default 'pending' check(status in ('pending','published','rejected','removed')),created_at timestamptz not null default now());
create index cc_comment_post on public.cc_comments(post_id,created_at,id);
create table public.cc_creator_follows(user_id uuid not null references public.cc_profiles(id),creator_id uuid not null references public.cc_profiles(id),created_at timestamptz not null default now(),primary key(user_id,creator_id),check(user_id<>creator_id));
create table app_private.staff_roles(user_id uuid primary key references public.cc_profiles(id),role text not null check(role in ('moderator','support','publisher')),granted_at timestamptz not null default now());
create table app_private.moderation_actions(id bigint generated always as identity primary key,actor_id uuid not null,target_type text not null,target_id uuid not null,action text not null,reason text not null,created_at timestamptz not null default now());
create function app_private.visible_author(p_author uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.cc_profiles where id=auth.uid() and account_state='active') and exists(select 1 from public.cc_profiles where id=p_author and account_state='active') and not exists(select 1 from public.cc_blocks where(user_id=auth.uid() and blocked_user_id=p_author)or(user_id=p_author and blocked_user_id=auth.uid()))$$;
create function app_private.require_staff() returns uuid language plpgsql stable security definer set search_path='' as $$declare u uuid:=app_private.actor();begin if coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from app_private.staff_roles where user_id=u) then raise exception using errcode='42501',message='STAFF_MFA_REQUIRED';end if;return u;end $$;
create function app_private.cc_publish_post(p_share uuid,p_title text,p_operation uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=app_private.actor();c public.cc_shared_cards;p uuid;req jsonb:=jsonb_build_object('share',p_share,'title',p_title);cached jsonb;begin
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));cached:=app_private.replay(p_operation,req);if cached is not null then return cached;end if;
 select * into c from public.cc_shared_cards where id=p_share and owner_id=u and revoked_at is null and (expires_at is null or expires_at>now());if not found or not app_private.member(c.kitchen_id) then raise exception 'SHARE_NOT_FOUND';end if;
 if(select count(*) from public.cc_posts where author_id=u and created_at>now()-interval '1 day')>=10 then raise exception 'PUBLICATION_RATE_LIMIT';end if;
 insert into public.cc_posts(author_id,share_id,title,snapshot)values(u,p_share,p_title,c.snapshot)returning id into p;return app_private.remember(p_operation,req,jsonb_build_object('post_id',p,'status','pending'));
end $$;
create function app_private.cc_comment(p_post uuid,p_body text,p_operation uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=app_private.actor();c uuid;req jsonb:=jsonb_build_object('post',p_post,'body',p_body);cached jsonb;begin
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));cached:=app_private.replay(p_operation,req);if cached is not null then return cached;end if;
 if not exists(select 1 from public.cc_posts where id=p_post and status='published' and app_private.visible_author(author_id))then raise exception 'POST_NOT_FOUND';end if;
 if(select count(*)from public.cc_comments where author_id=u and created_at>now()-interval '1 hour')>=30 then raise exception 'COMMENT_RATE_LIMIT';end if;
 insert into public.cc_comments(post_id,author_id,body)values(p_post,u,p_body)returning id into c;return app_private.remember(p_operation,req,jsonb_build_object('comment_id',c,'status','pending'));
end $$;
create function app_private.cc_follow(p_creator uuid,p_following boolean) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=app_private.actor();begin
 if not app_private.visible_author(p_creator)then raise exception 'CREATOR_NOT_FOUND';end if;
 if p_following then insert into public.cc_creator_follows(user_id,creator_id)values(u,p_creator)on conflict do nothing;else delete from public.cc_creator_follows where user_id=u and creator_id=p_creator;end if;return jsonb_build_object('following',p_following);
end $$;
create function app_private.cc_moderate(p_type text,p_target uuid,p_action text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=app_private.require_staff();state text;begin
 if p_type not in('post','comment')or p_action not in('publish','reject','remove')or length(p_reason)not between 1 and 500 then raise exception 'INVALID_MODERATION';end if;
 state:=case p_action when 'publish' then 'published' when 'reject' then 'rejected' else 'removed' end;
 if p_type='post' then update public.cc_posts set status=state,updated_at=now()where id=p_target;else update public.cc_comments set status=state where id=p_target;end if;if not found then raise exception 'TARGET_NOT_FOUND';end if;
 insert into app_private.moderation_actions(actor_id,target_type,target_id,action,reason)values(u,p_type,p_target,p_action,p_reason);return jsonb_build_object('status',state);
end $$;
create function app_private.cc_staff_reports() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=app_private.require_staff();r jsonb;begin select coalesce(jsonb_agg(to_jsonb(x)),'[]')into r from(select id,target_type,target_id,reason,details,status,created_at from public.cc_reports where status in('pending','reviewing')order by created_at limit 100)x;return r;end $$;
create function app_private.cc_resolve_report(p_report uuid,p_resolution text) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=app_private.require_staff();begin
 if p_resolution not in('resolved','dismissed')then raise exception 'INVALID_RESOLUTION';end if;update public.cc_reports set status=p_resolution where id=p_report;if not found then raise exception 'REPORT_NOT_FOUND';end if;insert into app_private.moderation_actions(actor_id,target_type,target_id,action,reason)values(u,'report',p_report,p_resolution,p_resolution);return jsonb_build_object('status',p_resolution);
end $$;
create function app_private.cc_set_role(p_kitchen uuid,p_user uuid,p_role text) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=app_private.require_member(p_kitchen,true,true);begin
 perform 1 from public.cc_kitchens where id=p_kitchen for update;
 if p_role not in('viewer','editor','admin')then raise exception 'INVALID_ROLE';end if;
 if exists(select 1 from public.cc_kitchens where id=p_kitchen and owner_id=p_user)then raise exception 'OWNER_TRANSFER_REQUIRED';end if;
 if p_role='admin' and not exists(select 1 from public.cc_kitchens where id=p_kitchen and owner_id=u)then raise exception 'OWNER_REQUIRED';end if;
 update public.cc_memberships set role=p_role where kitchen_id=p_kitchen and user_id=p_user and status='active';if not found then raise exception 'MEMBER_NOT_FOUND';end if;
 update public.cc_kitchens set membership_revision=membership_revision+1 where id=p_kitchen;
 return jsonb_build_object('role',p_role);
end $$;
create function app_private.cc_transfer_owner(p_kitchen uuid,p_user uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=app_private.actor();begin
 perform 1 from public.cc_kitchens where id=p_kitchen and owner_id=u and kind<>'personal' and deleted_at is null for update;if not found then raise exception 'OWNER_REQUIRED';end if;
 if not exists(select 1 from public.cc_memberships where kitchen_id=p_kitchen and user_id=p_user and status='active')then raise exception 'ACTIVE_MEMBER_REQUIRED';end if;
 if not exists(select 1 from auth.users where id=u and last_sign_in_at>now()-interval '5 minutes')then raise exception 'REAUTH_REQUIRED';end if;
 update public.cc_memberships set role=case when user_id=p_user then 'owner' else 'admin' end where kitchen_id=p_kitchen and user_id in(u,p_user);
 update public.cc_kitchens set owner_id=p_user,membership_revision=membership_revision+1 where id=p_kitchen;
 return jsonb_build_object('owner_id',p_user);
end $$;
-- A deleted Auth identity leaves only a scrubbed tombstone profile to preserve
-- foreign keys in others' shared actual history. No email lives in that profile.
alter table public.cc_profiles drop constraint cc_profiles_id_fkey;
alter table public.cc_profiles drop constraint cc_profiles_account_state_check;
alter table public.cc_profiles add constraint cc_profiles_account_state_check check(account_state in('active','deleting','suspended','deleted'));
create function app_private.cc_worker_deletion_keys(p_user uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare keys jsonb;begin
 if not exists(select 1 from public.cc_profiles where id=p_user and account_state in('deleting','deleted'))then raise exception 'DELETION_NOT_AUTHORIZED';end if;
 select coalesce(jsonb_agg(object_key),'[]')into keys from public.cc_media where owner_id=p_user or kitchen_id in(select id from public.cc_kitchens where owner_id=p_user);return keys;
end $$;
create function app_private.cc_worker_delete_data(p_user uuid,p_job uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare k uuid;begin
 perform 1 from public.cc_profiles where id=p_user and account_state in('deleting','deleted')for update;if not found then raise exception 'DELETION_NOT_AUTHORIZED';end if;
 if not exists(select 1 from public.cc_jobs where id=p_job and user_id=p_user and kind='delete_account' and status='running')then raise exception 'DELETION_JOB_REQUIRED';end if;
 if exists(select 1 from public.cc_kitchens k join public.cc_memberships m on m.kitchen_id=k.id where k.owner_id=p_user and m.user_id<>p_user and m.status='active')then raise exception 'OWNERSHIP_TRANSFER_REQUIRED';end if;
 delete from public.cc_comments where author_id=p_user or post_id in(select id from public.cc_posts where author_id=p_user);
 delete from public.cc_posts where author_id=p_user;
 delete from public.cc_creator_follows where user_id=p_user or creator_id=p_user;
 delete from public.cc_blocks where user_id=p_user or blocked_user_id=p_user;
 delete from public.cc_reports where user_id=p_user;
 delete from app_private.share_tokens where card_id in(select id from public.cc_shared_cards where owner_id=p_user);
 delete from public.cc_shared_cards where owner_id=p_user;
 delete from public.cc_media where owner_id=p_user;
 for k in select id from public.cc_kitchens where owner_id=p_user loop
 delete from public.cc_resource_reservations where kitchen_id=k;delete from public.cc_reminders where kitchen_id=k;delete from public.cc_schedules where kitchen_id=k;
 delete from public.cc_domain_events where kitchen_id=k;delete from public.cc_sync_changes where kitchen_id=k;delete from public.cc_aggregates where kitchen_id=k;
 delete from app_private.invites where kitchen_id=k;delete from public.cc_media where kitchen_id=k;
 update public.cc_jobs set kitchen_id=null where kitchen_id=k;delete from public.cc_memberships where kitchen_id=k;update public.cc_kitchens set deleted_at=now(),name='Deleted kitchen' where id=k;
 end loop;
 -- Remove free-form contributions; keep numeric action evidence attributed only to
 -- the tombstone identity, subject to the published shared-history retention policy.
 update public.cc_domain_events set payload=payload-'note'-'notes'-'text'-'photo'-'photos' where actor_id=p_user;
 update public.cc_aggregates set data=data-'notes'-'note'-'email'-'photos'-'photo' where created_by=p_user;
 delete from public.cc_sync_changes where entity_id in(select id from public.cc_aggregates where created_by=p_user);
 update public.cc_memberships set status='revoked',revoked_at=now()where user_id=p_user;
 delete from public.cc_consents where user_id=p_user;delete from public.cc_entitlements where user_id=p_user;
 delete from public.cc_jobs where user_id=p_user and id<>p_job;delete from app_private.idempotency where user_id=p_user;delete from app_private.staff_roles where user_id=p_user;
 update public.cc_profiles set display_name=null,locale='und',time_zone='Etc/UTC',account_state='deleted'where id=p_user;
 return jsonb_build_object('purged',true,'shared_numeric_history_retained',true);
end $$;

alter table public.cc_posts enable row level security;alter table public.cc_comments enable row level security;alter table public.cc_creator_follows enable row level security;
revoke all on public.cc_posts,public.cc_comments,public.cc_creator_follows from anon,authenticated;
grant select on public.cc_posts,public.cc_comments,public.cc_creator_follows to authenticated;
create policy cc_visible_posts on public.cc_posts for select to authenticated using((author_id=auth.uid() or status='published')and app_private.visible_author(author_id));
create policy cc_visible_comments on public.cc_comments for select to authenticated using((author_id=auth.uid() or status='published')and app_private.visible_author(author_id)and exists(select 1 from public.cc_posts where id=post_id and status='published'));
create policy cc_follows_self on public.cc_creator_follows for select to authenticated using(user_id=auth.uid());
revoke all on all tables in schema app_private from public,anon,authenticated;
revoke execute on function app_private.visible_author(uuid)from public,anon;grant execute on function app_private.visible_author(uuid)to authenticated;
revoke execute on function app_private.require_staff()from public,anon,authenticated;
-- Service reads for the worker are explicit; no consumer receives this key.
do $$declare t record;begin for t in select tablename from pg_tables where schemaname='public'and tablename like 'cc\_%'escape '\' loop execute format('grant all on public.%I to service_role',t.tablename);end loop;end $$;

create function app_private.cc_staff_pending() returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=app_private.require_staff();r jsonb;begin select coalesce(jsonb_agg(to_jsonb(x)),'[]')into r from(select id,author_id,title,snapshot,status,created_at from public.cc_posts where status='pending'order by created_at limit 100)x;return r;end $$;

create function public.cc_publish_post(p_share uuid,p_title text,p_operation uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_publish_post(p_share,p_title,p_operation)$$;
revoke execute on function public.cc_publish_post(uuid,text,uuid),app_private.cc_publish_post(uuid,text,uuid)from public,anon,authenticated;
grant execute on function public.cc_publish_post(uuid,text,uuid),app_private.cc_publish_post(uuid,text,uuid)to authenticated;
create function public.cc_comment(p_post uuid,p_body text,p_operation uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_comment(p_post,p_body,p_operation)$$;
revoke execute on function public.cc_comment(uuid,text,uuid),app_private.cc_comment(uuid,text,uuid)from public,anon,authenticated;
grant execute on function public.cc_comment(uuid,text,uuid),app_private.cc_comment(uuid,text,uuid)to authenticated;
create function public.cc_follow(p_creator uuid,p_following boolean)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_follow(p_creator,p_following)$$;
revoke execute on function public.cc_follow(uuid,boolean),app_private.cc_follow(uuid,boolean)from public,anon,authenticated;
grant execute on function public.cc_follow(uuid,boolean),app_private.cc_follow(uuid,boolean)to authenticated;
create function public.cc_moderate(p_type text,p_target uuid,p_action text,p_reason text)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_moderate(p_type,p_target,p_action,p_reason)$$;
revoke execute on function public.cc_moderate(text,uuid,text,text),app_private.cc_moderate(text,uuid,text,text)from public,anon,authenticated;
grant execute on function public.cc_moderate(text,uuid,text,text),app_private.cc_moderate(text,uuid,text,text)to authenticated;
create function public.cc_staff_reports()returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_staff_reports()$$;
revoke execute on function public.cc_staff_reports(),app_private.cc_staff_reports()from public,anon,authenticated;
grant execute on function public.cc_staff_reports(),app_private.cc_staff_reports()to authenticated;
create function public.cc_resolve_report(p_report uuid,p_resolution text)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_resolve_report(p_report,p_resolution)$$;
revoke execute on function public.cc_resolve_report(uuid,text),app_private.cc_resolve_report(uuid,text)from public,anon,authenticated;
grant execute on function public.cc_resolve_report(uuid,text),app_private.cc_resolve_report(uuid,text)to authenticated;
create function public.cc_set_role(p_kitchen uuid,p_user uuid,p_role text)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_set_role(p_kitchen,p_user,p_role)$$;
revoke execute on function public.cc_set_role(uuid,uuid,text),app_private.cc_set_role(uuid,uuid,text)from public,anon,authenticated;
grant execute on function public.cc_set_role(uuid,uuid,text),app_private.cc_set_role(uuid,uuid,text)to authenticated;
create function public.cc_transfer_owner(p_kitchen uuid,p_user uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_transfer_owner(p_kitchen,p_user)$$;
revoke execute on function public.cc_transfer_owner(uuid,uuid),app_private.cc_transfer_owner(uuid,uuid)from public,anon,authenticated;
grant execute on function public.cc_transfer_owner(uuid,uuid),app_private.cc_transfer_owner(uuid,uuid)to authenticated;
create function public.cc_worker_deletion_keys(p_user uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_worker_deletion_keys(p_user)$$;
revoke execute on function public.cc_worker_deletion_keys(uuid),app_private.cc_worker_deletion_keys(uuid)from public,anon,authenticated;
grant execute on function public.cc_worker_deletion_keys(uuid),app_private.cc_worker_deletion_keys(uuid)to service_role;
create function public.cc_worker_delete_data(p_user uuid,p_job uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_worker_delete_data(p_user,p_job)$$;
revoke execute on function public.cc_worker_delete_data(uuid,uuid),app_private.cc_worker_delete_data(uuid,uuid)from public,anon,authenticated;
grant execute on function public.cc_worker_delete_data(uuid,uuid),app_private.cc_worker_delete_data(uuid,uuid)to service_role;
create function public.cc_staff_pending()returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_staff_pending()$$;
revoke execute on function public.cc_staff_pending(),app_private.cc_staff_pending()from public,anon,authenticated;
grant execute on function public.cc_staff_pending(),app_private.cc_staff_pending()to authenticated;
create function app_private.cc_worker_export(p_user uuid,p_job uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;records jsonb;events jsonb;begin
 if not exists(select 1 from public.cc_jobs j join public.cc_profiles p on p.id=j.user_id where j.id=p_job and j.user_id=p_user and j.kind='export'and j.status='running'and p.account_state='active')then raise exception 'EXPORT_NOT_AUTHORIZED';end if;
 if(select count(*)from public.cc_aggregates a join public.cc_memberships m on m.kitchen_id=a.kitchen_id and m.user_id=p_user and m.status='active'where a.deleted_at is null)>500 then raise exception 'EXPORT_TOO_LARGE_USE_LOCAL_ARCHIVE';end if;
 select coalesce(jsonb_agg(to_jsonb(a)),'[]')into records from public.cc_aggregates a join public.cc_memberships m on m.kitchen_id=a.kitchen_id and m.user_id=p_user and m.status='active'join public.cc_kitchens k on k.id=a.kitchen_id and k.deleted_at is null where a.deleted_at is null;
 select coalesce(jsonb_agg(to_jsonb(e)),'[]')into events from public.cc_domain_events e join public.cc_memberships m on m.kitchen_id=e.kitchen_id and m.user_id=p_user and m.status='active'join public.cc_kitchens k on k.id=e.kitchen_id and k.deleted_at is null;
 result:=jsonb_build_object('format','crispy-crust-cloud-export','schema_version',1,'created_at',now(),'records',records,'events',events,'media_included',false);
 if octet_length(result::text)>4194304 then raise exception 'EXPORT_TOO_LARGE_USE_LOCAL_ARCHIVE';end if;return result;
end $$;
create function public.cc_worker_export(p_user uuid,p_job uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_worker_export(p_user,p_job)$$;
revoke execute on function public.cc_worker_export(uuid,uuid),app_private.cc_worker_export(uuid,uuid)from public,anon,authenticated;
grant execute on function public.cc_worker_export(uuid,uuid),app_private.cc_worker_export(uuid,uuid)to service_role;
create function app_private.cc_list_members(p_kitchen uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare u uuid:=app_private.require_member(p_kitchen);r jsonb;begin select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'role',m.role,'display_name',p.display_name,'status',m.status)),'[]')into r from public.cc_memberships m join public.cc_profiles p on p.id=m.user_id where m.kitchen_id=p_kitchen and m.status='active';return r;end $$;
create function public.cc_list_members(p_kitchen uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_list_members(p_kitchen)$$;
revoke execute on function public.cc_list_members(uuid),app_private.cc_list_members(uuid)from public,anon,authenticated;
grant execute on function public.cc_list_members(uuid),app_private.cc_list_members(uuid)to authenticated;
