-- Admin-controlled lesson generation: an unconfigured schedule cannot generate
-- unrelated lessons. Verify-only automation retains its separate settings.
ALTER TABLE public.automation_settings
  ADD COLUMN IF NOT EXISTS focus_topics text[] NOT NULL DEFAULT '{}'::text[];

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.automation_settings'::regclass
      AND conname = 'automation_settings_focus_topics_valid'
  ) THEN
    ALTER TABLE public.automation_settings
      ADD CONSTRAINT automation_settings_focus_topics_valid CHECK (
        focus_topics <@ ARRAY[
          'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification'
        ]::text[]
        AND array_position(focus_topics, NULL) IS NULL
      );
  END IF;
END;
$$;

COMMENT ON COLUMN public.automation_settings.focus_topics IS
  'Saved administrator focus areas for scheduled lesson automation; an empty array pauses lesson generation until configured. Manual requests must provide their own selection.';
