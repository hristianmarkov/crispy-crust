create table public.crumb_clock_waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (email = lower(trim(email)) and length(email) <= 254),
  platform text not null check (platform in ('ios', 'android', 'both')),
  consent text not null default 'launch-updates-v1',
  created_at timestamptz not null default now()
);
alter table public.crumb_clock_waitlist enable row level security;
revoke all on public.crumb_clock_waitlist from anon, authenticated;
grant select, insert, delete on public.crumb_clock_waitlist to service_role;
create table public.crumb_clock_rate_limits (
  key text primary key,
  count integer not null,
  reset_at timestamptz not null
);
alter table public.crumb_clock_rate_limits enable row level security;
revoke all on public.crumb_clock_rate_limits from anon, authenticated;
grant select, insert, update, delete on public.crumb_clock_rate_limits to service_role;
create function public.crumb_clock_waitlist_request(p_email text, p_platform text, p_action text, p_rate_key text)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare attempts integer;
begin
  if p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or p_email <> lower(trim(p_email)) or p_action is null or p_action not in ('join','remove')
    or (p_action = 'join' and (p_platform is null or p_platform not in ('ios','android','both')))
    or p_rate_key is null or p_rate_key !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid waitlist request';
  end if;
  delete from public.crumb_clock_rate_limits where reset_at < now() - interval '1 minute';
  insert into public.crumb_clock_rate_limits as limits (key,count,reset_at)
    values (p_rate_key,1,now()+interval '1 minute')
    on conflict (key) do update set
      count = case when limits.reset_at < now() then 1 else limits.count+1 end,
      reset_at = case when limits.reset_at < now() then now()+interval '1 minute' else limits.reset_at end
    returning count into attempts;
  if attempts > 8 then return false; end if;
  if p_action = 'remove' then
    delete from public.crumb_clock_waitlist where email=p_email;
  else
    insert into public.crumb_clock_waitlist(email,platform) values(p_email,p_platform) on conflict(email) do nothing;
  end if;
  return true;
end;
$$;
revoke all on function public.crumb_clock_waitlist_request(text,text,text,text) from public, anon, authenticated;
grant execute on function public.crumb_clock_waitlist_request(text,text,text,text) to service_role;
-- Internal event trigger, not a public RPC.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
