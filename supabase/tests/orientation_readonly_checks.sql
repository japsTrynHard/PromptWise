-- Read-only verification after migration (Supabase SQL Editor, PromptWise only).
select to_regclass('public.learner_onboarding') is not null as table_exists,
       to_regprocedure('public.complete_my_orientation(boolean)') is not null
         as completion_rpc_exists;

select relrowsecurity as rls_enabled
from pg_class where oid = 'public.learner_onboarding'::regclass;

select policyname, roles, cmd, qual, with_check
from pg_policies where schemaname='public' and tablename='learner_onboarding'
order by policyname;

select has_table_privilege('anon', 'public.learner_onboarding', 'SELECT')
         as anon_can_read,
       has_table_privilege('authenticated', 'public.learner_onboarding', 'SELECT')
         as authenticated_has_table_grant;
-- authenticated_has_table_grant is not proof of access to another account:
-- RLS restricts actual rows; test cross-account access on a STAGING project.
