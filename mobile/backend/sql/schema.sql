-- Crispy Crust app backend. Separate from marketing/waitlist project.
-- Apply as migration owner. Client writes go through checked commands, never table DML.
create schema if not exists app_private;
revoke all on schema app_private from public;
grant usage on schema app_private to authenticated;

create table public.cc_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text check (length(display_name)<=80),
 locale text not null default 'en', time_zone text not null default 'Europe/London',
 account_state text not null default 'active' check(account_state in ('active','deleting','suspended')),
 created_at timestamptz not null default now()
);
create table public.cc_kitchens (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.cc_profiles(id),
 kind text not null check(kind in ('personal','household','production')),
 name text not null check(length(name) between 1 and 100),
 membership_revision bigint not null default 1, change_sequence bigint not null default 0,
 created_at timestamptz not null default now(), deleted_at timestamptz
);
create unique index cc_one_personal on public.cc_kitchens(owner_id) where kind='personal' and deleted_at is null;
create table public.cc_memberships (
 kitchen_id uuid not null references public.cc_kitchens(id) on delete cascade,
 user_id uuid not null references public.cc_profiles(id) on delete cascade,
 role text not null check(role in ('viewer','editor','admin','owner')),
 status text not null default 'active' check(status in ('active','revoked')),
 joined_at timestamptz not null default now(), revoked_at timestamptz,
 primary key(kitchen_id,user_id)
);
create index cc_membership_user on public.cc_memberships(user_id,kitchen_id,status);
create table public.cc_aggregates (
 id uuid primary key, kitchen_id uuid not null references public.cc_kitchens(id),
 kind text not null check(kind in ('starter','recipe','bake','journal','pantry','equipment','availability','production','lesson_progress','experiment','shopping_list','discard','preference','sensor_binding','feed','completion','correction','observation','timer','interruption','lesson','sensor','shopping')),
 revision bigint not null default 1 check(revision>0), schema_version integer not null default 1 check(schema_version>0),
 data jsonb not null check(jsonb_typeof(data)='object' and octet_length(data::text)<=262144),
 created_by uuid not null references public.cc_profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(kitchen_id,id)
);
create index cc_aggregate_pull on public.cc_aggregates(kitchen_id,updated_at,id);
create index cc_aggregate_kind on public.cc_aggregates(kitchen_id,kind,id) where deleted_at is null;
create table public.cc_domain_events (
 event_id uuid primary key, kitchen_id uuid not null, aggregate_id uuid not null,
 aggregate_revision bigint not null, operation_id uuid not null, type text not null,
 payload jsonb not null check(jsonb_typeof(payload)='object'), actor_id uuid not null references public.cc_profiles(id),
 device_id uuid not null, occurred_at timestamptz not null, received_at timestamptz not null default now(),
 foreign key(kitchen_id,aggregate_id) references public.cc_aggregates(kitchen_id,id),
 unique(kitchen_id,operation_id), unique(aggregate_id,aggregate_revision)
);
create index cc_events_aggregate on public.cc_domain_events(aggregate_id,aggregate_revision);
create index cc_events_tenant on public.cc_domain_events(kitchen_id,received_at,event_id);
create table public.cc_sync_changes (
 kitchen_id uuid not null references public.cc_kitchens(id), sequence bigint not null,
 entity_id uuid not null, kind text not null, revision bigint not null, operation text not null check(operation in ('upsert','tombstone','event','schedule')),
 payload jsonb not null, created_at timestamptz not null default now(), primary key(kitchen_id,sequence)
);
create table app_private.idempotency (
 user_id uuid not null, operation_id uuid not null, request_hash text not null, result jsonb not null,
 created_at timestamptz not null default now(), primary key(user_id,operation_id)
);
create table public.cc_schedules (
 id uuid primary key, kitchen_id uuid not null, bake_id uuid not null,
 version bigint not null, status text not null check(status in ('accepted','superseded')),
 engine_version text not null, snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 created_by uuid not null references public.cc_profiles(id), created_at timestamptz not null default now(),
 foreign key(kitchen_id,bake_id) references public.cc_aggregates(kitchen_id,id), unique(bake_id,version)
);
create unique index cc_current_schedule on public.cc_schedules(bake_id) where status='accepted';
create table public.cc_resource_reservations (
 id uuid primary key default gen_random_uuid(), kitchen_id uuid not null references public.cc_kitchens(id),
 schedule_id uuid not null references public.cc_schedules(id), resource_id text not null,
 slot integer not null default 1 check(slot>0), start_at timestamptz not null, finish_at timestamptz not null,
 check(finish_at>start_at)
);
create index cc_resource_time on public.cc_resource_reservations(kitchen_id,resource_id,slot,start_at,finish_at);
create table public.cc_reminders (
 id uuid primary key default gen_random_uuid(), kitchen_id uuid not null references public.cc_kitchens(id),
 aggregate_id uuid not null, schedule_id uuid references public.cc_schedules(id),
 due_at timestamptz not null, task_id text not null, status text not null default 'pending' check(status in ('pending','superseded','acknowledged')),
 foreign key(kitchen_id,aggregate_id) references public.cc_aggregates(kitchen_id,id)
);
create index cc_due on public.cc_reminders(kitchen_id,due_at) where status='pending';
create table app_private.invites (
 id uuid primary key default gen_random_uuid(), kitchen_id uuid not null references public.cc_kitchens(id),
 token_hash text not null unique, role text not null check(role in ('viewer','editor','admin')),
 created_by uuid not null, expires_at timestamptz not null, redeemed_by uuid, revoked_at timestamptz
);
create table public.cc_shared_cards (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.cc_profiles(id),
 kitchen_id uuid not null references public.cc_kitchens(id), snapshot jsonb not null,
 created_at timestamptz not null default now(), expires_at timestamptz, revoked_at timestamptz
);
create table app_private.share_tokens (card_id uuid primary key references public.cc_shared_cards(id),token_hash text not null unique);
create table public.cc_jobs (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.cc_profiles(id), kitchen_id uuid references public.cc_kitchens(id),
 kind text not null check(kind in ('coach','import','image','export','delete_account')),
 status text not null default 'queued' check(status in ('queued','running','complete','failed','canceled')),
 input jsonb not null check(octet_length(input::text)<=262144), result jsonb,
 error_code text, attempt integer not null default 0, available_at timestamptz not null default now(), lease_until timestamptz,
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '30 days'
);
create index cc_jobs_owner on public.cc_jobs(user_id,created_at desc,id);
create index cc_jobs_queue on public.cc_jobs(available_at,id) where status='queued';
create table public.cc_reports (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.cc_profiles(id),
 target_type text not null check(target_type in ('share','post','coach','user')), target_id uuid not null,
 reason text not null check(length(reason) between 1 and 500), details text check(length(details)<=2000),
 status text not null default 'pending' check(status in ('pending','reviewing','resolved','dismissed')), created_at timestamptz not null default now()
);
create table public.cc_blocks (user_id uuid not null references public.cc_profiles(id),blocked_user_id uuid not null references public.cc_profiles(id),created_at timestamptz not null default now(),primary key(user_id,blocked_user_id),check(user_id<>blocked_user_id));
create table public.cc_media (
 id uuid primary key default gen_random_uuid(), kitchen_id uuid not null references public.cc_kitchens(id), owner_id uuid not null references public.cc_profiles(id),
 object_key text not null unique, sha256 text not null check(sha256~'^[a-f0-9]{64}$'), mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp')),
 bytes bigint not null check(bytes between 1 and 10485760), status text not null default 'pending' check(status in ('pending','uploaded','quarantined','deleted')),created_at timestamptz not null default now()
);
create table public.cc_consents (user_id uuid not null references public.cc_profiles(id),purpose text not null,version text not null,granted_at timestamptz not null default now(),revoked_at timestamptz,primary key(user_id,purpose,version));
create table public.cc_entitlements (user_id uuid not null references public.cc_profiles(id),entitlement_key text not null,state text not null check(state in ('active','trial','grace','hold','expired','revoked')),valid_until timestamptz,provider text not null,verified_at timestamptz not null default now(),primary key(user_id,entitlement_key));
create table app_private.audit_events (id bigint generated always as identity primary key,actor_id uuid,action text not null,target_id uuid,details jsonb not null default '{}',created_at timestamptz not null default now());

