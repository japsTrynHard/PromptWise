-- Phase 1B-2: stop concurrent content-automation jobs (manual and scheduled).
-- Deploy this migration BEFORE deploying the updated Edge Function.
-- This migration is additive: no application content or approved drafts are deleted.

-- An abandoned run is no longer active after the existing 20-minute timeout.
-- Preserve a failure record instead of deleting it. Do not alter recent runs.
update public.automation_runs
set status = 'failed',
    completed_at = now(),
    error_message = coalesce(nullif(error_message, ''),
      'Marked failed after exceeding the 20-minute automation run timeout.')
where status = 'running'
  and started_at < now() - interval '20 minutes';

-- A concurrent duplicate already in progress requires an operator to let the
-- runs finish before applying this migration; never silently overwrite them.
do $$
begin
  if (select count(*) from public.automation_runs where status = 'running') > 1 then
    raise exception 'Multiple active automation jobs exist. Wait for them to finish, then retry this migration.';
  end if;
end;
$$;

-- Enforce the invariant at the database level, including calls from old code.
-- Partial UNIQUE index allows any number of historical completed/failed runs.
create unique index if not exists automation_runs_one_running_idx
  on public.automation_runs (status)
  where status = 'running';

-- An RPC is a single transaction. The transaction-scoped advisory lock ensures
-- that the stale-row cleanup, active-run check and new insertion are atomic.
-- SECURITY INVOKER + restricted EXECUTE avoids exposing a job-creation endpoint
-- to normal app users; only the Edge Function's service role may call it.
create or replace function public.claim_content_automation_run(
  p_trigger_mode text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run_id uuid;
begin
  if p_trigger_mode is null or p_trigger_mode not in ('manual', 'scheduled') then
    raise exception 'Invalid automation trigger mode.' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(7262009, 1);

  update public.automation_runs
  set status = 'failed',
      completed_at = now(),
      error_message = coalesce(nullif(error_message, ''),
        'Marked failed after exceeding the 20-minute automation run timeout.')
  where status = 'running'
    and started_at < now() - interval '20 minutes';

  if exists (select 1 from public.automation_runs where status = 'running') then
    return null;
  end if;

  insert into public.automation_runs (trigger_mode, status)
  values (p_trigger_mode, 'running')
  returning id into v_run_id;

  return v_run_id;
end;
$$;

revoke all on function public.claim_content_automation_run(text) from public;
revoke all on function public.claim_content_automation_run(text) from anon;
revoke all on function public.claim_content_automation_run(text) from authenticated;
grant execute on function public.claim_content_automation_run(text) to service_role;
