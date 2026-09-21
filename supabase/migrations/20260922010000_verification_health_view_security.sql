-- Phase 1A: The health view was readable by anon/authenticated using its
-- owner's rights. Keep the view for internal/service use but remove its
-- public Data API access; the admin app now derives health from the existing
-- admin-gated admin_list_verification_cases() RPC.
-- Do NOT grant authenticated SELECT on verification_cases: the table contains
-- correct answers and explanations that must not be exposed to learners.

alter view public.phase9_verification_case_health
  set (security_invoker = true);

revoke all privileges on table public.phase9_verification_case_health
  from public, anon, authenticated;
