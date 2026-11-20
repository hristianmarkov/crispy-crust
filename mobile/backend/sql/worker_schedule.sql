-- Deployment coordinator applies this only to the owner-approved shared project.
-- Job is installed INACTIVE. Activate only after the new worker is deployed and a
-- forced heartbeat is verified. No existing named cron jobs are altered.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create function app_private.cc_worker_dispatch(p_force boolean default false)returns bigint language plpgsql security definer set search_path=''as $$
declare nonce uuid:=gen_random_uuid();stamp bigint:=floor(extract(epoch from now()))::bigint;message text;capability text;request_id bigint;begin
 if not p_force and not exists(select 1 from public.cc_jobs where attempt<3 and expires_at>now()and((status='queued'and available_at<=now())or(status='running'and lease_until<now())))then return null;end if;
 delete from app_private.worker_dispatches where expires_at<now()-interval '1 hour';
 message:='v1.'||stamp::text||'.'||nonce::text;
 capability:=message||'.'||encode(app_private.worker_signature(message),'hex');
 insert into app_private.worker_dispatches(nonce,issued_at,expires_at)values(nonce,to_timestamp(stamp),to_timestamp(stamp)+interval '120 seconds');
 select net.http_post(
 url:='https://wpxeuwknbuxbtkkkmcsm.supabase.co/functions/v1/job-worker',
 headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||capability),
 body:=jsonb_build_object('dispatch_id',nonce,'version',1),timeout_milliseconds:=90000
 )into request_id;
 return request_id;
end $$;
revoke all on function app_private.cc_worker_dispatch(boolean)from public,anon,authenticated,service_role;
do $$declare own_job bigint;begin
 select cron.schedule('crispy-crust-mobile-job-worker-v1','* * * * *','select app_private.cc_worker_dispatch();')into own_job;
 perform cron.alter_job(own_job,active:=false);
end $$;
