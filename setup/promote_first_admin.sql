-- 1. Register the administrator email normally or create it in
--    Supabase Dashboard > Authentication > Users.
-- 2. Replace the email below, then run this in SQL Editor.
-- 3. Sign out and sign back in on the PromptWise web app.

update public.profiles
set role = 'administrator'::public.app_role
where lower(email) = lower('REPLACE_WITH_ADMIN_EMAIL@example.com');

-- Verify the result:
select id, email, full_name, role, created_at
from public.profiles
where role = 'administrator'::public.app_role;
