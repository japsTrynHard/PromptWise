-- PromptWise Phase 9 - FINAL ONE-RUN CURRENT DATABASE FINALIZER
-- Date: 2026-08-25
--
-- PURPOSE
-- Finalizes the CURRENT PromptWise database for the latest Phase 9
-- AI Awareness + Verify behavior.
--
-- IMPORTANT
-- This is intentionally a CURRENT-DATABASE finalizer, not a brand-new database
-- bootstrap. Your base Phase 9 schema must already exist.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 0. PRE-FLIGHT: stop with a clear message if the original Phase 9 schema
--    has not been installed yet.
-- ---------------------------------------------------------------------------
do $$
declare
  missing text[] := array[]::text[];
begin
  if to_regclass('public.awareness_articles') is null then
    missing := array_append(missing, 'public.awareness_articles');
  end if;

  if to_regclass('public.awareness_feed_settings') is null then
    missing := array_append(missing, 'public.awareness_feed_settings');
  end if;

  if to_regclass('public.awareness_source_domains') is null then
    missing := array_append(missing, 'public.awareness_source_domains');
  end if;

  if to_regclass('public.awareness_direct_sources') is null then
    missing := array_append(missing, 'public.awareness_direct_sources');
  end if;

  if to_regclass('public.awareness_user_actions') is null then
    missing := array_append(missing, 'public.awareness_user_actions');
  end if;

  if to_regclass('public.verification_case_drafts') is null then
    missing := array_append(missing, 'public.verification_case_drafts');
  end if;

  if array_length(missing, 1) is not null then
    raise exception
      'Phase 9 base schema is incomplete. Missing: %. Run the original Phase 9 base migration/setup first.',
      array_to_string(missing, ', ');
  end if;
end $$;

begin;

-- ---------------------------------------------------------------------------
-- 1. AI Awareness final schema fields
-- ---------------------------------------------------------------------------
alter table public.awareness_articles
  add column if not exists ai_relevance_score integer not null default 0,
  add column if not exists last_seen_at timestamptz not null default now();

alter table public.awareness_feed_settings
  add column if not exists min_active_ai_articles integer not null default 12,
  add column if not exists manual_check_cooldown_minutes integer not null default 10;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'awareness_articles_ai_relevance_check'
      and conrelid = 'public.awareness_articles'::regclass
  ) then
    alter table public.awareness_articles
      add constraint awareness_articles_ai_relevance_check
      check (ai_relevance_score between 0 and 20);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'awareness_feed_settings_min_ai_check'
      and conrelid = 'public.awareness_feed_settings'::regclass
  ) then
    alter table public.awareness_feed_settings
      add constraint awareness_feed_settings_min_ai_check
      check (min_active_ai_articles between 4 and 50);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'awareness_feed_settings_manual_check_cooldown_check'
      and conrelid = 'public.awareness_feed_settings'::regclass
  ) then
    alter table public.awareness_feed_settings
      add constraint awareness_feed_settings_manual_check_cooldown_check
      check (manual_check_cooldown_minutes between 1 and 60);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Strict AI-topic scoring
-- ---------------------------------------------------------------------------
create or replace function public.awareness_ai_topic_score(
  p_title text,
  p_summary text default ''
)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  t text := lower(coalesce(p_title, ''));
  s text := lower(left(coalesce(p_summary, ''), 900));
  title_score integer := 0;
  summary_score integer := 0;
