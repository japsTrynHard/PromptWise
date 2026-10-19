-- Administrator-controlled generation policy. Existing settings stay limited.
ALTER TABLE public.verification_automation_settings
  ADD COLUMN IF NOT EXISTS unlimited_generation boolean NOT NULL DEFAULT false;
ALTER TABLE public.verification_automation_settings
  DROP CONSTRAINT IF EXISTS verification_automation_settings_manual_cooldown_check;
ALTER TABLE public.verification_automation_settings
  ADD CONSTRAINT verification_automation_settings_manual_cooldown_check
  CHECK (manual_cooldown_minutes BETWEEN 0 AND 120);
-- Replace the old signature to avoid ambiguous PostgREST overloads. The new
-- optional argument preserves callers which only supply the original 8 fields.
DROP FUNCTION IF EXISTS public.update_verification_automation_settings(boolean,integer,integer,integer,integer,integer,integer,integer);
CREATE OR REPLACE FUNCTION "public"."update_verification_automation_settings"("p_enabled" boolean, "p_max_articles_per_run" integer, "p_max_drafts_per_run" integer, "p_max_drafts_per_day" integer, "p_monthly_draft_cap" integer, "p_monthly_groq_request_cap" integer, "p_max_pending_drafts" integer, "p_manual_cooldown_minutes" integer, "p_unlimited_generation" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if not public.phase9_is_admin() then
    raise exception 'Administrator access required.';
  end if;

  update public.verification_automation_settings
  set enabled = p_enabled,
      unlimited_generation = coalesce(p_unlimited_generation, false),
      max_articles_per_run = greatest(1, least(20, p_max_articles_per_run)),
      max_drafts_per_run = greatest(1, least(10, p_max_drafts_per_run)),
      max_drafts_per_day = greatest(1, least(50, p_max_drafts_per_day)),
      monthly_draft_cap = greatest(1, least(1000, p_monthly_draft_cap)),
      monthly_groq_request_cap = greatest(1, least(5000, p_monthly_groq_request_cap)),
      max_pending_drafts = greatest(5, least(200, p_max_pending_drafts)),
      manual_cooldown_minutes = greatest(0, least(120, p_manual_cooldown_minutes)),
      updated_at = now()
  where id = 1;

  return (
    select to_jsonb(v)
    from public.verification_automation_settings v
    where v.id = 1
  );
end;
$$;

NOTIFY pgrst, 'reload schema';
REVOKE ALL ON FUNCTION public.update_verification_automation_settings(boolean,integer,integer,integer,integer,integer,integer,integer,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_verification_automation_settings(boolean,integer,integer,integer,integer,integer,integer,integer,boolean) TO authenticated, service_role;
CREATE OR REPLACE FUNCTION "public"."get_verification_automation_overview"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_settings public.verification_automation_settings%rowtype;
  v_pending integer := 0;
  v_today integer := 0;
  v_month integer := 0;
  v_groq_month integer := 0;
  v_cooldown_remaining integer := 0;
begin
  if not public.phase9_is_admin() then
    raise exception 'Administrator access required.';
  end if;

  select * into v_settings
  from public.verification_automation_settings
  where id = 1;

  select count(*)::integer into v_pending
  from public.verification_case_drafts
  where status = 'draft';

  select count(*)::integer into v_today
  from public.verification_case_drafts
  where created_at >= date_trunc('day', now());

  select count(*)::integer into v_month
  from public.verification_case_drafts
  where created_at >= date_trunc('month', now());

  select count(*)::integer into v_groq_month
  from public.verification_groq_requests
  where requested_at >= date_trunc('month', now());

  if not v_settings.unlimited_generation and v_settings.manual_cooldown_minutes > 0 and v_settings.last_manual_success_at is not null then
    v_cooldown_remaining := greatest(
      0,
      ceil(
        extract(epoch from (
          v_settings.last_manual_success_at
          + make_interval(mins => v_settings.manual_cooldown_minutes)
          - now()
        )) / 60.0
      )::integer
    );
  end if;

  return jsonb_build_object(
    'settings', to_jsonb(v_settings),
    'pending_drafts', v_pending,
    'drafts_today', v_today,
    'drafts_this_month', v_month,
    'groq_requests_this_month', v_groq_month,
    'groq_requests_remaining', case when v_settings.unlimited_generation then null else greatest(0, v_settings.monthly_groq_request_cap - v_groq_month) end,
    'cooldown_remaining_minutes', v_cooldown_remaining,
    'remaining_today', case when v_settings.unlimited_generation then null else greatest(0, v_settings.max_drafts_per_day - v_today) end,
    'remaining_this_month', case when v_settings.unlimited_generation then null else greatest(0, v_settings.monthly_draft_cap - v_month) end
  );
end;
$$;
