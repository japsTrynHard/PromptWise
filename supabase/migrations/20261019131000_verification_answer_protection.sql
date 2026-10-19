BEGIN;
-- Preserve the existing rotation/adaptation implementation verbatim privately.
DO $$
DECLARE definition text := pg_get_functiondef('public.create_adaptive_verification_session(integer,integer)'::regprocedure);
BEGIN
  EXECUTE replace(definition, 'public.create_adaptive_verification_session(', 'public._create_verification_session_private(');
END;
$$;
REVOKE ALL ON FUNCTION public._create_verification_session_private(integer,integer) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_adaptive_verification_session(p_case_count integer DEFAULT 5, p_rank_level integer DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result jsonb;
BEGIN
  result := public._create_verification_session_private(p_case_count,p_rank_level);
  RETURN jsonb_set(result,'{cases}',coalesce((SELECT jsonb_agg(
    (item - ARRAY['correct_decision','explanation','learning_point','expected_confidence','evidence','actions','best_source_index']) ||
    jsonb_build_object('answer_hidden',true,'decision_options',jsonb_build_array(
      'supported','ai_generated','manipulated','misleading_context','unsupported_claim','unverified','insufficient_evidence'))
    ORDER BY (item->>'sequence')::integer)
    FROM jsonb_array_elements(result->'cases') AS item),'[]'::jsonb));
END;
$$;
-- An otherwise safe session RPC is insufficient while the learner can SELECT
-- the entire answer bank directly. Admin review keeps its authorized access.
DROP POLICY IF EXISTS verification_cases_select_published ON public.verification_cases;
CREATE POLICY verification_cases_select_published ON public.verification_cases FOR SELECT TO authenticated USING (public.phase9_is_admin());

-- Lock before looking for an existing submission; both submission APIs share
-- the same lock, making retries idempotent and concurrent answer forgery inert.
DO $$
DECLARE signature text; definition text;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'public.submit_verification_guess(uuid,uuid,text)',
    'public.submit_verification_case_attempt(uuid,uuid,text[],text[],integer,text,text)'
  ] LOOP
    definition := pg_get_functiondef(signature::regprocedure);
    definition := regexp_replace(definition, '\mbegin\M', E'begin\n  perform pg_advisory_xact_lock(hashtextextended(coalesce(auth.uid()::text, '''') || ''|verification_submission|'' || p_case_id::text, 0));', 'i');
    EXECUTE definition;
  END LOOP;
END;
$$;
COMMIT;
