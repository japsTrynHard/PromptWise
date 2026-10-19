-- Record actual administrator approval events. Existing dates stay unknown
-- unless a matching approved Verify draft supplies a recorded review event.
BEGIN;

ALTER TABLE public.question_bank
  ADD COLUMN IF NOT EXISTS approved_at timestamptz;
ALTER TABLE public.verification_cases
  ADD COLUMN IF NOT EXISTS approved_at timestamptz;

CREATE OR REPLACE FUNCTION public.stamp_question_bank_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.approved_at := OLD.approved_at;
    IF NEW.validation_status = 'verified'
       AND OLD.validation_status IS DISTINCT FROM 'verified'
       AND public.is_promptwise_admin() THEN
      NEW.approved_at := now();
    END IF;
  ELSE
    NEW.approved_at := CASE
      WHEN NEW.validation_status = 'verified' AND public.is_promptwise_admin()
      THEN now() ELSE NULL END;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.stamp_verification_case_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.approved_at := OLD.approved_at;
    IF NEW.status = 'published' AND OLD.status IS DISTINCT FROM 'published'
       AND public.phase9_is_admin() THEN
      NEW.approved_at := now();
    END IF;
  ELSE
    NEW.approved_at := CASE
      WHEN NEW.status = 'published' AND public.phase9_is_admin()
      THEN now() ELSE NULL END;
  END IF;
  RETURN NEW;
END;
$$;

-- The approval RPC creates this exact case code from its draft ID and URL.
-- Do not infer approval from creation/update/source-publication timestamps.
DROP TRIGGER IF EXISTS question_bank_stamp_approval ON public.question_bank;
DROP TRIGGER IF EXISTS verification_case_stamp_approval ON public.verification_cases;
UPDATE public.verification_cases c
SET approved_at = d.reviewed_at
FROM public.verification_case_drafts d
WHERE c.approved_at IS NULL AND c.generated_by = 'content_automation'
  AND d.status = 'approved' AND d.reviewed_at IS NOT NULL
  AND c.case_code = 'auto_' || substr(md5(d.source_url || d.id::text), 1, 20);

CREATE TRIGGER question_bank_stamp_approval BEFORE INSERT OR UPDATE
ON public.question_bank FOR EACH ROW
EXECUTE FUNCTION public.stamp_question_bank_approval();

CREATE TRIGGER verification_case_stamp_approval BEFORE INSERT OR UPDATE
ON public.verification_cases FOR EACH ROW
EXECUTE FUNCTION public.stamp_verification_case_approval();

REVOKE ALL ON FUNCTION public.stamp_question_bank_approval() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.stamp_verification_case_approval() FROM PUBLIC, anon, authenticated;

COMMENT ON COLUMN public.question_bank.approved_at IS
  'Latest recorded admin transition to verified; unknown for older unrecorded approvals. Ordinary edits preserve this timestamp.';
COMMENT ON COLUMN public.verification_cases.approved_at IS
  'Latest recorded admin approval/publication. Historical generated cases may use their matching approved draft reviewed_at; other unknown dates stay NULL.';

COMMIT;
