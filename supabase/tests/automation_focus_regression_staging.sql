-- Run ONLY in a disposable STAGING database after the 20260922090000 migration.
-- All mutations are rolled back. Failures raise exceptions instead of merely
-- printing an error; no production or existing user settings are retained.
BEGIN;
DO $$
DECLARE
  v_before public.automation_settings%ROWTYPE;
  v_after public.automation_settings%ROWTYPE;
  v_rejected boolean := false;
BEGIN
  SELECT * INTO STRICT v_before FROM public.automation_settings WHERE id = 1;
  BEGIN
    UPDATE public.automation_settings
       SET enabled = true, focus_topics = '{}'::text[]
     WHERE id = 1;
  EXCEPTION WHEN check_violation THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'TC_AUTO_NEG_001: invalid enabled/empty setting was accepted';
  END IF;
  SELECT * INTO STRICT v_after FROM public.automation_settings WHERE id = 1;
  IF v_after.enabled IS DISTINCT FROM v_before.enabled OR
     v_after.focus_topics IS DISTINCT FROM v_before.focus_topics THEN
    RAISE EXCEPTION 'TC_AUTO_NEG_001: rejected update overwrote saved configuration';
  END IF;
  -- Valid enabled configuration (also rolled back at the end).
  UPDATE public.automation_settings
     SET enabled = true, focus_topics = ARRAY['verification']::text[]
   WHERE id = 1;
  SELECT * INTO STRICT v_after FROM public.automation_settings WHERE id = 1;
  IF NOT v_after.enabled OR v_after.focus_topics != ARRAY['verification']::text[] THEN
    RAISE EXCEPTION 'TC_AUTO_POS_001: valid focus configuration failed';
  END IF;
  -- Disabled/empty configuration remains a legitimate paused state.
  UPDATE public.automation_settings
     SET enabled = false, focus_topics = '{}'::text[]
   WHERE id = 1;
  RAISE NOTICE 'PASS: enabled requires focus; failed update preserves row; valid enabled and disabled/empty configurations accepted';
END;
$$;
ROLLBACK;
