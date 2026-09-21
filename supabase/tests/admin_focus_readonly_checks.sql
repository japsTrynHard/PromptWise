-- Read-only checks AFTER migration; run from Supabase SQL Editor.
-- These queries do not test the deployed function or Groq.
select column_name, data_type, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'automation_settings'
  and column_name = 'focus_topics';

select id, enabled, focus_topics, updated_at
from public.automation_settings
where id = 1;

select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.automation_settings'::regclass
  and conname = 'automation_settings_focus_topics_valid';

select relrowsecurity as rls_enabled
from pg_class
where oid = 'public.automation_settings'::regclass;
