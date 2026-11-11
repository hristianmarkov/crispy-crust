-- Vault-backed worker authentication. Long-lived signing material stays inside
-- Vault; pg_net receives only a short-lived, single-use HMAC capability.
-- Prerequisites: installed pgcrypto and supabase_vault (verified by coordinator).
do $$begin
 if not exists(select 1 from pg_extension where extname='pgcrypto')or to_regclass('vault.decrypted_secrets')is null then raise exception 'WORKER_VAULT_PREREQUISITES_MISSING';end if;
end $$;
create table app_private.worker_dispatches(
 nonce uuid primary key, issued_at timestamptz not null, expires_at timestamptz not null,
 used_at timestamptz, check(expires_at>issued_at)
);
revoke all on app_private.worker_dispatches from public,anon,authenticated,service_role;
-- Generate internally, encrypt internally, return no secret or secret identifier.
do $$declare crypto_schema text;material text;begin
 if not exists(select 1 from vault.decrypted_secrets where name='crispy_crust_worker_hmac_v1')then
 select n.nspname into crypto_schema from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
 execute format('select encode(%I.gen_random_bytes(32),''hex'')',crypto_schema)into material;
 perform vault.create_secret(material,'crispy_crust_worker_hmac_v1','Crispy Crust worker HMAC; never send this value as a bearer token');
 end if;
end $$;
create function app_private.worker_signature(p_message text)returns bytea language plpgsql security definer set search_path=''as $$
declare material text;crypto_schema text;signature bytea;begin
 select decrypted_secret into material from vault.decrypted_secrets where name='crispy_crust_worker_hmac_v1';
 if material is null then raise exception 'WORKER_SIGNING_KEY_MISSING';end if;
 select n.nspname into crypto_schema from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
 execute format('select %I.hmac(convert_to($1,''UTF8''),convert_to($2,''UTF8''),''sha256'')',crypto_schema)into signature using p_message,material;
 return signature;
end $$;
revoke all on function app_private.worker_signature(text)from public,anon,authenticated,service_role;
create function app_private.cc_worker_authorize(p_token text)returns boolean language plpgsql security definer set search_path=''as $$
declare parts text[];stamp bigint;dispatch app_private.worker_dispatches;expected bytea;provided bytea;difference integer:=0;i integer;begin
 -- Definer's current_user is its owner. Check the caller's selected database role
 -- AND the verified PostgREST JWT role, in addition to narrow EXECUTE grants.
 if coalesce(current_setting('role',true),'')<>'service_role'or coalesce(auth.jwt()->>'role','')<>'service_role'then raise exception using errcode='42501',message='WORKER_SERVER_ROLE_REQUIRED';end if;
 if p_token is null or length(p_token)>240 or p_token!~'^v1\.[0-9]{10}\.[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9a-f]{64}$'then return false;end if;
 parts:=string_to_array(p_token,'.');stamp:=parts[2]::bigint;
 if abs(extract(epoch from now())-stamp)>120 then return false;end if;
 select * into dispatch from app_private.worker_dispatches where nonce=parts[3]::uuid for update;
 if not found or dispatch.used_at is not null or dispatch.expires_at<=now()or extract(epoch from dispatch.issued_at)::bigint<>stamp then return false;end if;
 expected:=app_private.worker_signature(parts[1]||'.'||parts[2]||'.'||parts[3]);provided:=decode(parts[4],'hex');
 -- Fixed 32-byte comparison rather than a prefix-dependent string comparison.
 for i in 0..31 loop difference:=difference|(get_byte(expected,i)#get_byte(provided,i));end loop;
 if difference<>0 then return false;end if;
 update app_private.worker_dispatches set used_at=now()where nonce=dispatch.nonce;
 return true;
end $$;
create function public.cc_worker_authorize(p_token text)returns boolean language sql security invoker set search_path=''as $$select app_private.cc_worker_authorize(p_token)$$;
revoke execute on function public.cc_worker_authorize(text),app_private.cc_worker_authorize(text)from public,anon,authenticated,service_role;
grant execute on function public.cc_worker_authorize(text),app_private.cc_worker_authorize(text)to service_role;

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
