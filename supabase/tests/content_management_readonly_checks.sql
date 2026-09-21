-- Readiness and recent outcomes only: no generated content, keys, or user data
-- are modified or returned. Run with: supabase db query --linked --file ...
begin read only;
select jsonb_build_object(
  'settings', (select to_jsonb(s) from (
    select enabled, focus_topics, max_articles_per_run, max_drafts_per_day,
      monthly_draft_cap, max_pending_drafts, max_pending_questions,
      manual_cooldown_minutes, last_manual_run_at
    from public.automation_settings where id = 1
  ) s),
  'enabled_sources', (select count(*) from public.content_sources where enabled),
  'content_counts', (select jsonb_object_agg(status, total) from (
    select status, count(*) total from public.content_items group by status
  ) c),
  'draft_counts', (select jsonb_object_agg(status, total) from (
    select status, count(*) total from public.generated_content_drafts group by status
  ) d),
  'recent_runs', (select jsonb_agg(r) from (
    select trigger_mode, status, started_at, completed_at, drafts_created,
      error_message from public.automation_runs order by started_at desc limit 5
  ) r),
  'admin_tables', (select jsonb_agg(t) from (
    select c.relname, c.relrowsecurity as rls_enabled
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname in (
      'content_items', 'content_item_versions', 'automation_settings',
      'content_sources', 'generated_content_drafts', 'question_bank'
    )
  ) t),
  'review_functions', (select jsonb_agg(p.proname) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'publish_generated_content_draft', 'reject_generated_content_draft',
      'review_question_bank_item', 'claim_content_automation_run'
    ))
) as readiness;
rollback;
