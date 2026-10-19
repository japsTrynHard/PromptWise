-- Existing waits remain unchanged; administrators may disable the manual wait.
-- Daily/monthly limits and queue limits still apply.
ALTER TABLE public.automation_settings
  DROP CONSTRAINT IF EXISTS automation_settings_manual_cooldown_minutes_check;
ALTER TABLE public.automation_settings
  ADD CONSTRAINT automation_settings_manual_cooldown_minutes_check
  CHECK (manual_cooldown_minutes >= 0 AND manual_cooldown_minutes <= 1440);
