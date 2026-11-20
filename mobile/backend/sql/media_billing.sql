-- Private immutable uploads, analysis grants and server-verified purchases.
alter table public.cc_media add column width integer check(width between 1 and 4096),add column height integer check(height between 1 and 4096),add column verified_at timestamptz;
alter table public.cc_media add column attachment_target uuid;
alter table public.cc_media add foreign key(kitchen_id,attachment_target)references public.cc_aggregates(kitchen_id,id);
create function app_private.cc_media_prepare(p_kitchen uuid,p_target uuid,p_operation uuid,p_hash text,p_bytes bigint,p_mime text,p_width integer,p_height integer)returns jsonb language plpgsql security definer set search_path=''as $$declare u uuid:=app_private.require_member(p_kitchen,true);a uuid:=gen_random_uuid();request jsonb;cached jsonb;result jsonb;begin
 if p_bytes is null or p_width is null or p_height is null or p_hash is null or p_mime is null or p_bytes not between 1 and 2097152 or p_width not between 1 and 4096 or p_height not between 1 and 4096 or p_width::bigint*p_height>16777216 or p_hash!~'^[a-f0-9]{64}$'or p_mime not in('image/jpeg','image/png','image/webp')then raise exception 'INVALID_MEDIA';end if;
 if not exists(select 1 from public.cc_aggregates where id=p_target and kitchen_id=p_kitchen and deleted_at is null)then raise exception 'ATTACHMENT_TARGET_NOT_FOUND';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));request:=jsonb_build_object('kitchen',p_kitchen,'target',p_target,'hash',p_hash,'bytes',p_bytes,'mime',p_mime,'width',p_width,'height',p_height);cached:=app_private.replay(p_operation,request);if cached is not null then return cached;end if;
 if(select count(*)from public.cc_media where owner_id=u and created_at>now()-interval '1 day')>=100 then raise exception 'MEDIA_QUOTA_EXHAUSTED';end if;
 insert into public.cc_media(id,kitchen_id,owner_id,object_key,sha256,mime_type,bytes,width,height,attachment_target)values(a,p_kitchen,u,p_kitchen::text||'/'||a::text,p_hash,p_mime,p_bytes,p_width,p_height,p_target);
 result:=jsonb_build_object('asset_id',a,'object_key',p_kitchen::text||'/'||a::text,'status','pending');return app_private.remember(p_operation,request,result);
