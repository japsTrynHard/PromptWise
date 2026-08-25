-- Phase 9 source reliability, Verify API budget controls, and lower-traffic admin reads.

-- ---------------------------------------------------------------------------
-- 1. Direct Awareness discovery sources
-- ---------------------------------------------------------------------------
create table if not exists public.awareness_direct_sources (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  base_domain text not null,
  source_url text not null,
  source_type text not null default 'html_listing',
  region text not null default 'Global',
  trust_level integer not null default 80,
  priority integer not null default 50,
  relevance_keywords text[] not null default array[]::text[],
  enabled boolean not null default true,
  last_checked_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint awareness_direct_sources_type_check check (source_type in ('html_listing','rss')),
  constraint awareness_direct_sources_region_check check (region in ('Philippines','Global')),
  constraint awareness_direct_sources_trust_check check (trust_level between 1 and 100),
  constraint awareness_direct_sources_priority_check check (priority between 1 and 100)
);

create unique index if not exists uq_awareness_direct_sources_url
  on public.awareness_direct_sources (source_url);
create index if not exists idx_awareness_direct_sources_enabled_priority
  on public.awareness_direct_sources (enabled, priority desc);

alter table public.awareness_direct_sources enable row level security;
drop policy if exists awareness_direct_sources_admin_read on public.awareness_direct_sources;
create policy awareness_direct_sources_admin_read
  on public.awareness_direct_sources for select to authenticated
  using (public.awareness_is_admin());
revoke insert, update, delete on public.awareness_direct_sources from authenticated;
grant select on public.awareness_direct_sources to authenticated;

-- Remove obsolete direct-source rows from earlier Phase 9 development builds.
delete from public.awareness_direct_sources
where source_url in (
  'https://www.pna.gov.ph/categories/national',
  'https://www.gmanetwork.com/news/scitech/'
);

insert into public.awareness_direct_sources
  (name, base_domain, source_url, source_type, region, trust_level, priority, relevance_keywords)
values
  (
    'Philippine News Agency - Latest',
    'pna.gov.ph',
    'https://www.pna.gov.ph/latest.rss',
    'rss',
    'Philippines',
    100,
    100,
    array['ai','artificial intelligence','deepfake','cyber','scam','fraud','phishing','misinformation','disinformation','fake news','privacy','online','digital','impersonation']
  ),
  (
    'Philippine News Agency - Science and Technology',
    'pna.gov.ph',
    'https://www.pna.gov.ph/categories/science-and-technology',
    'html_listing',
    'Philippines',
    100,
    96,
    array['ai','artificial intelligence','deepfake','cyber','scam','misinformation','privacy','online safety','digital']
  ),
  (
    'GMA News - RSS',
    'gmanetwork.com',
    'https://data.gmanews.tv/gno/rss/news/feed.xml',
    'rss',
    'Philippines',
    90,
    94,
    array['ai','artificial intelligence','deepfake','cyber','scam','fraud','phishing','misinformation','fake news','privacy','online safety']
  ),
  (
    'GMA News - Money',
    'gmanetwork.com',
    'https://www.gmanetwork.com/news/money/',
    'html_listing',
    'Philippines',
    88,
    82,
    array['scam','fraud','phishing','investment scam','online scam','identity theft','digital fraud','cyber']
  ),
  (
    'CISA Cybersecurity Advisories',
    'cisa.gov',
    'https://www.cisa.gov/cybersecurity-advisories/all.xml',
    'rss',
    'Global',
    98,
    76,
    array['phishing','ransomware','malware','cybersecurity','credential','social engineering','identity','fraud']
  ),
  (
    'FTC Consumer Alerts',
    'consumer.ftc.gov',
    'https://consumer.ftc.gov/consumer-alerts',
    'html_listing',
    'Global',
    98,
    74,
    array['scam','fraud','impersonation','phishing','identity theft','privacy','ai','deepfake','online']
  )
on conflict (source_url) do update set
  name = excluded.name,
  base_domain = excluded.base_domain,
  source_type = excluded.source_type,
  region = excluded.region,
  trust_level = excluded.trust_level,
  priority = excluded.priority,
  relevance_keywords = excluded.relevance_keywords,
  enabled = true,
  updated_at = now();

-- Direct sources are cheap enough to check first; broad discovery becomes a fallback.
alter table public.awareness_feed_settings
  add column if not exists direct_source_limit integer not null default 6,
  add column if not exists min_direct_candidates_before_fallback integer not null default 8,
  add column if not exists min_ph_direct_candidates_before_fallback integer not null default 3,
  add column if not exists article_snapshot_hours integer not null default 24;