begin
  if t ~ 'artificial intelligence' then title_score := title_score + 6; end if;
  if t ~ 'generative[[:space:]-]+ai|genai' then title_score := title_score + 6; end if;
  if t ~ 'deep[[:space:]-]*fake|synthetic media|voice clon|cloned voice' then title_score := title_score + 7; end if;
  if t ~ 'ai[[:space:]-]+(generated|made|created|powered|driven|assisted)' then title_score := title_score + 6; end if;
  if t ~ '(^|[^a-z0-9])ai([^a-z0-9]|$)' then title_score := title_score + 4; end if;

  if t ~ 'chatgpt|openai|google gemini|gemini ai|google ai|claude ai|anthropic|copilot|grok|meta ai|large language model|(^|[^a-z0-9])llms?([^a-z0-9]|$)' then
    title_score := title_score + 4;
  end if;

  if s ~ 'artificial intelligence' then summary_score := summary_score + 6; end if;
  if s ~ 'generative[[:space:]-]+ai|genai' then summary_score := summary_score + 6; end if;
  if s ~ 'deep[[:space:]-]*fake|synthetic media|voice clon|cloned voice' then summary_score := summary_score + 7; end if;
  if s ~ 'ai[[:space:]-]+(generated|made|created|powered|driven|assisted)' then summary_score := summary_score + 6; end if;

  if s ~ 'chatgpt|openai|google gemini|gemini ai|google ai|claude ai|anthropic|copilot|grok|meta ai|large language model|(^|[^a-z0-9])llms?([^a-z0-9]|$)' then
    summary_score := summary_score + 4;
  end if;

  if title_score >= 4 then
    return least(20, greatest(title_score, summary_score));
  end if;

  -- A lone generic "AI" mention in a summary is not enough.
  if summary_score >= 7 then
    return least(20, summary_score);
  end if;

  return 0;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Clean old unrelated Awareness rows
-- ---------------------------------------------------------------------------
update public.awareness_articles
set
  ai_relevance_score = public.awareness_ai_topic_score(title, summary),
  last_seen_at = coalesce(last_seen_at, discovered_at, created_at, now()),
  is_active = (
    is_active = true
    and public.awareness_ai_topic_score(title, summary) >= 4
  ),
  updated_at = now();

create index if not exists idx_awareness_articles_ai_feed
  on public.awareness_articles (
    is_active,
    ai_relevance_score desc,
    relevance_score desc,
    published_at desc
  )
  where ai_relevance_score >= 4;

-- ---------------------------------------------------------------------------
-- 4. Trusted AI/news domains
-- ---------------------------------------------------------------------------
insert into public.awareness_source_domains
  (domain, name, region, trust_level)
values
  ('pna.gov.ph', 'Philippine News Agency', 'Philippines', 100),
  ('gmanetwork.com', 'GMA News', 'Philippines', 90),
  ('philstar.com', 'Philstar.com', 'Philippines', 87),
  ('inquirer.net', 'Inquirer.net', 'Philippines', 87),
  ('mb.com.ph', 'Manila Bulletin', 'Philippines', 85),
  ('rappler.com', 'Rappler', 'Philippines', 88),
  ('reuters.com', 'Reuters', 'Global', 96),
  ('apnews.com', 'Associated Press', 'Global', 96),
  ('technologyreview.com', 'MIT Technology Review', 'Global', 92),
  ('techcrunch.com', 'TechCrunch', 'Global', 86),
  ('theverge.com', 'The Verge', 'Global', 85),
  ('arstechnica.com', 'Ars Technica', 'Global', 88),
  ('wired.com', 'WIRED', 'Global', 88),
  ('openai.com', 'OpenAI', 'Global', 90),
  ('deepmind.google', 'Google DeepMind', 'Global', 90)
on conflict do nothing;

update public.awareness_source_domains d
set
  name = v.name,
  region = v.region,
  trust_level = v.trust_level,
  enabled = true,
  updated_at = now()
from (
  values
    ('pna.gov.ph', 'Philippine News Agency', 'Philippines', 100),
    ('gmanetwork.com', 'GMA News', 'Philippines', 90),
    ('philstar.com', 'Philstar.com', 'Philippines', 87),
    ('inquirer.net', 'Inquirer.net', 'Philippines', 87),
    ('mb.com.ph', 'Manila Bulletin', 'Philippines', 85),
    ('rappler.com', 'Rappler', 'Philippines', 88),
    ('reuters.com', 'Reuters', 'Global', 96),
    ('apnews.com', 'Associated Press', 'Global', 96),
    ('technologyreview.com', 'MIT Technology Review', 'Global', 92),
    ('techcrunch.com', 'TechCrunch', 'Global', 86),
    ('theverge.com', 'The Verge', 'Global', 85),
    ('arstechnica.com', 'Ars Technica', 'Global', 88),
    ('wired.com', 'WIRED', 'Global', 88),
    ('openai.com', 'OpenAI', 'Global', 90),
    ('deepmind.google', 'Google DeepMind', 'Global', 90)
) as v(domain, name, region, trust_level)
where lower(d.domain) = lower(v.domain);

