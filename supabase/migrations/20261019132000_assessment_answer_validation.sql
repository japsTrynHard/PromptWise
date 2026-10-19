BEGIN;
-- Keep eligibility/mastery logic unchanged, but prevent direct boolean input.
DO $$
DECLARE definition text := pg_get_functiondef('public.record_adaptive_attempt(uuid,text,text,boolean,text,boolean,timestamptz)'::regprocedure);
BEGIN
  EXECUTE replace(definition,'public.record_adaptive_attempt(', 'public._record_adaptive_attempt_private(');
END;
$$;
REVOKE ALL ON FUNCTION public._record_adaptive_attempt_private(uuid,text,text,boolean,text,boolean,timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.record_adaptive_attempt(uuid,text,text,boolean,text,boolean,timestamptz) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.record_adaptive_answer(p_user_id uuid,p_item_id text,p_topic_id text,p_is_correct boolean,
  p_attempt_type text,p_counted_for_mastery boolean,p_attempted_at timestamptz,p_selected_index integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item public.content_items%rowtype; actual boolean;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'Unauthorized answer.' USING errcode='42501'; END IF;
  -- Old offline queues/historical best scores have no answer to validate. Keep
  -- historical records, but never turn an unverifiable boolean into new credit.
  IF p_selected_index IS NULL THEN RETURN false; END IF;
  SELECT * INTO item FROM public.content_items WHERE id=p_item_id AND status='published' AND content_type='quiz';
  IF item.id IS NULL OR item.correct_index IS NULL OR p_selected_index < 0 OR p_selected_index >= jsonb_array_length(item.options)
     OR item.adaptive_topic IS DISTINCT FROM p_topic_id OR p_attempt_type NOT IN ('quiz','legacy_quiz') THEN
    RAISE EXCEPTION 'Invalid quiz answer.' USING errcode='22023';
  END IF;
  actual := p_selected_index = item.correct_index;
  IF p_is_correct IS DISTINCT FROM actual THEN RAISE EXCEPTION 'Quiz result does not match its answer.' USING errcode='22023'; END IF;
  RETURN public._record_adaptive_attempt_private(p_user_id,p_item_id,p_topic_id,actual,p_attempt_type,p_counted_for_mastery,now());
END;
$$;
REVOKE ALL ON FUNCTION public.record_adaptive_answer(uuid,text,text,boolean,text,boolean,timestamptz,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_adaptive_answer(uuid,text,text,boolean,text,boolean,timestamptz,integer) TO authenticated;

-- Versioned key for the five existing Flutter diagnostic items. No client-
-- editable answer key or new assessment design is needed.
CREATE OR REPLACE FUNCTION public.record_adaptive_diagnostic(p_user_id uuid,p_score integer,p_correct_answers integer,p_total_questions integer,p_answers jsonb,p_completed_at timestamptz DEFAULT now())
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  keys constant jsonb := '{"diagnostic_prompt_clarity":1,"diagnostic_context":1,"diagnostic_specificity":0,"diagnostic_responsible_use":2,"diagnostic_verification":1}';
  entry record; correct integer := 0; score integer;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'Unauthorized diagnostic.' USING errcode='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || '|diagnostic',0));
  IF EXISTS(SELECT 1 FROM public.assessment_attempts WHERE user_id=p_user_id AND assessment_type='diagnostic') THEN RETURN false; END IF;
  IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'object' THEN RAISE EXCEPTION 'Diagnostic answers required.' USING errcode='22023'; END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(p_answers)) <> 5 OR NOT (p_answers ?& ARRAY(SELECT jsonb_object_keys(keys))) THEN
    RAISE EXCEPTION 'Complete all five known diagnostic questions.' USING errcode='22023';
  END IF;
  FOR entry IN SELECT * FROM jsonb_each(p_answers) LOOP
    IF jsonb_typeof(entry.value) <> 'number' OR entry.value::text !~ '^[0-3]$' THEN RAISE EXCEPTION 'Invalid diagnostic option.' USING errcode='22023'; END IF;
    IF entry.value = keys->entry.key THEN correct := correct+1; END IF;
  END LOOP;
  score := correct*20;
  IF p_score IS DISTINCT FROM score OR p_correct_answers IS DISTINCT FROM correct OR p_total_questions IS DISTINCT FROM 5 THEN
    RAISE EXCEPTION 'Diagnostic totals do not match the submitted answers.' USING errcode='22023';
  END IF;
  INSERT INTO public.assessment_attempts(user_id,assessment_type,score,correct_answers,total_questions,answers,completed_at)
  VALUES(p_user_id,'diagnostic',score,correct,5,p_answers,now());
  PERFORM public.rebuild_adaptive_mastery_for_user(p_user_id);
  RETURN true;
END;
$$;
-- Existing SELECT policies remain; clients must not bypass the grading RPCs.
REVOKE INSERT,UPDATE,DELETE ON public.question_attempts, public.assessment_attempts FROM anon, authenticated;
COMMIT;
