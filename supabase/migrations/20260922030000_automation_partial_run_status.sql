-- Phase 1B-3: distinguish partially successful automation runs from successes.
-- Additive status only: no rows/data are rewritten; existing lock index is unchanged.
-- Deploy this migration before deploying the matching content-automation function.
alter table public.automation_runs
  drop constraint if exists automation_runs_status_check;

alter table public.automation_runs
  add constraint automation_runs_status_check
  check (status in ('running', 'completed', 'completed_with_errors', 'failed', 'skipped'));
