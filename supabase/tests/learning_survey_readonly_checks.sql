-- Run in Supabase SQL Editor after migrations 040000 and 050000.
-- Read-only contract inspection. No test account is created or modified.
select to_regclass('public.learner_onboarding') is not null as onboarding_exists;
select to_regclass('public.learner_survey') is not null as survey_exists;
select column_name, data_type
from information_schema.columns
where table_schema='public' and table_name='learner_onboarding'
  and column_name in ('survey_completed_at', 'survey_exempt')
order by column_name;
select tablename, rowsecurity from pg_tables
where schemaname='public' and tablename in ('learner_onboarding','learner_survey');
select policyname, cmd, roles from pg_policies
where schemaname='public' and tablename='learner_survey'
order by policyname;
select routine_name, security_type from information_schema.routines
where routine_schema='public' and routine_name in (
  'save_my_learning_survey', 'complete_my_orientation'
);
select has_table_privilege('authenticated','public.learner_survey','SELECT')
         as learner_can_select_survey,
       has_table_privilege('authenticated','public.learner_survey','UPDATE')
         as direct_survey_update_must_be_false,
       has_table_privilege('authenticated','public.learner_onboarding','UPDATE')
         as direct_onboarding_update_must_be_false;
select count(*) filter (where survey_exempt) as legacy_exempt,
       count(*) filter (where survey_completed_at is not null) as completed_surveys
from public.learner_onboarding;