-- ---------------------------------------------------------------------------
-- 5. Dedicated AI feeds
-- ---------------------------------------------------------------------------
insert into public.awareness_direct_sources
  (
    name,
    base_domain,
    source_url,
    source_type,
    region,
    trust_level,
    priority,
    relevance_keywords,
    enabled
  )
values
  (
    'TechCrunch - Artificial Intelligence RSS',
    'techcrunch.com',
    'https://techcrunch.com/category/artificial-intelligence/feed/',
    'rss',
    'Global',
    86,
    88,
    array[
      'artificial intelligence',
      'generative ai',
      'deepfake',
      'chatgpt',
      'openai',
      'ai-generated'
    ],
    true
  ),
  (
    'Ars Technica - AI RSS',
    'arstechnica.com',
    'https://arstechnica.com/ai/feed/',
    'rss',
    'Global',
    88,
    86,
    array[
      'artificial intelligence',
      'generative ai',
      'deepfake',
      'chatgpt',
      'openai',
      'ai-generated'
    ],
    true
  ),
  (
    'WIRED - AI RSS',
    'wired.com',
    'https://www.wired.com/feed/tag/ai/latest/rss',
    'rss',
    'Global',
    88,
    85,
    array[
      'artificial intelligence',
      'generative ai',
      'deepfake',
      'chatgpt',
      'openai',
      'ai-generated'
    ],
    true
  ),
  (
    'OpenAI News RSS',
    'openai.com',
    'https://openai.com/news/rss.xml',
    'rss',
    'Global',
    90,
    84,
    array[
      'openai',
      'chatgpt',
      'artificial intelligence',
      'generative ai'
    ],
    true
  ),
  (
    'Google DeepMind Blog RSS',
    'deepmind.google',
    'https://deepmind.google/blog/feed/basic/',
    'rss',
    'Global',
    90,
    83,
    array[
      'artificial intelligence',
      'gemini',
      'deepmind',
      'generative ai'
    ],
    true
  )
on conflict (source_url) do update
set
  name = excluded.name,
  base_domain = excluded.base_domain,
  source_type = excluded.source_type,
  region = excluded.region,
  trust_level = excluded.trust_level,
  priority = excluded.priority,
  relevance_keywords = excluded.relevance_keywords,
  enabled = true,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- 6. Final feed limits / traffic controls
-- ---------------------------------------------------------------------------
update public.awareness_feed_settings
set
  direct_source_limit = greatest(coalesce(direct_source_limit, 6), 12),
  min_direct_candidates_before_fallback =
    greatest(coalesce(min_direct_candidates_before_fallback, 8), 12),
  min_ph_direct_candidates_before_fallback =
    greatest(coalesce(min_ph_direct_candidates_before_fallback, 3), 5),
  max_articles_per_refresh =
    greatest(coalesce(max_articles_per_refresh, 24), 32),
  max_active_articles =
    greatest(coalesce(max_active_articles, 200), 200),
  archive_after_days =
    greatest(coalesce(archive_after_days, 45), 45),
  min_active_ai_articles = 12,
  manual_check_cooldown_minutes = 10,
  last_success_at = null,
  last_refresh_at = null,
  last_error = null,
  updated_at = now()
where id = 1;

