-- Verification-only heartbeat. Never reads, claims or processes cc_jobs.
-- Purpose is authenticated cryptographically, not selected by a request body.
alter table app_private.worker_dispatches add column purpose text not null default 'jobs'check(purpose in('jobs','heartbeat'));
create function app_private.cc_worker_authorize_health(p_token text)returns boolean language plpgsql security definer set search_path=''as $$
declare parts text[];stamp bigint;dispatch app_private.worker_dispatches;expected bytea;provided bytea;difference integer:=0;i integer;begin
 if coalesce(current_setting('role',true),'')<>'service_role'or coalesce(auth.jwt()->>'role','')<>'service_role'then raise exception using errcode='42501',message='WORKER_SERVER_ROLE_REQUIRED';end if;
 if p_token is null or length(p_token)>240 or p_token!~'^v2\.heartbeat\.[0-9]{10}\.[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9a-f]{64}$'then return false;end if;
 parts:=string_to_array(p_token,'.');stamp:=parts[3]::bigint;
 if abs(extract(epoch from now())-stamp)>120 then return false;end if;
 select * into dispatch from app_private.worker_dispatches where nonce=parts[4]::uuid and purpose='heartbeat'for update;
 if not found or dispatch.used_at is not null or dispatch.expires_at<=now()or extract(epoch from dispatch.issued_at)::bigint<>stamp then return false;end if;
 expected:=app_private.worker_signature('v2.heartbeat.'||parts[3]||'.'||parts[4]);provided:=decode(parts[5],'hex');
 for i in 0..31 loop difference:=difference|(get_byte(expected,i)#get_byte(provided,i));end loop;
 if difference<>0 then return false;end if;
 update app_private.worker_dispatches set used_at=now()where nonce=dispatch.nonce;
 return true;
end $$;
create function public.cc_worker_authorize_health(p_token text)returns boolean language sql security invoker set search_path=''as $$select app_private.cc_worker_authorize_health(p_token)$$;
revoke execute on function public.cc_worker_authorize_health(text),app_private.cc_worker_authorize_health(text)from public,anon,authenticated,service_role;
grant execute on function public.cc_worker_authorize_health(text),app_private.cc_worker_authorize_health(text)to service_role;
create function app_private.cc_worker_heartbeat()returns bigint language plpgsql security definer set search_path=''as $$
declare nonce uuid:=gen_random_uuid();stamp bigint:=floor(extract(epoch from now()))::bigint;message text;capability text;request_id bigint;begin
 message:='v2.heartbeat.'||stamp::text||'.'||nonce::text;
 capability:=message||'.'||encode(app_private.worker_signature(message),'hex');
 insert into app_private.worker_dispatches(nonce,issued_at,expires_at,purpose)values(nonce,to_timestamp(stamp),to_timestamp(stamp)+interval '120 seconds','heartbeat');
 select net.http_post(
 url:='https://wpxeuwknbuxbtkkkmcsm.supabase.co/functions/v1/job-worker/health',
 headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||capability),
 body:='{"mode":"heartbeat"}'::jsonb,timeout_milliseconds:=20000
 )into request_id;
 return request_id;
end $$;
revoke all on function app_private.cc_worker_heartbeat()from public,anon,authenticated,service_role;
