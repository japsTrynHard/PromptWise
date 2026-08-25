-- PromptWise Phase 9 reliability hotfix
-- Fixes false-success Awareness refreshes, adds source snapshots/diagnostics,
-- and separates Verify manual attempts from successful-generation cooldowns.

alter table public.awareness_feed_settings
  add column if not exists last_attempt_at timestamptz,
  add column if not exists last_success_at timestamptz,
  add column if not exists last_success_count integer not null default 0,
  add column if not exists last_error text;

alter table public.awareness_articles
  add column if not exists content_excerpt text not null default '',
  add column if not exists content_fetch_status text not null default 'not_attempted',
  add column if not exists content_fetched_at timestamptz,
  add column if not exists content_hash text;

alter table public.awareness_articles
  drop constraint if exists awareness_articles_content_fetch_status_check;
alter table public.awareness_articles
  add constraint awareness_articles_content_fetch_status_check
  check (content_fetch_status in ('not_attempted','usable','insufficient','unavailable'));

create index if not exists idx_awareness_articles_content_hash
  on public.awareness_articles (content_hash)
  where content_hash is not null;

alter table public.awareness_refresh_runs
  add column if not exists trusted_matched integer not null default 0,
  add column if not exists articles_usable integer not null default 0,
  add column if not exists active_articles integer not null default 0,
  add column if not exists provider_warnings jsonb not null default '[]'::jsonb;

alter table public.verification_automation_settings
  add column if not exists last_manual_attempt_at timestamptz,
  add column if not exists last_manual_success_at timestamptz,
  add column if not exists last_manual_error text;

-- Preserve a previous Awareness success only when there is actual cached
-- learner-visible content. If the feed is empty, clear the old freshness stamp
-- so the next request immediately attempts discovery again.
with active as (
  select count(*)::integer as count
  from public.awareness_articles
  where is_active = true
)
update public.awareness_feed_settings s
set last_success_at = case
      when active.count > 0 then coalesce(s.last_success_at, s.last_refresh_at)
      else null
    end,
    last_success_count = active.count,
    last_refresh_at = case when active.count > 0 then s.last_refresh_at else null end,
    last_error = case
      when active.count > 0 then s.last_error
      else coalesce(s.last_error, 'No active Awareness articles are cached yet.')
    end,
    updated_at = now()
from active
where s.id = 1;

-- Legacy last_manual_run_at may have been written by a failed Verify attempt.
-- The new Edge Function intentionally ignores it for cooldown decisions and
-- starts using last_manual_success_at only after a draft is actually created.