-- ---------------------------------------------------------------------------
-- 7. AI-only learner feed RPC
-- ---------------------------------------------------------------------------
create or replace function public.get_my_awareness_feed_cache(
  p_limit integer default 80
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      item
      order by
        ai_relevance_score desc,
        relevance_score desc,
        published_at desc nulls last
    ),
    '[]'::jsonb
  )
  from (
    select
      jsonb_build_object(
        'id', a.id,
        'title', a.title,
        'summary', a.summary,
        'why_it_matters', a.why_it_matters,
        'source_name', a.source_name,
        'source_domain', a.source_domain,
        'source_url', a.source_url,
        'image_url', a.image_url,
        'published_at', a.published_at,
        'discovered_at', a.discovered_at,
        'category', a.category,
        'region', a.region,
        'relevance_score', a.relevance_score,
        'trust_level', a.trust_level,
        'read', (ua.read_at is not null),
        'saved', (ua.saved_at is not null)
      ) as item,
      a.ai_relevance_score,
      a.relevance_score,
      a.published_at
    from public.awareness_articles a
    left join public.awareness_user_actions ua
      on ua.article_id = a.id
     and ua.user_id = auth.uid()
    where
      a.is_active = true
      and a.ai_relevance_score >= 4
    order by
      a.ai_relevance_score desc,
      a.relevance_score desc,
      a.published_at desc nulls last
    limit least(
      greatest(coalesce(p_limit, 80), 10),
      100
    )
  ) q;
$$;

grant execute
on function public.get_my_awareness_feed_cache(integer)
to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Reject old Verify drafts that were based on invalid/non-AI articles
-- ---------------------------------------------------------------------------
update public.verification_case_drafts d
set
  status = 'rejected',
  reviewed_at = coalesce(reviewed_at, now()),
  updated_at = now()
from public.awareness_articles a
where
  d.article_id = a.id
  and d.status = 'draft'
  and (
    a.is_active = false
    or a.ai_relevance_score < 4
  );

commit;

-- ---------------------------------------------------------------------------
-- 9. Optional scheduled refresh every 6 hours.
--    Does not fail the core patch when scheduler infrastructure is unavailable.
-- ---------------------------------------------------------------------------
do $$
declare
  item record;
  schedule_sql text := $cronbody$
    select net.http_post(
      url := (
        select project_url
        from public.automation_scheduler_config
        where id = 1
          and enabled = true
      ) || '/functions/v1/awareness-feed',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-automation-secret', (
          select scheduler_secret
          from public.automation_scheduler_config
          where id = 1
            and enabled = true
        )
      ),
      body := '{"action":"scheduled_refresh"}'::jsonb,
      timeout_milliseconds := 120000
    );
  $cronbody$;
begin
  if to_regnamespace('cron') is null
     or to_regclass('public.automation_scheduler_config') is null then
    raise notice
      'Scheduler not available. Core Phase 9 finalizer still completed.';
    return;
  end if;

  for item in execute
    'select jobid from cron.job where jobname = ''promptwise-ai-awareness-refresh'''
  loop
    execute
      'select cron.unschedule($1)'
    using item.jobid;
  end loop;

  execute
    'select cron.schedule($1, $2, $3)'
  using
    'promptwise-ai-awareness-refresh',
    '17 */6 * * *',
    schedule_sql;

exception
  when others then
    raise notice
      'AI Awareness scheduler was not installed: %',
      sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 10. Final diagnostics
-- ---------------------------------------------------------------------------
select
  count(*) filter (
    where is_active
      and ai_relevance_score >= 4
  ) as active_ai_articles,

  count(*) filter (
    where is_active
      and ai_relevance_score >= 4
      and region = 'Philippines'
  ) as active_ph_ai_articles,

  count(*) filter (
    where is_active
      and ai_relevance_score >= 4
      and region = 'Global'
  ) as active_global_ai_articles
from public.awareness_articles;

select
  id,
  enabled,
  direct_source_limit,
  max_articles_per_refresh,
  max_active_articles,
  min_active_ai_articles,
  manual_check_cooldown_minutes,
  last_success_at,
  last_error
from public.awareness_feed_settings
where id = 1;
