-- Keep general adaptive sessions mixed; lesson-linked sessions use only their topic.
-- An insufficient eligible bank raises the existing recoverable error.
BEGIN;

CREATE OR REPLACE FUNCTION "public"."create_adaptive_knowledge_check"("p_question_count" integer DEFAULT 10, "p_focus_topic" "text" DEFAULT NULL::"text", "p_mode" "text" DEFAULT 'adaptive'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid := gen_random_uuid();
  v_count integer := greatest(5, least(15, coalesce(p_question_count, 10)));
  v_mode text := coalesce(nullif(trim(p_mode), ''), 'adaptive');
  v_focus text := nullif(trim(p_focus_topic), '');
  v_i integer;
  v_question record;
  v_selected integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  if v_mode not in ('adaptive', 'review', 'focused') then
    raise exception 'Unknown knowledge-check mode.' using errcode = '22023';
  end if;
  if v_focus is not null and v_focus not in (
    'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification'
  ) then
    raise exception 'Unknown focus topic.' using errcode = '22023';
  end if;

  perform public.refresh_learner_topic_progression(v_user_id);

  if v_focus is null then
    select rs.topic_id into v_focus
    from public.review_schedule rs
    where rs.user_id = v_user_id and rs.due_at <= now()
    order by rs.due_at
    limit 1;
  end if;

  if v_focus is null then
    select tm.topic_id into v_focus
    from public.topic_mastery tm
    where tm.user_id = v_user_id
    order by tm.mastery asc, tm.attempts asc
    limit 1;
  end if;

  -- Starting a new session closes any orphaned active session from an earlier
  -- browser/app exit so stale sessions cannot accumulate or be mistaken for
  -- current work. Submitted answers remain in the audit history.
  update public.knowledge_check_sessions
  set status = 'abandoned',
      completed_at = coalesce(completed_at, now())
  where user_id = v_user_id
    and status = 'active';

  insert into public.knowledge_check_sessions (
    id, user_id, mode, focus_topic, status, question_count
  ) values (
    v_session_id, v_user_id, v_mode, v_focus, 'active', v_count
  );

  for v_i in 1..v_count loop
    select
      qb.id,
      qb.topic_id,
      qb.objective_id,
      qb.difficulty
    into v_question
    from public.question_bank qb
    left join public.topic_mastery tm
      on tm.user_id = v_user_id and tm.topic_id = qb.topic_id
    left join public.learner_topic_progression lp
      on lp.user_id = v_user_id and lp.topic_id = qb.topic_id
    left join public.question_exposure qe
      on qe.user_id = v_user_id and qe.question_id = qb.id
    left join public.review_schedule rs
      on rs.user_id = v_user_id and rs.topic_id = qb.topic_id
    where qb.status = 'published'
      and qb.validation_status = 'verified'
      -- A lesson-linked focused check must never substitute another topic.
      and (v_mode <> 'focused' or v_focus is null or qb.topic_id = v_focus)
      and qb.difficulty <= least(5, coalesce(lp.rank_level, 1) + 1)
      and not exists (
        select 1
        from public.knowledge_check_session_questions sq
        where sq.session_id = v_session_id and sq.question_id = qb.id
      )
    order by (
      -- Keep focus meaningful but cap dominance through the topic-count penalty.
      case when qb.topic_id = v_focus then 95 else 0 end
      + case when rs.due_at is not null and rs.due_at <= now() then 75 else 0 end
      + (100 - coalesce(tm.mastery, 0))
      + case when coalesce(qe.times_answered, 0) = 0 then 60 else 0 end
      + case when qe.last_is_correct = false then 28 else 0 end
      + greatest(
          0,
          26 - abs(
            qb.difficulty - least(
              5,
              coalesce(lp.rank_level, 1)
              + case when coalesce(tm.mastery, 0) >= 45 then 1 else 0 end
            )
          ) * 9
        )
      - (
          select count(*) * 38
          from public.knowledge_check_session_questions existing
          where existing.session_id = v_session_id
            and existing.topic_id = qb.topic_id
        )
      + random() * 8
    ) desc
    limit 1;

    if v_question.id is null then
      exit;
    end if;

    insert into public.knowledge_check_session_questions (
      session_id, question_id, sequence, topic_id, objective_id, difficulty
    ) values (
      v_session_id,
      v_question.id,
      v_i,
      v_question.topic_id,
      v_question.objective_id,
      v_question.difficulty
    );
    v_selected := v_selected + 1;
    v_question := null;
  end loop;

  if v_selected < 5 then
    delete from public.knowledge_check_sessions where id = v_session_id;
    raise exception 'No eligible question set is available for this learner yet.'
      using errcode = 'P0001';
  end if;

  update public.knowledge_check_sessions
  set question_count = v_selected
  where id = v_session_id;

  return jsonb_build_object(
    'session_id', v_session_id,
    'mode', v_mode,
    'focus_topic', v_focus,
    'started_at', now(),
    'questions', (
      select jsonb_agg(
        jsonb_build_object(
          'question_id', qb.id,
          'topic_id', qb.topic_id,
          'objective_id', qb.objective_id,
          'objective_title', coalesce(lo.title, ''),
          'stem', qb.stem,
          'options', qb.options,
          'difficulty', qb.difficulty,
          'question_type', qb.question_type,
          'sequence', sq.sequence
        ) order by sq.sequence
      )
      from public.knowledge_check_session_questions sq
      join public.question_bank qb on qb.id = sq.question_id
      left join public.learning_objectives lo on lo.id = qb.objective_id
      where sq.session_id = v_session_id
    )
  );
end;
$$;

COMMIT;
