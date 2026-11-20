-- Calendar-month allowances use UTC and verified store entitlements, never client claims.
create or replace function app_private.cc_coach_usage() returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();pro boolean;used integer;cap integer;
 period_start timestamptz:=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
begin
 select exists(select 1 from public.cc_entitlements where user_id=u
  and entitlement_key='crispy_crust_pro' and provider='revenuecat'
  and state in ('active','trial','grace') and (valid_until is null or valid_until>now())) into pro;
 cap:=case when pro then 60 else 3 end;
 select count(*) into used from public.cc_jobs where user_id=u and kind='coach'
  and created_at>=period_start and created_at<period_start+interval '1 month';
 return jsonb_build_object('is_pro',pro,'limit',cap,'used',used,
  'remaining',greatest(0,cap-used),'resets_at',period_start+interval '1 month');
end $$;
revoke execute on function app_private.cc_coach_usage() from public,anon,authenticated;
grant execute on function app_private.cc_coach_usage() to authenticated;
create or replace function public.cc_coach_usage() returns jsonb language sql security invoker
set search_path='' as $$select app_private.cc_coach_usage()$$;
revoke execute on function public.cc_coach_usage() from public,anon,authenticated;
grant execute on function public.cc_coach_usage() to authenticated;

create or replace function app_private.cc_enqueue_job(p_operation uuid,p_kind text,p_input jsonb,p_kitchen uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=app_private.actor();j uuid;req jsonb;cached jsonb;begin
 if p_kitchen is not null then perform app_private.require_member(p_kitchen);end if;
 if p_kind not in ('coach','import','image','export') then raise exception 'INVALID_JOB';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 req:=jsonb_build_object('kind',p_kind,'input',p_input,'kitchen_id',p_kitchen);cached:=app_private.replay(p_operation,req);if cached is not null then return cached;end if;
 if p_kind in ('coach','image','import') and not exists(select 1 from public.cc_consents where user_id=u and purpose=p_kind and version=p_input->>'consent_version' and revoked_at is null) then raise exception 'CONSENT_REQUIRED';end if;
 if p_kind='coach' and (app_private.cc_coach_usage()->>'remaining')::integer=0 then raise exception 'COACH_MONTHLY_LIMIT';end if;
 if (select count(*) from public.cc_jobs where user_id=u and kind=p_kind and created_at>now()-interval '1 day')>=(case when p_kind='export' then 10 else 20 end) then raise exception 'QUOTA_EXHAUSTED';end if;
 insert into public.cc_jobs(user_id,kitchen_id,kind,input) values(u,p_kitchen,p_kind,p_input) returning id into j;
 return app_private.remember(p_operation,req,jsonb_build_object('job_id',j,'status','queued'));
end $$;