-- ---------------------------------------------------------------------------
-- 2. Verify automation budget controls (mirrors Learning Studio)
-- ---------------------------------------------------------------------------
alter table public.verification_automation_settings
  add column if not exists max_articles_per_run integer not null default 6,
  add column if not exists max_drafts_per_run integer not null default 2,
  add column if not exists max_drafts_per_day integer not null default 4,
  add column if not exists monthly_draft_cap integer not null default 40,
  add column if not exists monthly_groq_request_cap integer not null default 80;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'verification_automation_settings_articles_run_check') then
    alter table public.verification_automation_settings
      add constraint verification_automation_settings_articles_run_check
      check (max_articles_per_run between 1 and 20);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'verification_automation_settings_drafts_run_check') then
    alter table public.verification_automation_settings
      add constraint verification_automation_settings_drafts_run_check
      check (max_drafts_per_run between 1 and 10);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'verification_automation_settings_drafts_day_check') then
    alter table public.verification_automation_settings
      add constraint verification_automation_settings_drafts_day_check
      check (max_drafts_per_day between 1 and 50);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'verification_automation_settings_monthly_cap_check') then
    alter table public.verification_automation_settings
      add constraint verification_automation_settings_monthly_cap_check
      check (monthly_draft_cap between 1 and 1000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'verification_automation_settings_groq_monthly_cap_check') then
    alter table public.verification_automation_settings
      add constraint verification_automation_settings_groq_monthly_cap_check
      check (monthly_groq_request_cap between 1 and 5000);
  end if;
end $$;

create table if not exists public.verification_groq_requests (
  id uuid primary key default gen_random_uuid(),
  requested_at timestamptz not null default now(),
  model text,
  success boolean not null default false,
  error_code text,
  source_url text,
  created_at timestamptz not null default now()
);
create index if not exists idx_verification_groq_requests_requested_at
  on public.verification_groq_requests (requested_at desc);
alter table public.verification_groq_requests enable row level security;
drop policy if exists verification_groq_requests_admin_read on public.verification_groq_requests;
create policy verification_groq_requests_admin_read
  on public.verification_groq_requests for select to authenticated
  using (public.phase9_is_admin());
revoke insert, update, delete on public.verification_groq_requests from authenticated;
grant select on public.verification_groq_requests to authenticated;

-- Replace the earlier 7-argument version so PostgREST has one unambiguous RPC.
drop function if exists public.update_verification_automation_settings(
  boolean,integer,integer,integer,integer,integer,integer
);

create or replace function public.update_verification_automation_settings(
  p_enabled boolean,
  p_max_articles_per_run integer,
  p_max_drafts_per_run integer,
  p_max_drafts_per_day integer,
  p_monthly_draft_cap integer,
  p_monthly_groq_request_cap integer,
  p_max_pending_drafts integer,
  p_manual_cooldown_minutes integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.phase9_is_admin() then
    raise exception 'Administrator access required.';
  end if;

  update public.verification_automation_settings
  set enabled = p_enabled,
      max_articles_per_run = greatest(1, least(20, p_max_articles_per_run)),
      max_drafts_per_run = greatest(1, least(10, p_max_drafts_per_run)),
      max_drafts_per_day = greatest(1, least(50, p_max_drafts_per_day)),
      monthly_draft_cap = greatest(1, least(1000, p_monthly_draft_cap)),
      monthly_groq_request_cap = greatest(1, least(5000, p_monthly_groq_request_cap)),
      max_pending_drafts = greatest(5, least(200, p_max_pending_drafts)),
      manual_cooldown_minutes = greatest(1, least(120, p_manual_cooldown_minutes)),
      updated_at = now()
  where id = 1;

  return (
    select to_jsonb(v)
    from public.verification_automation_settings v
    where v.id = 1
  );
end;
$$;
revoke all on function public.update_verification_automation_settings(boolean,integer,integer,integer,integer,integer,integer,integer) from public, anon;
grant execute on function public.update_verification_automation_settings(boolean,integer,integer,integer,integer,integer,integer,integer) to authenticated;

create or replace function public.get_verification_automation_overview()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_settings public.verification_automation_settings%rowtype;
  v_pending integer := 0;
  v_today integer := 0;
  v_month integer := 0;
  v_groq_month integer := 0;
  v_cooldown_remaining integer := 0;
begin
  if not public.phase9_is_admin() then
    raise exception 'Administrator access required.';
  end if;

  select * into v_settings
  from public.verification_automation_settings
  where id = 1;

  select count(*)::integer into v_pending
  from public.verification_case_drafts
  where status = 'draft';

  select count(*)::integer into v_today
  from public.verification_case_drafts
  where created_at >= date_trunc('day', now());

  select count(*)::integer into v_month
  from public.verification_case_drafts
  where created_at >= date_trunc('month', now());

  select count(*)::integer into v_groq_month
  from public.verification_groq_requests
  where requested_at >= date_trunc('month', now());

  if v_settings.last_manual_success_at is not null then
    v_cooldown_remaining := greatest(
      0,
      ceil(
        extract(epoch from (
          v_settings.last_manual_success_at
          + make_interval(mins => v_settings.manual_cooldown_minutes)
          - now()
        )) / 60.0
      )::integer
    );
  end if;

  return jsonb_build_object(
    'settings', to_jsonb(v_settings),
    'pending_drafts', v_pending,
    'drafts_today', v_today,
    'drafts_this_month', v_month,
    'groq_requests_this_month', v_groq_month,
    'groq_requests_remaining', greatest(0, v_settings.monthly_groq_request_cap - v_groq_month),
    'cooldown_remaining_minutes', v_cooldown_remaining,
    'remaining_today', greatest(0, v_settings.max_drafts_per_day - v_today),
    'remaining_this_month', greatest(0, v_settings.monthly_draft_cap - v_month)
  );
end;
$$;
revoke all on function public.get_verification_automation_overview() from public, anon;
grant execute on function public.get_verification_automation_overview() to authenticated;

select 'Phase 9 direct sources + Verify limits + traffic controls installed.' as result;