end $$;
create function app_private.cc_media_for_verify(p_asset uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare u uuid:=app_private.actor();m public.cc_media;begin
 select * into m from public.cc_media where id=p_asset and owner_id=u;if not found or not app_private.member(m.kitchen_id,true)then raise exception 'MEDIA_NOT_FOUND';end if;
 if m.status not in('pending','uploaded')then raise exception 'MEDIA_QUARANTINED';end if;return to_jsonb(m);
end $$;
create function app_private.cc_worker_media_status(p_asset uuid,p_hash text,p_status text)returns boolean language plpgsql security definer set search_path=''as $$begin
 if p_status not in('uploaded','quarantined','deleted')then raise exception 'INVALID_MEDIA_STATE';end if;
 update public.cc_media m set status=p_status,verified_at=case when p_status='uploaded'then now()else null end where id=p_asset and sha256=p_hash and status in('pending','uploaded','quarantined','deleted')and exists(select 1 from public.cc_profiles p where p.id=m.owner_id and p.account_state='active')and exists(select 1 from public.cc_memberships k where k.kitchen_id=m.kitchen_id and k.user_id=m.owner_id and k.status='active'and k.role in('editor','admin','owner'));return found;
end $$;
create function app_private.cc_worker_image_context(p_user uuid,p_job uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare j public.cc_jobs;assets jsonb;count_ids integer;begin
 select * into j from public.cc_jobs where id=p_job and user_id=p_user and kind='image'and status='running';if not found or not exists(select 1 from public.cc_profiles where id=p_user and account_state='active')then raise exception 'IMAGE_JOB_NOT_AUTHORIZED';end if;
 if not exists(select 1 from public.cc_consents where user_id=p_user and purpose='image'and version=j.input->>'consent_version'and revoked_at is null)then raise exception 'CONSENT_REQUIRED';end if;
 if jsonb_typeof(j.input->'media_ids')<>'array' or jsonb_array_length(j.input->'media_ids')not between 1 and 2 then raise exception 'INVALID_MEDIA_SELECTION';end if;
 count_ids:=jsonb_array_length(j.input->'media_ids');
 select coalesce(jsonb_agg(to_jsonb(m)),'[]')into assets from public.cc_media m join public.cc_memberships k on k.kitchen_id=m.kitchen_id and k.user_id=p_user and k.status='active'where m.id in(select value::uuid from jsonb_array_elements_text(j.input->'media_ids'))and m.status='uploaded'and m.verified_at is not null;
 if jsonb_array_length(assets)<>count_ids then raise exception 'MEDIA_NOT_FOUND';end if;return assets;
end $$;
create table app_private.billing_receipts(event_id text not null,user_id uuid not null,event_hash text not null,verified_at timestamptz not null,created_at timestamptz not null default now(),primary key(event_id,user_id));
create table app_private.billing_cursors(user_id uuid primary key,verified_at timestamptz not null);
create function app_private.cc_worker_entitlements(p_user uuid,p_event text,p_hash text,p_verified_at timestamptz,p_entitlements jsonb)returns jsonb language plpgsql security definer set search_path=''as $$declare e jsonb;r app_private.billing_receipts;latest timestamptz;begin
 if not exists(select 1 from public.cc_profiles where id=p_user and account_state='active')then raise exception 'BILLING_USER_NOT_FOUND';end if;
 if length(p_event)not between 1 and 200 or p_hash!~'^[a-f0-9]{64}$'or p_verified_at>now()+interval '5 minutes'or jsonb_typeof(p_entitlements)<>'array'or jsonb_array_length(p_entitlements)>20 then raise exception 'INVALID_BILLING_SNAPSHOT';end if;
 perform pg_advisory_xact_lock(hashtextextended('billing:'||p_user::text,0));select * into r from app_private.billing_receipts where event_id=p_event and user_id=p_user;
 if found then if r.event_hash<>p_hash then raise exception 'WEBHOOK_IDENTITY_MISMATCH';end if;return jsonb_build_object('duplicate',true);end if;
 select verified_at into latest from app_private.billing_cursors where user_id=p_user;
 if latest is null or p_verified_at>=latest then
 update public.cc_entitlements set state='expired',valid_until=least(coalesce(valid_until,p_verified_at),p_verified_at),verified_at=p_verified_at where user_id=p_user;
 for e in select value from jsonb_array_elements(p_entitlements)loop
 if length(e->>'key')not between 1 and 64 or e->>'state'not in('active','expired')then raise exception 'INVALID_ENTITLEMENT';end if;
 insert into public.cc_entitlements(user_id,entitlement_key,state,valid_until,provider,verified_at)values(p_user,e->>'key',e->>'state',(e->>'valid_until')::timestamptz,'revenuecat',p_verified_at)on conflict(user_id,entitlement_key)do update set state=excluded.state,valid_until=excluded.valid_until,verified_at=excluded.verified_at,provider='revenuecat';
 end loop;
 insert into app_private.billing_cursors(user_id,verified_at)values(p_user,p_verified_at)on conflict(user_id)do update set verified_at=excluded.verified_at;
 end if;
 insert into app_private.billing_receipts(event_id,user_id,event_hash,verified_at)values(p_event,p_user,p_hash,p_verified_at);return jsonb_build_object('verified_at',p_verified_at,'applied',latest is null or p_verified_at>=latest);
end $$;

create function public.cc_media_prepare(p_kitchen uuid,p_target uuid,p_operation uuid,p_hash text,p_bytes bigint,p_mime text,p_width integer,p_height integer)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_media_prepare(p_kitchen,p_target,p_operation,p_hash,p_bytes,p_mime,p_width,p_height)$$;
revoke execute on function public.cc_media_prepare(uuid,uuid,uuid,text,bigint,text,integer,integer),app_private.cc_media_prepare(uuid,uuid,uuid,text,bigint,text,integer,integer)from public,anon,authenticated;
grant execute on function public.cc_media_prepare(uuid,uuid,uuid,text,bigint,text,integer,integer),app_private.cc_media_prepare(uuid,uuid,uuid,text,bigint,text,integer,integer)to authenticated;
create function public.cc_media_for_verify(p_asset uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_media_for_verify(p_asset)$$;
revoke execute on function public.cc_media_for_verify(uuid),app_private.cc_media_for_verify(uuid)from public,anon,authenticated;
grant execute on function public.cc_media_for_verify(uuid),app_private.cc_media_for_verify(uuid)to authenticated;
create function public.cc_worker_media_status(p_asset uuid,p_hash text,p_status text)returns boolean language sql security invoker set search_path=''as $$select app_private.cc_worker_media_status(p_asset,p_hash,p_status)$$;
revoke execute on function public.cc_worker_media_status(uuid,text,text),app_private.cc_worker_media_status(uuid,text,text)from public,anon,authenticated;
grant execute on function public.cc_worker_media_status(uuid,text,text),app_private.cc_worker_media_status(uuid,text,text)to service_role;
create function public.cc_worker_image_context(p_user uuid,p_job uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_worker_image_context(p_user,p_job)$$;
revoke execute on function public.cc_worker_image_context(uuid,uuid),app_private.cc_worker_image_context(uuid,uuid)from public,anon,authenticated;
grant execute on function public.cc_worker_image_context(uuid,uuid),app_private.cc_worker_image_context(uuid,uuid)to service_role;
create function public.cc_worker_entitlements(p_user uuid,p_event text,p_hash text,p_verified_at timestamptz,p_entitlements jsonb)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_worker_entitlements(p_user,p_event,p_hash,p_verified_at,p_entitlements)$$;
revoke execute on function public.cc_worker_entitlements(uuid,text,text,timestamptz,jsonb),app_private.cc_worker_entitlements(uuid,text,text,timestamptz,jsonb)from public,anon,authenticated;
grant execute on function public.cc_worker_entitlements(uuid,text,text,timestamptz,jsonb),app_private.cc_worker_entitlements(uuid,text,text,timestamptz,jsonb)to service_role;

create function app_private.cc_media_for_read(p_asset uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare u uuid:=app_private.actor();m public.cc_media;begin select * into m from public.cc_media where id=p_asset and status='uploaded'and verified_at is not null;if not found or not app_private.member(m.kitchen_id)then raise exception 'MEDIA_NOT_FOUND';end if;return to_jsonb(m);end $$;
create function public.cc_media_for_read(p_asset uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_media_for_read(p_asset)$$;
revoke execute on function public.cc_media_for_read(uuid),app_private.cc_media_for_read(uuid)from public,anon,authenticated;
grant execute on function public.cc_media_for_read(uuid),app_private.cc_media_for_read(uuid)to authenticated;
create function app_private.cc_media_for_delete(p_asset uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare u uuid:=app_private.actor();m public.cc_media;begin select * into m from public.cc_media where id=p_asset and owner_id=u;if not found or not app_private.member(m.kitchen_id,true)then raise exception 'MEDIA_NOT_FOUND';end if;return to_jsonb(m);end $$;
create function public.cc_media_for_delete(p_asset uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.cc_media_for_delete(p_asset)$$;
revoke execute on function public.cc_media_for_delete(uuid),app_private.cc_media_for_delete(uuid)from public,anon,authenticated;
grant execute on function public.cc_media_for_delete(uuid),app_private.cc_media_for_delete(uuid)to authenticated;
alter policy cc_media_read on storage.objects using(bucket_id='kitchen-media'and exists(select 1 from public.cc_media m where m.object_key=name and m.status='uploaded'and m.verified_at is not null and app_private.member(m.kitchen_id)));
