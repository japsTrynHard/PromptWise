-- TC_AUTO_NEG_001: align the database with the admin UI contract.
-- Do not edit the previously deployed 20260922060000 migration.
-- Keep all saved settings/focus areas. Only turn off legacy unconfigured
-- schedules; the existing Edge Function already skips such schedules.
UPDATE public.automation_settings
SET enabled = false,
    updated_at = now()
WHERE enabled = true
  AND cardinality(focus_topics) = 0;

-- A newly inserted settings row must not inherit enabled=true with the
-- column's default empty focus list. Admins may enable after choosing a topic.
ALTER TABLE public.automation_settings
  ALTER COLUMN enabled SET DEFAULT false;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.automation_settings'::regclass
      AND conname = 'automation_settings_enabled_requires_focus'
  ) THEN
    ALTER TABLE public.automation_settings
      ADD CONSTRAINT automation_settings_enabled_requires_focus
      CHECK (NOT enabled OR cardinality(focus_topics) BETWEEN 1 AND 5);
  END IF;
END;
$$;

COMMENT ON COLUMN public.automation_settings.focus_topics IS
  'Admin-selected scheduled lesson topics. A disabled, empty configuration is allowed; enabling requires at least one valid topic. Manual runs have separate selections.';