-- These helpers never trust user_metadata and always re-check current DB membership.
create function app_private.actor() returns uuid language plpgsql stable security definer set search_path='' as $$
declare u uuid := auth.uid(); begin
 if u is null or not exists(select 1 from public.cc_profiles where id=u and account_state='active') then raise exception using errcode='28000',message='AUTH_REQUIRED'; end if;
 return u; end $$;
create function app_private.member(p_kitchen uuid,p_write boolean default false,p_admin boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cc_memberships m join public.cc_profiles p on p.id=m.user_id join public.cc_kitchens k on k.id=m.kitchen_id
 where m.kitchen_id=p_kitchen and m.user_id=auth.uid() and m.status='active' and p.account_state='active' and k.deleted_at is null
 and (not p_write or m.role in ('editor','admin','owner')) and (not p_admin or m.role in ('admin','owner')))
$$;
create function app_private.require_member(p_kitchen uuid,p_write boolean default false,p_admin boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid := app_private.actor(); begin
 if not app_private.member(p_kitchen,p_write,p_admin) then raise exception using errcode='42501',message='KITCHEN_ACCESS_REVOKED'; end if; return u;
end $$;
create function app_private.hash_token(p_token text) returns text language sql immutable set search_path='' as $$select encode(sha256(convert_to(p_token,'UTF8')),'hex')$$;
create function app_private.replay(p_operation uuid,p_request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r app_private.idempotency; begin
 select * into r from app_private.idempotency where user_id=auth.uid() and operation_id=p_operation;
 if found then if r.request_hash<>md5(p_request::text) then raise exception using errcode='23505',message='IDEMPOTENCY_KEY_MISMATCH';end if;return r.result;end if;return null;
end $$;
create function app_private.remember(p_operation uuid,p_request jsonb,p_result jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 insert into app_private.idempotency(user_id,operation_id,request_hash,result) values(auth.uid(),p_operation,md5(p_request::text),p_result);return p_result;
end $$;
create function app_private.change(p_kitchen uuid,p_id uuid,p_kind text,p_revision bigint,p_operation text,p_payload jsonb) returns bigint language plpgsql security definer set search_path='' as $$
declare n bigint;begin
 update public.cc_kitchens set change_sequence=change_sequence+1 where id=p_kitchen returning change_sequence into n;
 insert into public.cc_sync_changes(kitchen_id,sequence,entity_id,kind,revision,operation,payload) values(p_kitchen,n,p_id,p_kind,p_revision,p_operation,p_payload);return n;
end $$;

create function app_private.cc_bootstrap(p_name text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); k uuid;begin
 if u is null then raise exception using errcode='28000',message='AUTH_REQUIRED';end if;
 insert into public.cc_profiles(id,display_name) values(u,left(p_name,80)) on conflict(id) do nothing;
 perform app_private.actor();
 select id into k from public.cc_kitchens where owner_id=u and kind='personal' and deleted_at is null;
 if k is null then
 insert into public.cc_kitchens(owner_id,kind,name) values(u,'personal','My kitchen') returning id into k;
 insert into public.cc_memberships(kitchen_id,user_id,role) values(k,u,'owner');end if;
 return jsonb_build_object('user_id',u,'kitchen_id',k);
end $$;
create function app_private.cc_create_kitchen(p_kind text,p_name text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();k uuid;begin
 if p_kind not in ('household','production') then raise exception 'INVALID_KITCHEN_KIND';end if;
 insert into public.cc_kitchens(owner_id,kind,name) values(u,p_kind,p_name) returning id into k;
 insert into public.cc_memberships(kitchen_id,user_id,role) values(k,u,'owner');return jsonb_build_object('kitchen_id',k);
end $$;

create function app_private.cc_sync_push(p_kitchen uuid,p_device uuid,p_operations jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.require_member(p_kitchen,true);op jsonb;oid uuid;aid uuid;base bigint;r public.cc_aggregates;rev bigint;n bigint;res jsonb;cached jsonb;request jsonb;accepted jsonb:='[]';conflicts jsonb:='[]';typ text;kind text;dat jsonb;stamp timestamptz;begin
 if jsonb_typeof(p_operations)<>'array' or jsonb_array_length(p_operations)>100 or octet_length(p_operations::text)>1048576 then raise exception 'INVALID_BATCH';end if;
 -- Serializing each kitchen also prevents op-id races and establishes committed change order.
 perform 1 from public.cc_kitchens where id=p_kitchen for update;
 for op in select value from jsonb_array_elements(p_operations) loop
 begin
 oid:=(op->>'operation_id')::uuid;aid:=(op->>'aggregate_id')::uuid;base:=(op->>'base_revision')::bigint;typ:=op->>'type';
 if oid is null or aid is null or base is null or base<0 then raise exception 'INVALID_OPERATION';end if;
 request:=jsonb_build_object('kitchen_id',p_kitchen,'device_id',p_device,'operation',op);
 cached:=app_private.replay(oid,request);
 if cached is not null then accepted:=accepted||jsonb_build_array(cached);continue;end if;
 select * into r from public.cc_aggregates where id=aid for update;
 if found and r.kitchen_id<>p_kitchen then raise exception using errcode='42501',message='CROSS_KITCHEN_ENTITY';end if;
 if found and r.deleted_at is not null then raise exception using errcode='23505',message='TOMBSTONE_WINS';end if;
 if coalesce(r.revision,0)<>base then raise exception using errcode='23505',message='REVISION_CONFLICT';end if;
 rev:=base+1;
 if typ='Upsert' then
 kind:=op->>'kind';dat:=op->'data';
 if kind is null or dat is null or jsonb_typeof(dat)<>'object' then raise exception 'INVALID_AGGREGATE';end if;
 if base>0 and r.kind<>kind then raise exception 'KIND_IMMUTABLE';end if;
 if dat ?| array['kitchen_id','created_by','actor_id','entitlements','moderator_role','approved','tested','reviewed_by'] then raise exception 'PRIVILEGED_FIELD';end if;
 insert into public.cc_aggregates(id,kitchen_id,kind,revision,data,created_by) values(aid,p_kitchen,kind,rev,dat,u)
 on conflict(id) do update set revision=rev,data=excluded.data,updated_at=now();
 n:=app_private.change(p_kitchen,aid,kind,rev,'upsert',jsonb_build_object('data',dat,'schema_version',coalesce((op->>'schema_version')::integer,1)));
 elsif typ='Delete' and base>0 then
 update public.cc_aggregates set deleted_at=now(),revision=rev,updated_at=now() where id=aid;
 n:=app_private.change(p_kitchen,aid,r.kind,rev,'tombstone','{}');
 elsif typ in ('StepStarted','StepCompleted','StepCorrected','ObservationRecorded','FeedRecorded','FeedCorrected','NoteRecorded','PantryConsumed','OutcomeRecorded','HandoffAcknowledged') and base>0 then
 stamp:=coalesce((op->>'occurred_at')::timestamptz,now());
 if stamp>now()+interval '5 minutes' then raise exception 'CLOCK_SKEW_DETECTED';end if;
 dat:=op->'payload';if dat is null or jsonb_typeof(dat)<>'object' then raise exception 'INVALID_EVENT';end if;
 if typ='StepCompleted' and (dat->>'step_id' is null or exists(select 1 from public.cc_domain_events where aggregate_id=aid and type='StepCompleted' and payload->>'step_id'=dat->>'step_id')) then raise exception using errcode='23505',message='DUPLICATE_PHYSICAL_ACTION_REVIEW';end if;
 insert into public.cc_domain_events(event_id,kitchen_id,aggregate_id,aggregate_revision,operation_id,type,payload,actor_id,device_id,occurred_at) values(coalesce((op->>'event_id')::uuid,oid),p_kitchen,aid,rev,oid,typ,dat,u,p_device,stamp);
 update public.cc_aggregates set revision=rev,updated_at=now() where id=aid;
 n:=app_private.change(p_kitchen,aid,r.kind,rev,'event',jsonb_build_object('type',typ,'payload',dat,'occurred_at',stamp,'actor_id',u,'event_id',coalesce(op->>'event_id',oid::text)));
 else raise exception 'UNSUPPORTED_OPERATION';end if;
 res:=jsonb_build_object('operation_id',oid,'revision',rev,'change_sequence',n);
 perform app_private.remember(oid,request,res);accepted:=accepted||jsonb_build_array(res);
 exception when others then
 conflicts:=conflicts||jsonb_build_array(jsonb_build_object('operation_id',op->>'operation_id','code',SQLERRM,'current_revision',(select revision from public.cc_aggregates where id=aid and kitchen_id=p_kitchen)));
 end;end loop;
 return jsonb_build_object('accepted',accepted,'conflicts',conflicts,'next_cursor',(select change_sequence from public.cc_kitchens where id=p_kitchen));
end $$;

create function app_private.cc_sync_pull(p_kitchen uuid,p_cursor bigint default 0,p_limit integer default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb;n bigint;begin
 perform app_private.require_member(p_kitchen);
 if p_cursor<0 or p_limit<1 or p_limit>500 then raise exception 'INVALID_CURSOR';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by sequence),'[]'),coalesce(max(sequence),p_cursor) into rows,n from(select sequence,entity_id as id,kind,revision,operation,payload from public.cc_sync_changes where kitchen_id=p_kitchen and sequence>p_cursor order by sequence limit p_limit)x;
 return jsonb_build_object('changes',rows,'next_cursor',n,'has_more',exists(select 1 from public.cc_sync_changes where kitchen_id=p_kitchen and sequence>n),'membership_revision',(select membership_revision from public.cc_kitchens where id=p_kitchen));
end $$;

create function app_private.cc_accept_plan(p_kitchen uuid,p_bake uuid,p_operation uuid,p_expected_revision bigint,p_snapshot jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.require_member(p_kitchen,true);r public.cc_aggregates;sid uuid:=gen_random_uuid();task jsonb;reservation jsonb;a timestamptz;b timestamptz;request jsonb;res jsonb;cached jsonb;n bigint;begin
 perform 1 from public.cc_kitchens where id=p_kitchen for update;
 request:=jsonb_build_object('kitchen',p_kitchen,'bake',p_bake,'revision',p_expected_revision,'snapshot',p_snapshot);cached:=app_private.replay(p_operation,request);if cached is not null then return cached;end if;
 select * into r from public.cc_aggregates where id=p_bake and kitchen_id=p_kitchen and deleted_at is null for update;
 if not found or r.kind<>'bake' then raise exception 'BAKE_NOT_FOUND';end if;
 if r.revision<>p_expected_revision then raise exception using errcode='23505',message='REVISION_CONFLICT';end if;
 if jsonb_typeof(p_snapshot->'tasks')<>'array' or jsonb_typeof(p_snapshot->'reservations')<>'array' or length(coalesce(p_snapshot->>'engine_version',''))=0 then raise exception 'INVALID_SCHEDULE';end if;
 if jsonb_array_length(p_snapshot->'tasks')>400 or jsonb_array_length(p_snapshot->'reservations')>400 then raise exception 'SCHEDULE_TOO_LARGE';end if;
 -- A completed step cannot reappear as future work; event history is immutable.
 for task in select value from jsonb_array_elements(p_snapshot->'tasks') loop
 a:=(task->>'start_at')::timestamptz;b:=(task->>'finish_at')::timestamptz;
 if a is null or b is null or b<a or task->>'step_id' is null then raise exception 'INVALID_TASK';end if;
 if exists(select 1 from public.cc_domain_events where aggregate_id=p_bake and type='StepCompleted' and payload->>'step_id'=task->>'step_id') then raise exception 'COMPLETED_HISTORY_IMMUTABLE';end if;
 end loop;
 -- Kitchen lock serializes all plan acceptances, so overlap check and insertion are atomic.
 for reservation in select value from jsonb_array_elements(p_snapshot->'reservations') loop
 a:=(reservation->>'start_at')::timestamptz;b:=(reservation->>'finish_at')::timestamptz;
 if a is null or b is null or b<=a or coalesce((reservation->>'slot')::integer,1)<1 then raise exception 'INVALID_RESERVATION';end if;
 if coalesce((reservation->>'slot')::integer,1)>coalesce((select least(50,greatest(1,(a.data->>'capacity')::integer)) from public.cc_aggregates a where a.kitchen_id=p_kitchen and a.kind='equipment' and a.deleted_at is null and (a.id::text=reservation->>'resource_id' or a.data->>'resource_id'=reservation->>'resource_id') limit 1),1) then raise exception 'RESOURCE_CAPACITY_CONFLICT';end if;
 if exists(select 1 from public.cc_resource_reservations q join public.cc_schedules s on s.id=q.schedule_id where q.kitchen_id=p_kitchen and q.resource_id=reservation->>'resource_id' and q.slot=coalesce((reservation->>'slot')::integer,1) and s.status='accepted' and s.bake_id<>p_bake and q.start_at<b and a<q.finish_at) then raise exception using errcode='23505',message='RESOURCE_CAPACITY_CONFLICT';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_snapshot->'reservations') with ordinality a(value,n) join jsonb_array_elements(p_snapshot->'reservations') with ordinality b(value,n) on a.n<b.n and a.value->>'resource_id'=b.value->>'resource_id' and coalesce((a.value->>'slot')::integer,1)=coalesce((b.value->>'slot')::integer,1) and (a.value->>'start_at')::timestamptz<(b.value->>'finish_at')::timestamptz and (b.value->>'start_at')::timestamptz<(a.value->>'finish_at')::timestamptz) then raise exception 'RESOURCE_CAPACITY_CONFLICT';end if;
 update public.cc_schedules set status='superseded' where bake_id=p_bake and status='accepted';
 update public.cc_reminders set status='superseded' where aggregate_id=p_bake and status='pending';
 insert into public.cc_schedules(id,kitchen_id,bake_id,version,status,engine_version,snapshot,created_by) values(sid,p_kitchen,p_bake,r.revision+1,'accepted',p_snapshot->>'engine_version',p_snapshot,u);
 for reservation in select value from jsonb_array_elements(p_snapshot->'reservations') loop
 insert into public.cc_resource_reservations(kitchen_id,schedule_id,resource_id,slot,start_at,finish_at) values(p_kitchen,sid,reservation->>'resource_id',coalesce((reservation->>'slot')::integer,1),(reservation->>'start_at')::timestamptz,(reservation->>'finish_at')::timestamptz);end loop;
 for task in select value from jsonb_array_elements(p_snapshot->'tasks') loop
 insert into public.cc_reminders(kitchen_id,aggregate_id,schedule_id,due_at,task_id) values(p_kitchen,p_bake,sid,(task->>'start_at')::timestamptz,task->>'step_id');end loop;
 update public.cc_aggregates set revision=revision+1,updated_at=now() where id=p_bake;
 n:=app_private.change(p_kitchen,p_bake,'bake',r.revision+1,'schedule',jsonb_build_object('schedule_id',sid,'snapshot',p_snapshot));
 res:=jsonb_build_object('schedule_id',sid,'bake_revision',r.revision+1,'change_sequence',n);
 return app_private.remember(p_operation,request,res);
end $$;
create function app_private.cc_create_invite(p_kitchen uuid,p_role text,p_expires_seconds integer default 604800) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.require_member(p_kitchen,true,true);token text:=gen_random_uuid()::text||gen_random_uuid()::text;i uuid;begin
 if p_role not in ('viewer','editor','admin') or p_expires_seconds not between 60 and 604800 then raise exception 'INVALID_INVITE';end if;
 insert into app_private.invites(kitchen_id,token_hash,role,created_by,expires_at) values(p_kitchen,app_private.hash_token(token),p_role,u,now()+make_interval(secs=>p_expires_seconds)) returning id into i;
 return jsonb_build_object('invite_id',i,'token',token,'expires_in_seconds',p_expires_seconds);
end $$;
create function app_private.cc_redeem_invite(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();i app_private.invites;begin
 select * into i from app_private.invites where token_hash=app_private.hash_token(p_token) for update;
 if not found or i.revoked_at is not null or i.expires_at<=now() or i.redeemed_by is not null then raise exception 'INVITE_INVALID_OR_EXPIRED';end if;
 if exists(select 1 from public.cc_kitchens where id=i.kitchen_id and deleted_at is not null) then raise exception 'INVITE_INVALID_OR_EXPIRED';end if;
 insert into public.cc_memberships(kitchen_id,user_id,role) values(i.kitchen_id,u,i.role) on conflict(kitchen_id,user_id) do update set role=case when cc_memberships.role='owner' then 'owner' else excluded.role end,status='active',revoked_at=null;
 update app_private.invites set redeemed_by=u where id=i.id;
 update public.cc_kitchens set membership_revision=membership_revision+1 where id=i.kitchen_id;
 return jsonb_build_object('kitchen_id',i.kitchen_id,'role',i.role);
end $$;
create function app_private.cc_revoke_member(p_kitchen uuid,p_user uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.require_member(p_kitchen,true,true);begin
 perform 1 from public.cc_kitchens where id=p_kitchen for update;
 if exists(select 1 from public.cc_kitchens where id=p_kitchen and owner_id=p_user) then raise exception 'OWNER_TRANSFER_REQUIRED';end if;
 update public.cc_memberships set status='revoked',revoked_at=now() where kitchen_id=p_kitchen and user_id=p_user;
 update public.cc_kitchens set membership_revision=membership_revision+1 where id=p_kitchen;
 insert into app_private.audit_events(actor_id,action,target_id) values(u,'member_revoked',p_user);
 return jsonb_build_object('revoked',true);
end $$;
create function app_private.cc_create_share(p_kitchen uuid,p_aggregate uuid,p_fields text[],p_expires_at timestamptz default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.require_member(p_kitchen,true);r public.cc_aggregates;snapshot jsonb;token text:=gen_random_uuid()::text||gen_random_uuid()::text;cid uuid;begin
 select * into r from public.cc_aggregates where id=p_aggregate and kitchen_id=p_kitchen and deleted_at is null;
 if not found then raise exception 'SOURCE_NOT_FOUND';end if;
 if cardinality(p_fields)>20 or not p_fields<@array['title','name','formula','ingredients','steps','notes','outcome','hydration','yield','attribution'] then raise exception 'SHARE_FIELD_FORBIDDEN';end if;
 select coalesce(jsonb_object_agg(key,value),'{}') into snapshot from jsonb_each(r.data) where key=any(p_fields);
 snapshot:=jsonb_build_object('kind',r.kind,'source_id',r.id,'source_revision',r.revision,'data',snapshot);
 insert into public.cc_shared_cards(owner_id,kitchen_id,snapshot,expires_at) values(u,p_kitchen,snapshot,p_expires_at) returning id into cid;
 insert into app_private.share_tokens(card_id,token_hash) values(cid,app_private.hash_token(token));
 return jsonb_build_object('share_id',cid,'token',token,'snapshot',snapshot);
end $$;
create function app_private.cc_read_share(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare snapshot jsonb;begin
 perform app_private.actor();
 select c.snapshot into snapshot from public.cc_shared_cards c join app_private.share_tokens t on t.card_id=c.id join public.cc_profiles p on p.id=c.owner_id where t.token_hash=app_private.hash_token(p_token) and c.revoked_at is null and (c.expires_at is null or c.expires_at>now()) and p.account_state='active' and not exists(select 1 from public.cc_blocks b where (b.user_id=auth.uid() and b.blocked_user_id=c.owner_id) or (b.blocked_user_id=auth.uid() and b.user_id=c.owner_id));
 if snapshot is null then raise exception 'SHARE_INVALID_OR_EXPIRED';end if;return snapshot;
end $$;
create function app_private.cc_revoke_share(p_share uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();begin
 update public.cc_shared_cards set revoked_at=now() where id=p_share and owner_id=u;
 if not found then raise exception 'SHARE_NOT_FOUND';end if;return jsonb_build_object('revoked',true);
end $$;
create function app_private.cc_enqueue_job(p_operation uuid,p_kind text,p_input jsonb,p_kitchen uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();j uuid;req jsonb;cached jsonb;begin
 if p_kitchen is not null then perform app_private.require_member(p_kitchen);end if;
 if p_kind not in ('coach','import','image','export') then raise exception 'INVALID_JOB';end if;
 -- Identity-level advisory lock makes quotas/idempotency checks atomic across kitchens.
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 req:=jsonb_build_object('kind',p_kind,'input',p_input,'kitchen_id',p_kitchen);cached:=app_private.replay(p_operation,req);if cached is not null then return cached;end if;
 if p_kind in ('coach','image','import') and not exists(select 1 from public.cc_consents where user_id=u and purpose=p_kind and version=p_input->>'consent_version' and revoked_at is null) then raise exception 'CONSENT_REQUIRED';end if;
 if (select count(*) from public.cc_jobs where user_id=u and kind=p_kind and created_at>now()-interval '1 day')>=(case when p_kind='export' then 10 else 20 end) then raise exception 'QUOTA_EXHAUSTED';end if;
 insert into public.cc_jobs(user_id,kitchen_id,kind,input) values(u,p_kitchen,p_kind,p_input) returning id into j;
 return app_private.remember(p_operation,req,jsonb_build_object('job_id',j,'status','queued'));
end $$;
create function app_private.cc_grant_consent(p_purpose text,p_version text,p_granted boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();begin
 if p_purpose not in ('coach','import','image','sync','analytics') or length(p_version) not between 1 and 50 then raise exception 'INVALID_CONSENT';end if;
 insert into public.cc_consents(user_id,purpose,version,revoked_at) values(u,p_purpose,p_version,case when p_granted then null else now() end) on conflict(user_id,purpose,version) do update set revoked_at=excluded.revoked_at;
 return jsonb_build_object('purpose',p_purpose,'granted',p_granted);
end $$;
create function app_private.cc_report(p_type text,p_target uuid,p_reason text,p_details text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();r uuid;begin
 if (select count(*) from public.cc_reports where user_id=u and created_at>now()-interval '1 hour')>=20 then raise exception 'REPORT_RATE_LIMIT';end if;
 if p_type='coach' and not exists(select 1 from public.cc_jobs where id=p_target and user_id=u) then raise exception 'TARGET_NOT_FOUND';end if;
 if p_type='share' and not exists(select 1 from public.cc_shared_cards where id=p_target and revoked_at is null) then raise exception 'TARGET_NOT_FOUND';end if;
 insert into public.cc_reports(user_id,target_type,target_id,reason,details) values(u,p_type,p_target,p_reason,p_details) returning id into r;return jsonb_build_object('report_id',r,'status','pending');
end $$;
create function app_private.cc_block(p_user uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();begin insert into public.cc_blocks(user_id,blocked_user_id) values(u,p_user) on conflict do nothing;return jsonb_build_object('blocked',true);end $$;
create function app_private.cc_request_delete() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();j uuid;begin
 if exists(select 1 from public.cc_kitchens k join public.cc_memberships m on m.kitchen_id=k.id where k.owner_id=u and k.kind<>'personal' and k.deleted_at is null and m.user_id<>u and m.status='active') then raise exception 'OWNERSHIP_TRANSFER_REQUIRED';end if;
 insert into public.cc_jobs(user_id,kind,input) values(u,'delete_account','{}') returning id into j;
 update public.cc_profiles set account_state='deleting' where id=u;
 update public.cc_shared_cards set revoked_at=now() where owner_id=u and revoked_at is null;
 insert into app_private.audit_events(actor_id,action,target_id) values(u,'deletion_requested',u);
 return jsonb_build_object('deletion_job_id',j,'status','queued','access_revoked',true);
end $$;

-- RLS for every exposed table, read-only grants. Mutation exclusively through commands.
do $$declare t text;begin
 foreach t in array array['cc_profiles','cc_kitchens','cc_memberships','cc_aggregates','cc_domain_events','cc_sync_changes','cc_schedules','cc_resource_reservations','cc_reminders','cc_shared_cards','cc_jobs','cc_reports','cc_blocks','cc_media','cc_consents','cc_entitlements'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
create policy cc_profile_self on public.cc_profiles for select to authenticated using(id=auth.uid());
create policy cc_kitchen_read on public.cc_kitchens for select to authenticated using(app_private.member(id));
create policy cc_member_read on public.cc_memberships for select to authenticated using(app_private.member(kitchen_id));
do $$declare t text;begin
 foreach t in array array['cc_aggregates','cc_domain_events','cc_sync_changes','cc_schedules','cc_resource_reservations','cc_reminders','cc_media'] loop
 execute format('create policy tenant_read on public.%I for select to authenticated using(app_private.member(kitchen_id))',t);
 end loop;
end $$;
create policy cc_shares_owner on public.cc_shared_cards for select to authenticated using(owner_id=auth.uid() and app_private.member(kitchen_id));
create policy cc_jobs_owner on public.cc_jobs for select to authenticated using(user_id=auth.uid());
create policy cc_reports_owner on public.cc_reports for select to authenticated using(user_id=auth.uid());
create policy cc_blocks_owner on public.cc_blocks for select to authenticated using(user_id=auth.uid());
create policy cc_consents_owner on public.cc_consents for select to authenticated using(user_id=auth.uid());
create policy cc_entitlements_owner on public.cc_entitlements for select to authenticated using(user_id=auth.uid());
-- No inherited PUBLIC EXECUTE on privileged commands or helpers.
revoke all on all tables in schema app_private from public,anon,authenticated;
revoke execute on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.member(uuid,boolean,boolean) to authenticated;
do $$declare f record;begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'cc\_%' escape '\' loop
 execute format('revoke execute on function %s from public,anon',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;

-- Server-worker RPCs are granted only to service_role. They never ship in clients.
alter table public.cc_jobs add column lease_token uuid;
create function app_private.cc_worker_claim(p_limit integer default 5) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if p_limit not between 1 and 20 then raise exception 'INVALID_LIMIT';end if;
 update public.cc_jobs set status='failed',error_code='RETRY_EXHAUSTED',lease_until=null where attempt>=3 and (status='queued' or(status='running' and lease_until<now()));
 with selected as(select id from public.cc_jobs where attempt<3 and expires_at>now() and ((status='queued' and available_at<=now()) or(status='running' and lease_until<now())) order by available_at for update skip locked limit p_limit), claimed as(update public.cc_jobs j set status='running',attempt=attempt+1,lease_until=now()+interval '2 minutes',lease_token=gen_random_uuid() from selected s where j.id=s.id returning j.*) select coalesce(jsonb_agg(to_jsonb(c)),'[]') into result from claimed c;return result;
end $$;
create function app_private.cc_worker_finish(p_job uuid,p_lease uuid,p_result jsonb default null,p_error text default null,p_retry boolean default false) returns boolean language plpgsql security definer set search_path='' as $$begin
 update public.cc_jobs set status=case when p_error is null then 'complete' when p_retry and attempt<3 then 'queued' else 'failed' end,result=p_result,error_code=p_error,lease_until=null,lease_token=null,available_at=now()+make_interval(secs=>least(300,attempt*30)) where id=p_job and lease_token=p_lease and status='running' and lease_until>now();return found;
end $$;

-- Exposed invoker wrappers: privileged implementation remains unexposed.
create function public.cc_bootstrap(p_name text default null) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_bootstrap(p_name)$$;
revoke execute on function public.cc_bootstrap(text) from public,anon,authenticated;
grant execute on function public.cc_bootstrap(text) to authenticated;
revoke execute on function app_private.cc_bootstrap(text) from public,anon,authenticated;
grant execute on function app_private.cc_bootstrap(text) to authenticated;
create function public.cc_create_kitchen(p_kind text,p_name text) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_create_kitchen(p_kind,p_name)$$;
revoke execute on function public.cc_create_kitchen(text,text) from public,anon,authenticated;
grant execute on function public.cc_create_kitchen(text,text) to authenticated;
revoke execute on function app_private.cc_create_kitchen(text,text) from public,anon,authenticated;
grant execute on function app_private.cc_create_kitchen(text,text) to authenticated;
create function public.cc_sync_push(p_kitchen uuid,p_device uuid,p_operations jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_sync_push(p_kitchen,p_device,p_operations)$$;
revoke execute on function public.cc_sync_push(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.cc_sync_push(uuid,uuid,jsonb) to authenticated;
revoke execute on function app_private.cc_sync_push(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function app_private.cc_sync_push(uuid,uuid,jsonb) to authenticated;
create function public.cc_sync_pull(p_kitchen uuid,p_cursor bigint default 0,p_limit integer default 100) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_sync_pull(p_kitchen,p_cursor,p_limit)$$;
revoke execute on function public.cc_sync_pull(uuid,bigint,integer) from public,anon,authenticated;
grant execute on function public.cc_sync_pull(uuid,bigint,integer) to authenticated;
revoke execute on function app_private.cc_sync_pull(uuid,bigint,integer) from public,anon,authenticated;
grant execute on function app_private.cc_sync_pull(uuid,bigint,integer) to authenticated;
create function public.cc_accept_plan(p_kitchen uuid,p_bake uuid,p_operation uuid,p_expected_revision bigint,p_snapshot jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_accept_plan(p_kitchen,p_bake,p_operation,p_expected_revision,p_snapshot)$$;
revoke execute on function public.cc_accept_plan(uuid,uuid,uuid,bigint,jsonb) from public,anon,authenticated;
grant execute on function public.cc_accept_plan(uuid,uuid,uuid,bigint,jsonb) to authenticated;
revoke execute on function app_private.cc_accept_plan(uuid,uuid,uuid,bigint,jsonb) from public,anon,authenticated;
grant execute on function app_private.cc_accept_plan(uuid,uuid,uuid,bigint,jsonb) to authenticated;
create function public.cc_create_invite(p_kitchen uuid,p_role text,p_expires_seconds integer default 604800) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_create_invite(p_kitchen,p_role,p_expires_seconds)$$;
revoke execute on function public.cc_create_invite(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.cc_create_invite(uuid,text,integer) to authenticated;
revoke execute on function app_private.cc_create_invite(uuid,text,integer) from public,anon,authenticated;
grant execute on function app_private.cc_create_invite(uuid,text,integer) to authenticated;
create function public.cc_redeem_invite(p_token text) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_redeem_invite(p_token)$$;
revoke execute on function public.cc_redeem_invite(text) from public,anon,authenticated;
grant execute on function public.cc_redeem_invite(text) to authenticated;
revoke execute on function app_private.cc_redeem_invite(text) from public,anon,authenticated;
grant execute on function app_private.cc_redeem_invite(text) to authenticated;
create function public.cc_revoke_member(p_kitchen uuid,p_user uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_revoke_member(p_kitchen,p_user)$$;
revoke execute on function public.cc_revoke_member(uuid,uuid) from public,anon,authenticated;
grant execute on function public.cc_revoke_member(uuid,uuid) to authenticated;
revoke execute on function app_private.cc_revoke_member(uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.cc_revoke_member(uuid,uuid) to authenticated;
create function public.cc_create_share(p_kitchen uuid,p_aggregate uuid,p_fields text[],p_expires_at timestamptz default null) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_create_share(p_kitchen,p_aggregate,p_fields,p_expires_at)$$;
revoke execute on function public.cc_create_share(uuid,uuid,text[],timestamptz) from public,anon,authenticated;
grant execute on function public.cc_create_share(uuid,uuid,text[],timestamptz) to authenticated;
revoke execute on function app_private.cc_create_share(uuid,uuid,text[],timestamptz) from public,anon,authenticated;
grant execute on function app_private.cc_create_share(uuid,uuid,text[],timestamptz) to authenticated;
create function public.cc_read_share(p_token text) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_read_share(p_token)$$;
revoke execute on function public.cc_read_share(text) from public,anon,authenticated;
grant execute on function public.cc_read_share(text) to authenticated;
revoke execute on function app_private.cc_read_share(text) from public,anon,authenticated;
grant execute on function app_private.cc_read_share(text) to authenticated;
create function public.cc_revoke_share(p_share uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_revoke_share(p_share)$$;
revoke execute on function public.cc_revoke_share(uuid) from public,anon,authenticated;
grant execute on function public.cc_revoke_share(uuid) to authenticated;
revoke execute on function app_private.cc_revoke_share(uuid) from public,anon,authenticated;
grant execute on function app_private.cc_revoke_share(uuid) to authenticated;
create function public.cc_enqueue_job(p_operation uuid,p_kind text,p_input jsonb,p_kitchen uuid default null) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_enqueue_job(p_operation,p_kind,p_input,p_kitchen)$$;
revoke execute on function public.cc_enqueue_job(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.cc_enqueue_job(uuid,text,jsonb,uuid) to authenticated;
revoke execute on function app_private.cc_enqueue_job(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function app_private.cc_enqueue_job(uuid,text,jsonb,uuid) to authenticated;
create function public.cc_grant_consent(p_purpose text,p_version text,p_granted boolean) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_grant_consent(p_purpose,p_version,p_granted)$$;
revoke execute on function public.cc_grant_consent(text,text,boolean) from public,anon,authenticated;
grant execute on function public.cc_grant_consent(text,text,boolean) to authenticated;
revoke execute on function app_private.cc_grant_consent(text,text,boolean) from public,anon,authenticated;
grant execute on function app_private.cc_grant_consent(text,text,boolean) to authenticated;
create function public.cc_report(p_type text,p_target uuid,p_reason text,p_details text default null) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_report(p_type,p_target,p_reason,p_details)$$;
revoke execute on function public.cc_report(text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.cc_report(text,uuid,text,text) to authenticated;
revoke execute on function app_private.cc_report(text,uuid,text,text) from public,anon,authenticated;
grant execute on function app_private.cc_report(text,uuid,text,text) to authenticated;
create function public.cc_block(p_user uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_block(p_user)$$;
revoke execute on function public.cc_block(uuid) from public,anon,authenticated;
grant execute on function public.cc_block(uuid) to authenticated;
revoke execute on function app_private.cc_block(uuid) from public,anon,authenticated;
grant execute on function app_private.cc_block(uuid) to authenticated;
create function public.cc_request_delete() returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_request_delete()$$;
revoke execute on function public.cc_request_delete() from public,anon,authenticated;
grant execute on function public.cc_request_delete() to authenticated;
revoke execute on function app_private.cc_request_delete() from public,anon,authenticated;
grant execute on function app_private.cc_request_delete() to authenticated;
create function public.cc_worker_claim(p_limit integer default 5) returns jsonb language sql security invoker set search_path='' as $$select app_private.cc_worker_claim(p_limit)$$;
revoke execute on function public.cc_worker_claim(integer) from public,anon,authenticated;
grant execute on function public.cc_worker_claim(integer) to service_role;
revoke execute on function app_private.cc_worker_claim(integer) from public,anon,authenticated;
grant execute on function app_private.cc_worker_claim(integer) to service_role;
create function public.cc_worker_finish(p_job uuid,p_lease uuid,p_result jsonb default null,p_error text default null,p_retry boolean default false) returns boolean language sql security invoker set search_path='' as $$select app_private.cc_worker_finish(p_job,p_lease,p_result,p_error,p_retry)$$;
revoke execute on function public.cc_worker_finish(uuid,uuid,jsonb,text,boolean) from public,anon,authenticated;
grant execute on function public.cc_worker_finish(uuid,uuid,jsonb,text,boolean) to service_role;
revoke execute on function app_private.cc_worker_finish(uuid,uuid,jsonb,text,boolean) from public,anon,authenticated;
grant execute on function app_private.cc_worker_finish(uuid,uuid,jsonb,text,boolean) to service_role;
