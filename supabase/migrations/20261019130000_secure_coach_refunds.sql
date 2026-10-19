BEGIN;
CREATE TABLE public.prompt_coach_ai_requests (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  usage_date date NOT NULL,
  status text NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved','succeeded','refunded')),
  created_at timestamptz NOT NULL DEFAULT now(),
  settled_at timestamptz
);
ALTER TABLE public.prompt_coach_ai_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.prompt_coach_ai_requests FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.reserve_prompt_coach_ai_request(p_request_id uuid, p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_day date := (now() AT TIME ZONE 'Asia/Manila')::date;
  v_used integer;
BEGIN
  IF p_user_id IS NULL OR p_request_id IS NULL THEN RAISE EXCEPTION 'Request and user required.'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || '|prompt_coach_ai|' || v_day::text, 0));
  SELECT coalesce(ai_uses,0) INTO v_used FROM public.prompt_coach_daily_usage WHERE user_id=p_user_id AND usage_date=v_day;
  IF coalesce(v_used,0) >= 3 THEN RAISE EXCEPTION 'AI Coach daily limit reached.'; END IF;
  INSERT INTO public.prompt_coach_ai_requests(id,user_id,usage_date) VALUES(p_request_id,p_user_id,v_day);
  INSERT INTO public.prompt_coach_daily_usage(user_id,usage_date,ai_uses,updated_at) VALUES(p_user_id,v_day,1,now())
  ON CONFLICT(user_id,usage_date) DO UPDATE SET ai_uses=public.prompt_coach_daily_usage.ai_uses+1,updated_at=now()
  RETURNING ai_uses INTO v_used;
  RETURN jsonb_build_object('used',v_used,'remaining',greatest(0,3-v_used),'limit',3,'reset_at',((v_day+1)::timestamp AT TIME ZONE 'Asia/Manila'));
END;
$$;

CREATE FUNCTION public.settle_prompt_coach_ai_request(p_request_id uuid, p_user_id uuid, p_success boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_request public.prompt_coach_ai_requests%rowtype;
BEGIN
  SELECT * INTO v_request FROM public.prompt_coach_ai_requests WHERE id=p_request_id AND user_id=p_user_id FOR UPDATE;
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'Unknown AI request.' USING errcode='22023'; END IF;
  IF p_success IS NULL THEN RAISE EXCEPTION 'Request outcome required.' USING errcode='22023'; END IF;
  IF v_request.status <> 'reserved' THEN RETURN false; END IF;
  IF NOT p_success THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || '|prompt_coach_ai|' || v_request.usage_date::text,0));
    UPDATE public.prompt_coach_daily_usage SET ai_uses=greatest(0,ai_uses-1),updated_at=now()
    WHERE user_id=p_user_id AND usage_date=v_request.usage_date;
  END IF;
  UPDATE public.prompt_coach_ai_requests SET status=CASE WHEN p_success THEN 'succeeded' ELSE 'refunded' END,settled_at=now() WHERE id=p_request_id;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_prompt_coach_ai_request(uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.settle_prompt_coach_ai_request(uuid,uuid,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_prompt_coach_ai_request(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.settle_prompt_coach_ai_request(uuid,uuid,boolean) TO service_role;
-- All legitimate refunds move through the Edge request ledger. The old RPC
-- lacks any request identity and must not remain callable by learners.
REVOKE EXECUTE ON FUNCTION public.refund_prompt_coach_ai_use() FROM PUBLIC, anon, authenticated;
COMMIT;
