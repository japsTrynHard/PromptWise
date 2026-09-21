-- OPTIONAL smoke test. Run ONLY after migration, with no active automation.
-- Run in a staging/local SQL editor. Transaction rollback leaves no run records.
-- Do NOT run while a real content-automation Edge Function is executing.
begin;
do $$
declare
  v_first uuid;
  v_second uuid;
  v_third uuid;
begin
  if exists(select 1 from public.automation_runs where status = 'running') then
    raise exception 'A live automation job exists. Try the smoke test later.';
  end if;

  v_first := public.claim_content_automation_run('manual');
  if v_first is null then
    raise exception 'FAIL: initial claim unexpectedly returned null';
  end if;

  v_second := public.claim_content_automation_run('scheduled');
  if v_second is not null then
    raise exception 'FAIL: second claim incorrectly succeeded';
  end if;

  update public.automation_runs
    set status = 'completed', completed_at = now()
    where id = v_first;

  v_third := public.claim_content_automation_run('scheduled');
  if v_third is null or v_third = v_first then
    raise exception 'FAIL: lock was not released after completion';
  end if;

  raise notice 'PASS: first claim succeeded, overlap blocked, slot reusable.';
end;
$$;
rollback;
