


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."app_role" AS ENUM (
    'learner',
    'administrator'
);


ALTER TYPE "public"."app_role" OWNER TO "postgres";


CREATE TYPE "public"."content_status" AS ENUM (
    'draft',
    'published',
    'archived'
);


ALTER TYPE "public"."content_status" OWNER TO "postgres";


CREATE TYPE "public"."content_type" AS ENUM (
    'module',
    'lesson',
    'quiz',
    'activity',
    'awareness'
);


ALTER TYPE "public"."content_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."abandon_adaptive_knowledge_check"("p_session_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  update public.knowledge_check_sessions
  set status = 'abandoned',
      completed_at = coalesce(completed_at, now())
  where id = p_session_id
    and user_id = auth.uid()
    and status = 'active';
end;
$$;


ALTER FUNCTION "public"."abandon_adaptive_knowledge_check"("p_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."abandon_verification_session"("p_session_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  update public.verification_sessions set status='abandoned', completed_at=now()
  where id=p_session_id and user_id=auth.uid() and status='active';
end;
$$;


ALTER FUNCTION "public"."abandon_verification_session"("p_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_verification_cases"() RETURNS SETOF "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  select to_jsonb(c)
  from public.verification_cases c
  where public.phase9_is_admin() and c.status='published'
  order by c.created_at desc;
$$;


ALTER FUNCTION "public"."admin_list_verification_cases"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_verification_case_draft"("p_draft_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_draft public.verification_case_drafts%rowtype;
  v_payload jsonb;
  v_case_id uuid;
  v_code text;
begin
  if not public.phase9_is_admin() then raise exception 'Administrator access required.' using errcode='42501'; end if;
  select * into v_draft from public.verification_case_drafts where id=p_draft_id and status='draft' for update;
  if v_draft.id is null then raise exception 'Verification draft not found.' using errcode='P0001'; end if;
  v_payload := v_draft.draft_payload;
  v_code := 'auto_' || substr(md5(v_draft.source_url || v_draft.id::text),1,20);

  -- Keep the dynamic published bank bounded. Only AI-generated cases are
  -- eligible for automatic archival; curated/admin cases are never removed.
  if (
    select count(*) from public.verification_cases
    where status='published' and generated_by='content_automation'
  ) >= (
    select max_dynamic_published from public.verification_automation_settings where id=1
  ) then
    update public.verification_cases
    set status='archived', updated_at=now()
    where id = (
      select id from public.verification_cases
      where status='published' and generated_by='content_automation'
      order by created_at asc
      limit 1
    );
  end if;

  insert into public.verification_cases (
    case_code,title,scenario,claim_text,case_type,subskill,difficulty,
    media_type,media_url,media_description,evidence,actions,source_options,
    best_source_index,correct_decision,expected_confidence,explanation,
    learning_point,source_name,source_url,source_published_at,generated_by,status,
    expires_at
  ) values (
    v_code,
    v_payload->>'title',
    v_payload->>'scenario',
    coalesce(v_payload->>'claim_text',''),
    v_payload->>'case_type',
    v_payload->>'subskill',
    coalesce((v_payload->>'difficulty')::integer,3),
    coalesce(v_payload->>'media_type','text'),
    nullif(v_payload->>'media_url',''),
    coalesce(v_payload->>'media_description',''),
    coalesce(v_payload->'evidence','[]'::jsonb),
    coalesce(v_payload->'actions','[]'::jsonb),
    coalesce(v_payload->'source_options','[]'::jsonb),
    coalesce((v_payload->>'best_source_index')::integer,0),
    v_payload->>'correct_decision',
    coalesce(v_payload->>'expected_confidence','medium'),
    v_payload->>'explanation',
    v_payload->>'learning_point',
    v_draft.source_name,
    v_draft.source_url,
    v_draft.source_published_at,
    'content_automation','published',
    now() + make_interval(days => (
      select dynamic_case_max_age_days
      from public.verification_automation_settings
      where id=1
    ))
  )
  on conflict (case_code) do update set
    title=excluded.title, scenario=excluded.scenario, claim_text=excluded.claim_text,
    evidence=excluded.evidence, actions=excluded.actions, source_options=excluded.source_options,
    correct_decision=excluded.correct_decision, explanation=excluded.explanation,
    learning_point=excluded.learning_point, status='published', updated_at=now()
  returning id into v_case_id;

  update public.verification_case_drafts
  set status='approved', reviewed_at=now(), updated_at=now()
  where id=p_draft_id;
  return v_case_id;
end;
$$;


ALTER FUNCTION "public"."approve_verification_case_draft"("p_draft_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."archive_verification_case"("p_case_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if not public.phase9_is_admin() then raise exception 'Administrator access required.' using errcode='42501'; end if;
  update public.verification_cases set status='archived', updated_at=now() where id=p_case_id;
end;
$$;


ALTER FUNCTION "public"."archive_verification_case"("p_case_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."awareness_ai_topic_score"("p_title" "text", "p_summary" "text" DEFAULT ''::"text") RETURNS integer
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
declare
  t text := lower(coalesce(p_title, ''));
  s text := lower(left(coalesce(p_summary, ''), 900));
  title_score integer := 0;
  summary_score integer := 0;
begin
  if t ~ 'artificial intelligence' then title_score := title_score + 6; end if;
  if t ~ 'generative[[:space:]-]+ai|genai' then title_score := title_score + 6; end if;
  if t ~ 'deep[[:space:]-]*fake|synthetic media|voice clon|cloned voice' then title_score := title_score + 7; end if;
  if t ~ 'ai[[:space:]-]+(generated|made|created|powered|driven|assisted)' then title_score := title_score + 6; end if;
  if t ~ '(^|[^a-z0-9])ai([^a-z0-9]|$)' then title_score := title_score + 4; end if;
  if t ~ 'chatgpt|openai|google gemini|gemini ai|google ai|claude ai|anthropic|copilot|grok|meta ai|large language model|(^|[^a-z0-9])llms?([^a-z0-9]|$)' then
    title_score := title_score + 4;
  end if;

  if s ~ 'artificial intelligence' then summary_score := summary_score + 6; end if;
  if s ~ 'generative[[:space:]-]+ai|genai' then summary_score := summary_score + 6; end if;
  if s ~ 'deep[[:space:]-]*fake|synthetic media|voice clon|cloned voice' then summary_score := summary_score + 7; end if;
  if s ~ 'ai[[:space:]-]+(generated|made|created|powered|driven|assisted)' then summary_score := summary_score + 6; end if;
  if s ~ 'chatgpt|openai|google gemini|gemini ai|google ai|claude ai|anthropic|copilot|grok|meta ai|large language model|(^|[^a-z0-9])llms?([^a-z0-9]|$)' then
    summary_score := summary_score + 4;
  end if;

  if title_score >= 4 then
    return least(20, greatest(title_score, summary_score));
  end if;

  -- Summary-only qualification requires a stronger signal than a lone "AI"
  -- token. This is what removes false positives such as generic CISA stories.
  if summary_score >= 7 then
    return least(20, summary_score);
  end if;

  return 0;
end;
$_$;


ALTER FUNCTION "public"."awareness_ai_topic_score"("p_title" "text", "p_summary" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."awareness_is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'administrator'
  );
$$;


ALTER FUNCTION "public"."awareness_is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."capture_content_item_version"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    new.version := 1;
    new.created_by := coalesce(new.created_by, current_user_id);
    new.updated_by := coalesce(new.updated_by, current_user_id);
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := now();
    if new.status = 'published'::public.content_status
       and new.publication_date is null then
      new.publication_date := current_date;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' and exists (
    select 1
    from public.content_items as dependent
    where dependent.id <> old.id
      and (dependent.parent_id = old.id or dependent.quiz_id = old.id)
  ) then
    raise exception 'Content item % is still referenced by other content', old.id;
  end if;

  insert into public.content_item_versions (
    content_id,
    content_type,
    version,
    operation,
    snapshot,
    changed_by
  ) values (
    old.id,
    old.content_type,
    old.version,
    tg_op,
    to_jsonb(old),
    current_user_id
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  new.version := old.version + 1;
  new.created_by := old.created_by;
  new.created_at := old.created_at;
  new.updated_by := current_user_id;
  new.updated_at := now();
  if new.status = 'published'::public.content_status
     and new.publication_date is null then
    new.publication_date := current_date;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."capture_content_item_version"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_adaptive_knowledge_check"("p_session_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_owner uuid;
  v_total integer;
  v_answered integer;
  v_correct integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select user_id into v_owner
  from public.knowledge_check_sessions
  where id = p_session_id;
  if v_owner is null or v_owner <> v_user_id then
    raise exception 'Knowledge-check session not found.' using errcode = '42501';
  end if;

  select count(*), count(selected_index), count(*) filter (where is_correct = true)
    into v_total, v_answered, v_correct
  from public.knowledge_check_session_questions
  where session_id = p_session_id;

  if v_total = 0 or v_answered < v_total then
    raise exception 'Answer every question before completing this session.' using errcode = '22023';
  end if;

  update public.knowledge_check_sessions
  set status = 'completed', completed_at = coalesce(completed_at, now())
  where id = p_session_id;

  perform public.refresh_learner_topic_progression(v_user_id);

  return jsonb_build_object(
    'session_id', p_session_id,
    'correct', v_correct,
    'total', v_total,
    'topics', (
      select coalesce(jsonb_agg(row_to_json(x) order by x.topic_id), '[]'::jsonb)
      from (
        select topic_id,
               count(*) filter (where is_correct = true)::integer as correct,
               count(*)::integer as total
        from public.knowledge_check_session_questions
        where session_id = p_session_id
        group by topic_id
      ) x
    ),
    'ranks', (
      select coalesce(jsonb_agg(row_to_json(lp) order by lp.topic_id), '[]'::jsonb)
      from public.learner_topic_progression lp
      where lp.user_id = v_user_id
    )
  );
end;
$$;


ALTER FUNCTION "public"."complete_adaptive_knowledge_check"("p_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_verification_session"("p_session_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user uuid := auth.uid();
  v_expected integer;
  v_done integer;
  v_average integer;
  v_scores jsonb;
begin
  if v_user is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not exists (select 1 from public.verification_sessions where id=p_session_id and user_id=v_user) then
    raise exception 'Verification session not found.' using errcode='42501';
  end if;
  select count(*) into v_expected from public.verification_session_cases where session_id=p_session_id;
  select count(*), coalesce(round(avg(total_score))::integer,0)
    into v_done, v_average
  from public.verification_case_attempts where session_id=p_session_id and user_id=v_user;
  if v_done < v_expected then raise exception 'Complete every verification case first.' using errcode='P0001'; end if;

  select coalesce(jsonb_object_agg(subskill, score), '{}'::jsonb) into v_scores
  from (
    select subskill, round(avg(total_score))::integer as score
    from public.verification_case_attempts
    where session_id=p_session_id and user_id=v_user
    group by subskill
  ) x;

  update public.verification_sessions
  set status='completed', completed_at=now()
  where id=p_session_id and user_id=v_user;

  return jsonb_build_object(
    'session_id', p_session_id,
    'average_score', v_average,
    'completed_cases', v_done,
    'subskill_scores', v_scores
  );
end;
$$;


ALTER FUNCTION "public"."complete_verification_session"("p_session_id" "uuid") OWNER TO "postgres";


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


ALTER FUNCTION "public"."create_adaptive_knowledge_check"("p_question_count" integer, "p_focus_topic" "text", "p_mode" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_adaptive_verification_session"("p_case_count" integer DEFAULT 5, "p_rank_level" integer DEFAULT 1) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user uuid := auth.uid();
  v_count integer := greatest(4, least(8, coalesce(p_case_count, 5)));
  v_rank integer := greatest(1, least(5, coalesce(p_rank_level, 1)));
  v_session uuid;
  v_selected integer;
  v_result jsonb;
begin
  if v_user is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  update public.verification_sessions
  set status = 'abandoned', completed_at = now()
  where user_id = v_user and status = 'active';

  insert into public.verification_sessions (user_id, rank_level)
  values (v_user, v_rank)
  returning id into v_session;

  with eligible as (
    select
      c.id,
      c.subskill,
      c.difficulty,
      coalesce(m.mastery, 0) as subskill_mastery,
      e.times_seen,
      e.last_seen_at,
      row_number() over (
        partition by c.subskill
        order by
          case when e.case_id is null then 0 else 1 end,
          coalesce(e.last_seen_at, '1900-01-01'::timestamptz),
          abs(c.difficulty - v_rank),
          md5(c.id::text || v_user::text || current_date::text)
      ) as within_subskill
    from public.verification_cases c
    left join public.verification_subskill_mastery m
      on m.user_id = v_user and m.subskill = c.subskill
    left join public.verification_case_exposure e
      on e.user_id = v_user and e.case_id = c.id
    where c.status = 'published'
      and (c.expires_at is null or c.expires_at > now())
      and (
        (v_rank = 1 and c.difficulty = 1)
        or
        (v_rank > 1 and c.difficulty between greatest(1, v_rank - 1) and v_rank)
      )
  ), ranked as (
    select *,
      case when within_subskill = 1 then 0 else 1 end as diversity_bucket
    from eligible
  ), chosen as (
    select id,
      row_number() over (
        order by
          diversity_bucket,
          subskill_mastery,
          case when times_seen is null then 0 else 1 end,
          coalesce(last_seen_at, '1900-01-01'::timestamptz),
          abs(difficulty - v_rank),
          md5(id::text || clock_timestamp()::text)
      ) as seq
    from ranked
    order by
      diversity_bucket,
      subskill_mastery,
      case when times_seen is null then 0 else 1 end,
      coalesce(last_seen_at, '1900-01-01'::timestamptz),
      abs(difficulty - v_rank),
      md5(id::text || clock_timestamp()::text)
    limit v_count
  )
  insert into public.verification_session_cases (session_id, case_id, sequence)
  select v_session, id, seq from chosen;

  select count(*) into v_selected
  from public.verification_session_cases
  where session_id = v_session;

  if v_selected < 4 then
    delete from public.verification_sessions where id = v_session;
    raise exception 'Not enough verification examples are available right now.' using errcode = 'P0001';
  end if;

  select jsonb_build_object(
    'session_id', v_session,
    'rank_level', v_rank,
    'started_at', s.started_at,
    'cases', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'case_id', c.id,
          'case_code', c.case_code,
          'title', c.title,
          'scenario', c.scenario,
          'claim_text', c.claim_text,
          'case_type', c.case_type,
          'subskill', c.subskill,
          'difficulty', c.difficulty,
          'media_type', c.media_type,
          'media_url', c.media_url,
          'media_description', c.media_description,
          'evidence', c.evidence,
          'actions', c.actions,
          'source_options', c.source_options,
          'correct_decision', c.correct_decision,
          'expected_confidence', c.expected_confidence,
          'explanation', c.explanation,
          'learning_point', c.learning_point,
          'source_name', c.source_name,
          'source_url', c.source_url,
          'source_published_at', c.source_published_at,
          'generated_by', c.generated_by,
          'sequence', sc.sequence
        ) order by sc.sequence
      ),
      '[]'::jsonb
    )
  ) into v_result
  from public.verification_sessions s
  join public.verification_session_cases sc on sc.session_id = s.id
  join public.verification_cases c on c.id = sc.case_id
  where s.id = v_session
  group by s.id, s.started_at;

  return v_result;
end;
$$;


ALTER FUNCTION "public"."create_adaptive_verification_session"("p_case_count" integer, "p_rank_level" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_phase7_generated_draft_queue_cap"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_cap integer;
  v_pending integer;
begin
  perform pg_advisory_xact_lock(hashtext('promptwise_phase7_draft_queue_cap'));

  if new.status <> 'draft' then
    return new;
  end if;

  -- Only count when a row newly enters the pending queue.
  if tg_op = 'UPDATE' and old.status = 'draft' then
    return new;
  end if;

  select max_pending_drafts into v_cap
  from public.automation_settings where id = 1;
  v_cap := coalesce(v_cap, 30);

  select count(*)::integer into v_pending
  from public.generated_content_drafts
  where status = 'draft'
    and (tg_op <> 'UPDATE' or id <> new.id);

  if v_pending >= v_cap then
    raise exception 'AI lesson draft queue is full (%/%). Review or archive pending drafts before generating more.', v_pending, v_cap
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."enforce_phase7_generated_draft_queue_cap"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_phase7_question_review_queue_cap"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_cap integer;
  v_pending integer;
begin
  perform pg_advisory_xact_lock(hashtext('promptwise_phase7_question_queue_cap'));

  if new.generated_by <> 'content_automation'
     or new.validation_status <> 'needs_review'
     or new.status = 'archived' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.generated_by = 'content_automation'
     and old.validation_status = 'needs_review'
     and old.status <> 'archived' then
    return new;
  end if;

  select max_pending_questions into v_cap
  from public.automation_settings where id = 1;
  v_cap := coalesce(v_cap, 100);

  select count(*)::integer into v_pending
  from public.question_bank
  where generated_by = 'content_automation'
    and validation_status = 'needs_review'
    and status <> 'archived'
    and (tg_op <> 'UPDATE' or id <> new.id);

  if v_pending >= v_cap then
    raise exception 'AI question review queue is full (%/%). Review pending questions before approving more generated lessons.', v_pending, v_cap
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."enforce_phase7_question_review_queue_cap"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_verification_activity_topic"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.content_type = 'activity' then
    new.adaptive_topic := 'verification';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."enforce_verification_activity_topic"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_adaptive_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
declare
  v_user uuid := auth.uid();
  v_mastery jsonb := '[]'::jsonb;
  v_attempts jsonb := '[]'::jsonb;
  v_diagnostic_completed boolean := false;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Use dynamic SQL so this traffic migration can still be installed safely
  -- on an older database where the Phase 8 rebuild helper is not present yet.
  if to_regprocedure('public.rebuild_adaptive_mastery_for_user(uuid)') is not null then
    execute 'select public.rebuild_adaptive_mastery_for_user($1)' using v_user;
  end if;

  if to_regclass('public.topic_mastery') is not null then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'topic_id', tm.topic_id,
          'mastery', tm.mastery,
          'attempts', tm.attempts,
          'correct_answers', tm.correct_answers,
          'last_practiced_at', tm.last_practiced_at,
          'next_review_at', tm.next_review_at
        )
        order by tm.topic_id
      ),
      '[]'::jsonb
    )
    into v_mastery
    from public.topic_mastery tm
    where tm.user_id = v_user;
  end if;

  if to_regclass('public.assessment_attempts') is not null then
    select exists(
      select 1
      from public.assessment_attempts aa
      where aa.user_id = v_user
        and aa.assessment_type = 'diagnostic'
    )
    into v_diagnostic_completed;
  end if;

  if to_regclass('public.question_attempts') is not null then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'item_id', q.item_id,
          'topic_id', q.topic_id,
          'is_correct', q.is_correct,
          'attempt_type', q.attempt_type,
          'counted_for_mastery', true,
          'attempted_at', q.attempted_at
        )
        order by q.attempted_at
      ),
      '[]'::jsonb
    )
    into v_attempts
    from (
      select distinct on (qa.item_id, qa.topic_id)
        qa.item_id,
        qa.topic_id,
        qa.is_correct,
        qa.attempt_type,
        qa.attempted_at
      from public.question_attempts qa
      where qa.user_id = v_user
        and qa.counted_for_mastery = true
      order by qa.item_id, qa.topic_id, qa.attempted_at desc
    ) q;
  end if;

  return jsonb_build_object(
    'canonical', true,
    'diagnostic_completed', v_diagnostic_completed,
    'mastery', v_mastery,
    'counted_attempts', v_attempts
  );
end;
$_$;


ALTER FUNCTION "public"."get_my_adaptive_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_awareness_feed_cache"("p_limit" integer DEFAULT 80) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select coalesce(jsonb_agg(item order by relevance_score desc, published_at desc nulls last), '[]'::jsonb)
  from (
    select
      jsonb_build_object(
        'id', a.id,
        'title', a.title,
        'summary', a.summary,
        'why_it_matters', a.why_it_matters,
        'source_name', a.source_name,
        'source_domain', a.source_domain,
        'source_url', a.source_url,
        'image_url', a.image_url,
        'published_at', a.published_at,
        'discovered_at', a.discovered_at,
        'category', a.category,
        'region', a.region,
        'relevance_score', a.relevance_score,
        'trust_level', a.trust_level,
        'read', (ua.read_at is not null),
        'saved', (ua.saved_at is not null)
      ) as item,
      a.relevance_score,
      a.published_at
    from public.awareness_articles a
    left join public.awareness_user_actions ua
      on ua.article_id = a.id
     and ua.user_id = auth.uid()
    where a.is_active = true
    order by a.relevance_score desc, a.published_at desc nulls last
    limit least(greatest(coalesce(p_limit, 80), 10), 80)
  ) q;
$$;


ALTER FUNCTION "public"."get_my_awareness_feed_cache"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_phase7_queue_health"() RETURNS TABLE("pending_drafts" integer, "pending_questions" integer, "archived_drafts" integer, "expiring_drafts_soon" integer, "expiring_questions_soon" integer, "max_pending_drafts" integer, "max_pending_questions" integer, "draft_archive_days" integer, "rejected_delete_days" integer, "archived_delete_days" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  s public.automation_settings%rowtype;
begin
  if not public.is_promptwise_admin() then
    raise exception 'Administrator access required.' using errcode = '42501';
  end if;

  select * into s from public.automation_settings where id = 1;

  return query
  select
    (select count(*)::integer from public.generated_content_drafts where status = 'draft'),
    (select count(*)::integer from public.question_bank
      where generated_by = 'content_automation'
        and validation_status = 'needs_review'
        and status <> 'archived'),
    (select count(*)::integer from public.generated_content_drafts where status = 'archived'),
    (select count(*)::integer from public.generated_content_drafts
      where status = 'draft'
        and created_at <= now() - make_interval(days => greatest(0, s.draft_archive_days - 5))),
    (select count(*)::integer from public.question_bank
      where generated_by = 'content_automation'
        and validation_status = 'needs_review'
        and status <> 'archived'
        and created_at <= now() - make_interval(days => greatest(0, s.draft_archive_days - 5))),
    s.max_pending_drafts,
    s.max_pending_questions,
    s.draft_archive_days,
    s.rejected_delete_days,
    s.archived_delete_days;
end;
$$;


ALTER FUNCTION "public"."get_phase7_queue_health"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_prompt_coach_recent_sessions"("p_limit" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "title" "text", "focus_topic" "text", "revision_count" integer, "first_score" integer, "latest_score" integer, "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  select
    s.id,
    s.title,
    s.focus_topic,
    count(r.id)::integer as revision_count,
    coalesce((array_agg(r.overall_score order by r.revision_number asc))[1], 0)::integer as first_score,
    coalesce((array_agg(r.overall_score order by r.revision_number desc))[1], 0)::integer as latest_score,
    s.created_at,
    s.updated_at
  from public.prompt_coach_sessions s
  left join public.prompt_coach_revisions r on r.session_id = s.id
  where s.user_id = auth.uid()
  group by s.id, s.title, s.focus_topic, s.created_at, s.updated_at
  order by s.updated_at desc
  limit greatest(1, least(coalesce(p_limit, 8), 30));
$$;


ALTER FUNCTION "public"."get_prompt_coach_recent_sessions"("p_limit" integer) OWNER TO "postgres";


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

  if v_settings.last_manual_success_at is not null then
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
    'groq_requests_remaining', greatest(0, v_settings.monthly_groq_request_cap - v_groq_month),
    'cooldown_remaining_minutes', v_cooldown_remaining,
    'remaining_today', greatest(0, v_settings.max_drafts_per_day - v_today),
    'remaining_this_month', greatest(0, v_settings.monthly_draft_cap - v_month)
  );
end;
$$;


ALTER FUNCTION "public"."get_verification_automation_overview"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    coalesce(new.email, ''),
    left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 80),
    'learner'::public.app_role
  )
  on conflict (id) do nothing;

  insert into public.learner_progress (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_administrator"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role = 'administrator'::public.app_role
  );
$$;


ALTER FUNCTION "public"."is_administrator"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_promptwise_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'administrator'
  );
$$;


ALTER FUNCTION "public"."is_promptwise_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."phase7_cleanup_content_queues"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  s public.automation_settings%rowtype;
  v_archived_drafts integer := 0;
  v_archived_questions integer := 0;
  v_deleted_rejected_drafts integer := 0;
  v_deleted_rejected_questions integer := 0;
  v_deleted_archived_drafts integer := 0;
  v_deleted_archived_questions integer := 0;
  v_deleted_articles integer := 0;
  v_deleted_runs integer := 0;
begin
  select * into s from public.automation_settings where id = 1;
  if not found then
    raise exception 'Automation settings are missing.';
  end if;

  update public.generated_content_drafts
  set status = 'archived', archived_at = now()
  where status = 'draft'
    and created_at < now() - make_interval(days => s.draft_archive_days);
  get diagnostics v_archived_drafts = row_count;

  update public.question_bank
  set status = 'archived', updated_at = now()
  where generated_by = 'content_automation'
    and validation_status = 'needs_review'
    and status <> 'archived'
    and created_at < now() - make_interval(days => s.draft_archive_days);
  get diagnostics v_archived_questions = row_count;

  delete from public.generated_content_drafts
  where status = 'rejected'
    and coalesce(reviewed_at, created_at) < now() - make_interval(days => s.rejected_delete_days);
  get diagnostics v_deleted_rejected_drafts = row_count;

  delete from public.question_bank qb
  where qb.generated_by = 'content_automation'
    and qb.validation_status = 'rejected'
    and qb.status = 'archived'
    and qb.updated_at < now() - make_interval(days => s.rejected_delete_days)
    and not exists (
      select 1 from public.knowledge_check_session_questions sq
      where sq.question_id = qb.id
    );
  get diagnostics v_deleted_rejected_questions = row_count;

  delete from public.generated_content_drafts
  where status = 'archived'
    and coalesce(archived_at, created_at) < now() - make_interval(days => s.archived_delete_days);
  get diagnostics v_deleted_archived_drafts = row_count;

  -- Only stale, never-approved AI questions are removed. Verified/manual
  -- question-bank items are retained even when archived by an administrator.
  delete from public.question_bank qb
  where qb.generated_by = 'content_automation'
    and qb.validation_status = 'needs_review'
    and qb.status = 'archived'
    and qb.updated_at < now() - make_interval(days => s.archived_delete_days)
    and not exists (
      select 1 from public.knowledge_check_session_questions sq
      where sq.question_id = qb.id
    );
  get diagnostics v_deleted_archived_questions = row_count;

  -- Processed articles stay as durable duplicate markers. Only failed/ignored
  -- discovery noise ages out and may be reconsidered after the retention period.
  delete from public.discovered_articles
  where status in ('failed', 'ignored')
    and coalesce(processed_at, discovered_at) < now() - make_interval(days => s.article_cleanup_days);
  get diagnostics v_deleted_articles = row_count;

  delete from public.automation_runs
  where status <> 'running'
    and started_at < now() - make_interval(days => s.run_log_retention_days);
  get diagnostics v_deleted_runs = row_count;

  return jsonb_build_object(
    'archived_drafts', v_archived_drafts,
    'archived_questions', v_archived_questions,
    'deleted_rejected_drafts', v_deleted_rejected_drafts,
    'deleted_rejected_questions', v_deleted_rejected_questions,
    'deleted_archived_drafts', v_deleted_archived_drafts,
    'deleted_archived_questions', v_deleted_archived_questions,
    'deleted_articles', v_deleted_articles,
    'deleted_runs', v_deleted_runs
  );
end;
$$;


ALTER FUNCTION "public"."phase7_cleanup_content_queues"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."phase9_cleanup_awareness_feed"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_archive_days integer := 45;
  v_archived integer := 0;
  v_deleted_runs integer := 0;
begin
  if not public.awareness_is_admin() then
    raise exception 'Administrator access required.' using errcode = '42501';
  end if;

  select archive_after_days
    into v_archive_days
  from public.awareness_feed_settings
  where id = 1;

  update public.awareness_articles
  set is_active = false,
      updated_at = now()
  where is_active = true
    and published_at is not null
    and published_at < now() - make_interval(days => coalesce(v_archive_days, 45));
  get diagnostics v_archived = row_count;

  delete from public.awareness_refresh_runs
  where started_at < now() - interval '30 days';
  get diagnostics v_deleted_runs = row_count;

  return jsonb_build_object(
    'archived_articles', v_archived,
    'deleted_refresh_runs', v_deleted_runs
  );
end;
$$;


ALTER FUNCTION "public"."phase9_cleanup_awareness_feed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."phase9_cleanup_verification_queues"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_settings public.verification_automation_settings%rowtype;
  v_archived_drafts integer := 0;
  v_deleted_rejected integer := 0;
  v_deleted_archived integer := 0;
  v_archived_cases integer := 0;
begin
  select * into v_settings from public.verification_automation_settings where id=1;
  update public.verification_case_drafts
  set status='archived', updated_at=now()
  where status='draft' and created_at < now() - make_interval(days=>v_settings.draft_archive_days);
  get diagnostics v_archived_drafts = row_count;

  delete from public.verification_case_drafts
  where status='rejected' and coalesce(reviewed_at,updated_at) < now() - make_interval(days=>v_settings.rejected_delete_days);
  get diagnostics v_deleted_rejected = row_count;

  delete from public.verification_case_drafts
  where status='archived' and updated_at < now() - make_interval(days=>v_settings.archived_delete_days);
  get diagnostics v_deleted_archived = row_count;

  update public.verification_cases
  set status='archived', updated_at=now()
  where status='published' and generated_by='content_automation'
    and expires_at is not null and expires_at < now();
  get diagnostics v_archived_cases = row_count;

  return jsonb_build_object(
    'archived_drafts',v_archived_drafts,
    'deleted_rejected_drafts',v_deleted_rejected,
    'deleted_old_archived_drafts',v_deleted_archived,
    'archived_expired_dynamic_cases',v_archived_cases
  );
end;
$$;


ALTER FUNCTION "public"."phase9_cleanup_verification_queues"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."phase9_is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'administrator'
  );
$$;


ALTER FUNCTION "public"."phase9_is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prompt_coach_ai_usage_status"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user uuid := auth.uid();
  v_day date := (now() at time zone 'Asia/Manila')::date;
  v_used integer := 0;
  v_limit constant integer := 3;
  v_reset timestamptz;
begin
  if v_user is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select coalesce(ai_uses, 0) into v_used
  from public.prompt_coach_daily_usage
  where user_id = v_user and usage_date = v_day;
  v_used := coalesce(v_used, 0);
  v_reset := ((v_day + 1)::timestamp at time zone 'Asia/Manila');

  return jsonb_build_object(
    'used', v_used,
    'limit', v_limit,
    'remaining', greatest(0, v_limit - v_used),
    'reset_at', v_reset
  );
end;
$$;


ALTER FUNCTION "public"."prompt_coach_ai_usage_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prompt_coach_server_topic_score"("p_prompt" "text", "p_topic" "text") RETURNS integer
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_text text := lower(coalesce(p_prompt, ''));
  v_words integer := coalesce(array_length(regexp_split_to_array(trim(coalesce(p_prompt, '')), '\s+'), 1), 0);
  v_score integer := 0;
begin
  if p_topic = 'prompt_clarity' then
    if v_text ~ '(analyze|create|define|describe|design|evaluate|explain|identify|list|make|outline|review|summarize|compare|write|classify|recommend|generate|revise|critique|gumawa|ipaliwanag|ihambing|ibuod|suriin|ilarawan|magbigay)' then
      v_score := v_score + 55;
    end if;
    if v_words >= 8 then v_score := v_score + 20; end if;
    if v_words >= 18 then v_score := v_score + 10; end if;
    if v_text ~ '(about|regarding|for |using|based on|tungkol|gamit|:)' then
      v_score := v_score + 15;
    end if;

  elsif p_topic = 'context' then
    if v_text ~ '(audience|beginner|student|teacher|reader|customer|manager|developer|para sa|estudyante|guro|mambabasa|target user)' then
      v_score := v_score + 35;
    end if;
    if v_text ~ '(purpose|goal|objective|so that|because|dahil|layunin|gamitin para)' then
      v_score := v_score + 30;
    end if;
    if v_text ~ '(background|context|given that|based on|scenario|situation|konteksto|batay sa|sitwasyon)' then
      v_score := v_score + 25;
    end if;
    if v_words >= 20 then v_score := v_score + 10; end if;

  elsif p_topic = 'specificity' then
    if v_text ~ '(paragraph|sentence|bullet|table|json|outline|report|email|presentation|code|format|structure|talata|pangungusap|pormat|listahan)' then
      v_score := v_score + 25;
    end if;
    if v_text ~ '\m[0-9]+\M' or v_text ~ '(short|concise|detailed|brief|words|characters|minutes|maikli|detalyado)' then
      v_score := v_score + 20;
    end if;
    if v_text ~ '(must|should|only|do not|don''t|avoid|limit|maximum|minimum|without|at least|no more than|required|constraint|bawal|iwasan|limitahan|dapat)' then
      v_score := v_score + 25;
    end if;
    if v_text ~ '(tone|formal|casual|professional|simple language|technical|friendly|academic|style|tono|simple words)' then
      v_score := v_score + 15;
    end if;
    if v_text ~ '(first|second|then|next|finally|step [0-9]|include|cover|address|isama|una|sunod)' then
      v_score := v_score + 15;
    end if;

  elsif p_topic = 'responsible_use' then
    -- Start with a safety baseline, but remove it when obvious private data is present.
    v_score := 40;
    if v_text ~ '([[:alnum:]._%+-]+@[[:alnum:].-]+\.[a-z]{2,}|password:|api key:|apikey:|secret key:|access token:|private key)' then
      v_score := 10;
    end if;
    if v_text ~ '(verify|verification|source|citation|evidence|uncertainty|limitations|check accuracy|fact check|cross-check|human review|beripikahin|sanggunian|pinagmulan|katumpakan)' then
      v_score := v_score + 35;
    end if;
    if v_text ~ '(privacy|personal data|sensitive|bias|fairness|ethical|responsible|do not fabricate|do not invent|acknowledge uncertainty|confidential|pribado)' then
      v_score := v_score + 25;
    end if;
  else
    return 0;
  end if;

  return greatest(0, least(100, v_score));
end;
$$;


ALTER FUNCTION "public"."prompt_coach_server_topic_score"("p_prompt" "text", "p_topic" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."publish_generated_content_draft"("p_draft_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_draft public.generated_content_drafts%rowtype;
  v_content_id text;
  v_body text;
  v_section text;
  v_objective jsonb;
  v_question jsonb;
  v_objective_code text;
  v_objective_id uuid;
  v_index integer := 0;
begin
  if not public.is_promptwise_admin() then
    raise exception 'Administrator access required.' using errcode = '42501';
  end if;

  select * into v_draft
  from public.generated_content_drafts
  where id = p_draft_id
  for update;

  if v_draft.id is null or v_draft.status <> 'draft' then
    raise exception 'Draft is unavailable for approval.' using errcode = '22023';
  end if;

  v_content_id := 'auto_' || replace(p_draft_id::text, '-', '');
  v_body := '';
  for v_section in
    select jsonb_array_elements_text(coalesce(v_draft.draft_payload->'lesson_sections', '[]'::jsonb))
  loop
    v_body := v_body || case when v_body = '' then '' else E'\n\n' end || v_section;
  end loop;

  insert into public.content_items (
    id, content_type, parent_id, title, description, body,
    icon, estimated_minutes, sort_order, adaptive_topic, status,
    source_url, publication_date, learning_level
  ) values (
    v_content_id,
    'lesson',
    case v_draft.topic_id
      when 'prompt_clarity' then 'p7_module_prompt_clarity'
      when 'context' then 'p7_module_context'
      when 'specificity' then 'p7_module_specificity'
      when 'responsible_use' then 'p7_module_responsible_use'
      when 'verification' then 'p7_module_verification'
      else null
    end,
    v_draft.title,
    v_draft.summary,
    v_body,
    'school',
    greatest(8, least(25, 8 + v_draft.target_level * 2)),
    900,
    v_draft.topic_id,
    'draft',
    v_draft.source_url,
    v_draft.source_published_at::date,
    v_draft.target_level
  )
  on conflict (id) do update set
    title = excluded.title,
    description = excluded.description,
    body = excluded.body,
    adaptive_topic = excluded.adaptive_topic,
    status = 'draft',
    source_url = excluded.source_url,
    publication_date = excluded.publication_date,
    learning_level = excluded.learning_level;

  for v_objective in
    select value from jsonb_array_elements(coalesce(v_draft.draft_payload->'objectives', '[]'::jsonb))
  loop
    v_index := v_index + 1;
    v_objective_code := 'auto_' || replace(p_draft_id::text, '-', '') || '_o' || v_index::text;
    insert into public.learning_objectives (
      content_item_id, topic_id, objective_code, title, description,
      required_level, sort_order, status
    ) values (
      v_content_id,
      v_draft.topic_id,
      v_objective_code,
      coalesce(v_objective->>'title', v_objective#>>'{}'),
      coalesce(v_objective->>'description', ''),
      v_draft.target_level,
      v_index,
      'draft'
    )
    on conflict (objective_code) do update set
      title = excluded.title,
      description = excluded.description,
      required_level = excluded.required_level,
      status = 'draft'
    returning id into v_objective_id;
  end loop;

  v_index := 0;
  for v_question in
    select value from jsonb_array_elements(coalesce(v_draft.draft_payload->'questions', '[]'::jsonb))
  loop
    v_index := v_index + 1;
    select id into v_objective_id
    from public.learning_objectives
    where content_item_id = v_content_id
    order by sort_order
    offset greatest(0, least(v_index - 1, 2))
    limit 1;

    insert into public.question_bank (
      question_code, source_content_id, objective_id, topic_id,
      question_type, stem, options, correct_index, explanation,
      difficulty, status, validation_status, quality_score,
      source_url, source_published_at, generated_by
    ) values (
      'auto_' || replace(p_draft_id::text, '-', '') || '_q' || v_index::text,
      v_content_id,
      v_objective_id,
      v_draft.topic_id,
      coalesce(v_question->>'question_type', 'scenario'),
      v_question->>'stem',
      v_question->'options',
      coalesce((v_question->>'correct_index')::integer, 0),
      coalesce(v_question->>'explanation', ''),
      greatest(1, least(5, coalesce((v_question->>'difficulty')::integer, v_draft.target_level))),
      'draft',
      'needs_review',
      0.70,
      v_draft.source_url,
      v_draft.source_published_at,
      'content_automation'
    )
    on conflict (question_code) do nothing;
  end loop;

  update public.generated_content_drafts
  set status = 'approved',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      published_content_id = v_content_id
  where id = p_draft_id;

  return v_content_id;
end;
$$;


ALTER FUNCTION "public"."publish_generated_content_draft"("p_draft_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rebuild_adaptive_mastery_for_user"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
declare
  v_topic text;
  v_question_id text;
  v_correct_index integer;
  v_event record;
  v_mastery integer;
  v_attempts integer;
  v_correct integer;
  v_last timestamptz;
  v_due timestamptz;
  v_days integer;
begin
  foreach v_topic in array array[
    'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification'
  ] loop
    v_question_id := case v_topic
      when 'prompt_clarity' then 'diagnostic_prompt_clarity'
      when 'context' then 'diagnostic_context'
      when 'specificity' then 'diagnostic_specificity'
      when 'responsible_use' then 'diagnostic_responsible_use'
      when 'verification' then 'diagnostic_verification'
    end;
    v_correct_index := case v_topic
      when 'prompt_clarity' then 1
      when 'context' then 1
      when 'specificity' then 0
      when 'responsible_use' then 2
      when 'verification' then 1
    end;

    v_mastery := 0;
    v_attempts := 0;
    v_correct := 0;
    v_last := null;
    v_due := null;

    for v_event in
      select occurred_at, is_correct, diagnostic_evidence
      from (
        select
          aa.completed_at as occurred_at,
          ((aa.answers ->> v_question_id)::integer = v_correct_index) as is_correct,
          true as diagnostic_evidence
        from public.assessment_attempts aa
        where aa.user_id = p_user_id
          and aa.assessment_type = 'diagnostic'
          and aa.answers ? v_question_id
          and (aa.answers ->> v_question_id) ~ '^[0-9]+$'

        union all

        select
          qa.attempted_at as occurred_at,
          qa.is_correct,
          false as diagnostic_evidence
        from public.question_attempts qa
        where qa.user_id = p_user_id
          and qa.topic_id = v_topic
          and qa.counted_for_mastery = true

        union all

        select
          pce.created_at as occurred_at,
          pce.is_correct,
          false as diagnostic_evidence
        from public.prompt_coach_mastery_evidence pce
        where pce.user_id = p_user_id
          and pce.topic_id = v_topic
          and pce.counted_for_mastery = true
      ) events
      order by occurred_at, diagnostic_evidence desc
    loop
      if v_attempts = 0 then
        if v_event.diagnostic_evidence then
          v_mastery := case when v_event.is_correct then 70 else 30 end;
        else
          v_mastery := case when v_event.is_correct then 65 else 35 end;
        end if;
      else
        v_mastery := round(
          v_mastery * 0.75 +
          (case when v_event.is_correct then 100 else 0 end) * 0.25
        )::integer;
      end if;

      v_attempts := v_attempts + 1;
      if v_event.is_correct then v_correct := v_correct + 1; end if;
      v_last := v_event.occurred_at;
      v_days := case
        when v_mastery < 40 then 1
        when v_mastery < 60 then 2
        when v_mastery < 80 then 4
        else 7
      end;
      v_due := v_last + make_interval(days => v_days);
    end loop;

    if v_attempts = 0 then
      delete from public.topic_mastery
      where user_id = p_user_id and topic_id = v_topic;
      delete from public.review_schedule
      where user_id = p_user_id and topic_id = v_topic;
    else
      insert into public.topic_mastery (
        user_id, topic_id, mastery, attempts, correct_answers,
        last_practiced_at, next_review_at, updated_at
      ) values (
        p_user_id, v_topic, greatest(0, least(100, v_mastery)),
        v_attempts, v_correct, v_last, v_due, now()
      )
      on conflict (user_id, topic_id) do update set
        mastery = excluded.mastery,
        attempts = excluded.attempts,
        correct_answers = excluded.correct_answers,
        last_practiced_at = excluded.last_practiced_at,
        next_review_at = excluded.next_review_at,
        updated_at = now();

      insert into public.review_schedule (
        user_id, topic_id, due_at, mastery_snapshot, updated_at
      ) values (
        p_user_id, v_topic, v_due, greatest(0, least(100, v_mastery)), now()
      )
      on conflict (user_id, topic_id) do update set
        due_at = excluded.due_at,
        mastery_snapshot = excluded.mastery_snapshot,
        updated_at = now();
    end if;
  end loop;
end;
$_$;


ALTER FUNCTION "public"."rebuild_adaptive_mastery_for_user"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rebuild_my_adaptive_mastery"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  perform public.rebuild_adaptive_mastery_for_user(auth.uid());
end;
$$;


ALTER FUNCTION "public"."rebuild_my_adaptive_mastery"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_adaptive_attempt"("p_user_id" "uuid", "p_item_id" "text", "p_topic_id" "text", "p_is_correct" boolean, "p_attempt_type" "text" DEFAULT 'quiz'::"text", "p_counted_for_mastery" boolean DEFAULT true, "p_attempted_at" timestamp with time zone DEFAULT "now"()) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_effective_topic text := p_topic_id;
  v_content_type text;
  v_content_topic text;
  v_content_status text;
  v_last_counted timestamptz;
  v_due_at timestamptz;
  v_should_count boolean := false;
  -- Online evidence uses database time. Client/device clocks must not be able
  -- to jump ahead of a spaced-review deadline and farm mastery.
  v_occurred_at timestamptz := now();
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Not authorized to record adaptive evidence for this learner.'
      using errcode = '42501';
  end if;
  if nullif(trim(p_item_id), '') is null then
    raise exception 'Adaptive item ID is required.' using errcode = '22023';
  end if;
  if p_topic_id is null or p_topic_id not in (
    'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification'
  ) then
    raise exception 'Unknown adaptive topic.' using errcode = '22023';
  end if;

  if p_attempt_type is null or p_attempt_type not in (
    'quiz', 'legacy_quiz', 'verification_activity'
  ) then
    raise exception 'Unknown adaptive attempt type.' using errcode = '22023';
  end if;

  select ci.content_type, ci.adaptive_topic, ci.status
    into v_content_type, v_content_topic, v_content_status
  from public.content_items ci
  where ci.id = p_item_id
  limit 1;

  if v_content_type is null
     or v_content_type not in ('quiz', 'activity')
     or v_content_status is distinct from 'published' then
    return false;
  end if;

  if v_content_type = 'activity' then
    if p_attempt_type <> 'verification_activity' then
      return false;
    end if;
    v_effective_topic := 'verification';
  else
    if p_attempt_type = 'verification_activity' then
      return false;
    end if;
    if v_content_topic is null then
      return false;
    end if;
    v_effective_topic := v_content_topic;
  end if;

  -- Serialize decisions for one learner/item/topic to stop double taps or two
  -- browser requests from both becoming mastery evidence.
  perform pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || '|' || p_item_id || '|' || v_effective_topic, 0)
  );

  select max(qa.attempted_at)
    into v_last_counted
  from public.question_attempts qa
  where qa.user_id = p_user_id
    and qa.item_id = p_item_id
    and qa.topic_id = v_effective_topic
    and qa.counted_for_mastery = true;

  if p_counted_for_mastery then
    if p_attempt_type = 'legacy_quiz' then
      v_should_count := v_last_counted is null;
    elsif v_last_counted is null then
      v_should_count := true;
    else
      select tm.next_review_at
        into v_due_at
      from public.topic_mastery tm
      where tm.user_id = p_user_id
        and tm.topic_id = v_effective_topic;

      v_should_count := v_due_at is not null
        and v_occurred_at >= v_due_at
        and v_last_counted < v_due_at;
    end if;
  end if;

  insert into public.question_attempts (
    user_id, item_id, topic_id, is_correct, attempt_type,
    counted_for_mastery, attempted_at, attempt_day
  ) values (
    p_user_id, trim(p_item_id), v_effective_topic, p_is_correct,
    coalesce(nullif(trim(p_attempt_type), ''), 'quiz'),
    v_should_count, v_occurred_at,
    (v_occurred_at at time zone 'Asia/Manila')::date
  );

  if v_should_count then
    perform public.rebuild_adaptive_mastery_for_user(p_user_id);
  end if;
  return v_should_count;
end;
$$;


ALTER FUNCTION "public"."record_adaptive_attempt"("p_user_id" "uuid", "p_item_id" "text", "p_topic_id" "text", "p_is_correct" boolean, "p_attempt_type" "text", "p_counted_for_mastery" boolean, "p_attempted_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_adaptive_diagnostic"("p_user_id" "uuid", "p_score" integer, "p_correct_answers" integer, "p_total_questions" integer, "p_answers" "jsonb", "p_completed_at" timestamp with time zone DEFAULT "now"()) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Not authorized to record this diagnostic.' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || '|diagnostic', 0));

  if exists (
    select 1 from public.assessment_attempts
    where user_id = p_user_id and assessment_type = 'diagnostic'
  ) then
    return false;
  end if;

  insert into public.assessment_attempts (
    user_id, assessment_type, score, correct_answers,
    total_questions, answers, completed_at
  ) values (
    p_user_id, 'diagnostic', greatest(0, least(100, p_score)),
    greatest(0, p_correct_answers), greatest(0, p_total_questions),
    coalesce(p_answers, '{}'::jsonb), now()
  );

  perform public.rebuild_adaptive_mastery_for_user(p_user_id);
  return true;
end;
$$;


ALTER FUNCTION "public"."record_adaptive_diagnostic"("p_user_id" "uuid", "p_score" integer, "p_correct_answers" integer, "p_total_questions" integer, "p_answers" "jsonb", "p_completed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_learning_question_answer"("p_session_id" "uuid", "p_question_id" "uuid", "p_selected_index" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_question record;
  v_existing record;
  v_is_correct boolean;
  v_should_count boolean := false;
  v_last_counted timestamptz;
  v_due_at timestamptz;
  v_daily_count integer;
  v_mastery integer;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user_id::text || '|' || p_session_id::text || '|' || p_question_id::text, 0)
  );

  select
    s.user_id,
    s.status as session_status,
    sq.selected_index,
    sq.is_correct,
    sq.counted_for_mastery,
    qb.correct_index,
    qb.explanation,
    qb.topic_id,
    qb.difficulty,
    qb.objective_id,
    jsonb_array_length(qb.options) as option_count
  into v_question
  from public.knowledge_check_sessions s
  join public.knowledge_check_session_questions sq
    on sq.session_id = s.id and sq.question_id = p_question_id
  join public.question_bank qb on qb.id = sq.question_id
  where s.id = p_session_id;

  if v_question.user_id is null or v_question.user_id <> v_user_id then
    raise exception 'Knowledge-check session not found.' using errcode = '42501';
  end if;
  if v_question.session_status <> 'active' then
    raise exception 'This knowledge-check session is no longer active.' using errcode = '22023';
  end if;
  if p_selected_index < 0 or p_selected_index >= v_question.option_count then
    raise exception 'Selected answer is outside the available options.' using errcode = '22023';
  end if;

  -- Idempotent double-click protection: return the saved result.
  if v_question.selected_index is not null then
    select mastery into v_mastery
    from public.topic_mastery
    where user_id = v_user_id and topic_id = v_question.topic_id;
    return jsonb_build_object(
      'question_id', p_question_id,
      'is_correct', v_question.is_correct,
      'counted_for_mastery', coalesce(v_question.counted_for_mastery, false),
      'correct_index', v_question.correct_index,
      'explanation', v_question.explanation,
      'mastery_after', coalesce(v_mastery, 0)
    );
  end if;

  v_is_correct := p_selected_index = v_question.correct_index;

  select max(qa.attempted_at)
    into v_last_counted
  from public.question_attempts qa
  where qa.user_id = v_user_id
    and qa.item_id = p_question_id::text
    and qa.topic_id = v_question.topic_id
    and qa.attempt_type = 'question_bank'
    and qa.counted_for_mastery = true;

  select count(*)
    into v_daily_count
  from public.question_attempts qa
  where qa.user_id = v_user_id
    and qa.topic_id = v_question.topic_id
    and qa.attempt_type = 'question_bank'
    and qa.counted_for_mastery = true
    and (qa.attempted_at at time zone 'Asia/Manila')::date
      = (v_now at time zone 'Asia/Manila')::date;

  if v_daily_count < 4 then
    if v_last_counted is null then
      v_should_count := true;
    else
      select tm.next_review_at into v_due_at
      from public.topic_mastery tm
      where tm.user_id = v_user_id and tm.topic_id = v_question.topic_id;
      v_should_count := v_due_at is not null
        and v_now >= v_due_at
        and v_last_counted < v_due_at;
    end if;
  end if;

  update public.knowledge_check_session_questions
  set selected_index = p_selected_index,
      is_correct = v_is_correct,
      counted_for_mastery = v_should_count,
      answered_at = v_now
  where session_id = p_session_id and question_id = p_question_id;

  insert into public.question_exposure (
    user_id, question_id, times_seen, times_answered, correct_count,
    first_seen_at, last_seen_at, last_answered_at, last_is_correct
  ) values (
    v_user_id, p_question_id, 1, 1, case when v_is_correct then 1 else 0 end,
    v_now, v_now, v_now, v_is_correct
  )
  on conflict (user_id, question_id) do update set
    times_seen = public.question_exposure.times_seen + 1,
    times_answered = public.question_exposure.times_answered + 1,
    correct_count = public.question_exposure.correct_count + case when v_is_correct then 1 else 0 end,
    last_seen_at = v_now,
    last_answered_at = v_now,
    last_is_correct = v_is_correct;

  insert into public.question_attempts (
    user_id, item_id, topic_id, is_correct, attempt_type,
    counted_for_mastery, attempted_at, attempt_day
  ) values (
    v_user_id,
    p_question_id::text,
    v_question.topic_id,
    v_is_correct,
    'question_bank',
    v_should_count,
    v_now,
    (v_now at time zone 'Asia/Manila')::date
  );

  if v_should_count then
    perform public.rebuild_adaptive_mastery_for_user(v_user_id);
  end if;
  perform public.refresh_learner_topic_progression(v_user_id);

  select mastery into v_mastery
  from public.topic_mastery
  where user_id = v_user_id and topic_id = v_question.topic_id;

  return jsonb_build_object(
    'question_id', p_question_id,
    'is_correct', v_is_correct,
    'counted_for_mastery', v_should_count,
    'correct_index', v_question.correct_index,
    'explanation', v_question.explanation,
    'mastery_after', coalesce(v_mastery, 0)
  );
end;
$$;


ALTER FUNCTION "public"."record_learning_question_answer"("p_session_id" "uuid", "p_question_id" "uuid", "p_selected_index" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_prompt_coach_revision"("p_session_id" "uuid", "p_prompt_text" "text", "p_mode" "text", "p_rubric" "jsonb", "p_privacy_flags" "jsonb" DEFAULT '[]'::"jsonb", "p_standard_feedback" "jsonb" DEFAULT '{}'::"jsonb", "p_ai_guidance" "jsonb" DEFAULT NULL::"jsonb", "p_focus_topic" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user uuid := auth.uid();
  v_session uuid := p_session_id;
  v_revision uuid;
  v_revision_number integer;
  v_previous jsonb;
  v_previous_prompt text;
  v_title text;
  v_overall integer;
  v_evidence integer := 0;
  v_row_count integer := 0;
  v_day date := (now() at time zone 'Asia/Manila')::date;
  v_topic text;
  v_before_pct integer;
  v_after_pct integer;
begin
  if v_user is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  if p_prompt_text is null or char_length(trim(p_prompt_text)) not between 10 and 1500 then
    raise exception 'Prompt must contain 10 to 1500 characters.' using errcode = '22023';
  end if;
  if p_mode not in ('standard', 'ai') then
    raise exception 'Unknown Prompt Coach mode.' using errcode = '22023';
  end if;
  if p_rubric is null or jsonb_typeof(p_rubric) <> 'object' then
    raise exception 'Prompt rubric is required.' using errcode = '22023';
  end if;
  if p_focus_topic is not null and p_focus_topic not in (
    'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification'
  ) then
    raise exception 'Unknown Prompt Coach focus topic.' using errcode = '22023';
  end if;

  v_title := left(regexp_replace(trim(p_prompt_text), '\s+', ' ', 'g'), 90);
  v_overall := greatest(
    0,
    least(100, round(coalesce((p_rubric ->> 'overall')::numeric, 0) * 100)::integer)
  );

  if v_session is null then
    insert into public.prompt_coach_sessions (user_id, title, focus_topic)
    values (v_user, v_title, p_focus_topic)
    returning id into v_session;
  else
    perform pg_advisory_xact_lock(
      hashtextextended(v_user::text || '|prompt_coach_session|' || v_session::text, 0)
    );
    if not exists (
      select 1 from public.prompt_coach_sessions
      where id = v_session and user_id = v_user
    ) then
      raise exception 'Prompt Coach session was not found.' using errcode = '42501';
    end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user::text || '|prompt_coach_session|' || v_session::text, 0)
  );

  select rubric, prompt_text into v_previous, v_previous_prompt
  from public.prompt_coach_revisions
  where session_id = v_session and user_id = v_user
  order by revision_number desc
  limit 1;

  select coalesce(max(revision_number), 0) + 1 into v_revision_number
  from public.prompt_coach_revisions
  where session_id = v_session and user_id = v_user;

  insert into public.prompt_coach_revisions (
    session_id, user_id, revision_number, prompt_text, mode, overall_score,
    rubric, privacy_flags, standard_feedback, ai_guidance
  ) values (
    v_session, v_user, v_revision_number, trim(p_prompt_text), p_mode, v_overall,
    p_rubric, coalesce(p_privacy_flags, '[]'::jsonb),
    coalesce(p_standard_feedback, '{}'::jsonb), p_ai_guidance
  ) returning id into v_revision;

  update public.prompt_coach_sessions
  set
    title = case when v_revision_number = 1 then v_title else title end,
    focus_topic = coalesce(focus_topic, p_focus_topic),
    updated_at = now()
  where id = v_session and user_id = v_user;

  if v_previous is not null then
    foreach v_topic in array array[
      'prompt_clarity', 'context', 'specificity', 'responsible_use'
    ] loop
      v_before_pct := public.prompt_coach_server_topic_score(v_previous_prompt, v_topic);
      v_after_pct := public.prompt_coach_server_topic_score(p_prompt_text, v_topic);

      if v_after_pct >= 70 and (v_after_pct - v_before_pct) >= 10 then
        insert into public.prompt_coach_mastery_evidence (
          user_id, session_id, revision_id, topic_id, is_correct,
          counted_for_mastery, score_before, score_after, evidence_day
        ) values (
          v_user, v_session, v_revision, v_topic, true,
          true, v_before_pct, v_after_pct, v_day
        ) on conflict do nothing;
        get diagnostics v_row_count = row_count;
        v_evidence := v_evidence + v_row_count;
      end if;
    end loop;
  end if;

  if v_evidence > 0 then
    perform public.rebuild_adaptive_mastery_for_user(v_user);
  end if;

  return jsonb_build_object(
    'session_id', v_session,
    'revision_id', v_revision,
    'revision_number', v_revision_number,
    'mastery_evidence_count', v_evidence
  );
end;
$$;


ALTER FUNCTION "public"."record_prompt_coach_revision"("p_session_id" "uuid", "p_prompt_text" "text", "p_mode" "text", "p_rubric" "jsonb", "p_privacy_flags" "jsonb", "p_standard_feedback" "jsonb", "p_ai_guidance" "jsonb", "p_focus_topic" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_learner_topic_progression"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_topic text;
  v_mastery integer;
  v_total_objectives integer;
  v_correct_objectives integer;
  v_coverage integer;
  v_highest integer;
  v_retention integer;
  v_rank integer;
  v_progress integer;
  v_tier integer;
  v_old_rank integer;
  v_target_mastery integer;
  v_target_difficulty integer;
  v_target_coverage integer;
  v_target_retention integer;
  v_component_mastery numeric;
  v_component_difficulty numeric;
  v_component_coverage numeric;
  v_component_retention numeric;
begin
  foreach v_topic in array array[
    'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification'
  ] loop
    select coalesce(tm.mastery, 0)
      into v_mastery
    from public.topic_mastery tm
    where tm.user_id = p_user_id and tm.topic_id = v_topic;
    v_mastery := coalesce(v_mastery, 0);

    select count(*)
      into v_total_objectives
    from public.learning_objectives lo
    where lo.topic_id = v_topic and lo.status = 'published';

    select count(distinct qb.objective_id)
      into v_correct_objectives
    from public.question_attempts qa
    join public.question_bank qb on qb.id::text = qa.item_id
    where qa.user_id = p_user_id
      and qa.topic_id = v_topic
      and qa.attempt_type = 'question_bank'
      and qa.counted_for_mastery = true
      and qa.is_correct = true
      and qb.objective_id is not null;

    v_coverage := case
      when v_total_objectives = 0 then 0
      else round((v_correct_objectives::numeric / v_total_objectives::numeric) * 100)::integer
    end;

    select coalesce(max(x.difficulty), 0)
      into v_highest
    from (
      select qb.difficulty
      from public.question_attempts qa
      join public.question_bank qb on qb.id::text = qa.item_id
      where qa.user_id = p_user_id
        and qa.topic_id = v_topic
        and qa.attempt_type = 'question_bank'
        and qa.counted_for_mastery = true
      group by qb.difficulty
      having count(*) >= 2
         and avg(case when qa.is_correct then 1.0 else 0.0 end) >= 0.70
    ) x;

    select count(*)
      into v_retention
    from (
      select qa.item_id
      from public.question_attempts qa
      where qa.user_id = p_user_id
        and qa.topic_id = v_topic
        and qa.attempt_type = 'question_bank'
        and qa.counted_for_mastery = true
        and qa.is_correct = true
      group by qa.item_id
      having count(distinct (qa.attempted_at at time zone 'Asia/Manila')::date) >= 2
    ) retained;

    v_rank := case
      when v_mastery >= 90 and v_highest >= 5 and v_coverage >= 85 and v_retention >= 3 then 5
      when v_mastery >= 80 and v_highest >= 4 and v_coverage >= 70 and v_retention >= 2 then 4
      when v_mastery >= 65 and v_highest >= 3 and v_coverage >= 55 and v_retention >= 1 then 3
      when v_mastery >= 45 and v_highest >= 2 and v_coverage >= 35 then 2
      else 1
    end;

    if v_rank = 5 then
      v_progress := 100;
    else
      v_target_mastery := case v_rank
        when 1 then 45 when 2 then 65 when 3 then 80 else 90 end;
      v_target_difficulty := case v_rank
        when 1 then 2 when 2 then 3 when 3 then 4 else 5 end;
      v_target_coverage := case v_rank
        when 1 then 35 when 2 then 55 when 3 then 70 else 85 end;
      v_target_retention := case v_rank
        when 1 then 0 when 2 then 1 when 3 then 2 else 3 end;

      v_component_mastery := least(1.0, v_mastery::numeric / greatest(1, v_target_mastery));
      v_component_difficulty := least(1.0, v_highest::numeric / greatest(1, v_target_difficulty));
      v_component_coverage := least(1.0, v_coverage::numeric / greatest(1, v_target_coverage));
      v_component_retention := case
        when v_target_retention = 0 then 1.0
        else least(1.0, v_retention::numeric / v_target_retention)
      end;

      -- A gate-oriented progress score. The weakest requirement matters most,
      -- preventing easy-question grinding from hiding missing advanced evidence.
      v_progress := floor(
        least(
          v_component_mastery,
          v_component_difficulty,
          v_component_coverage,
          v_component_retention
        ) * 99
      )::integer;
    end if;

    v_tier := case when v_progress < 34 then 1 when v_progress < 67 then 2 else 3 end;

    select rank_level into v_old_rank
    from public.learner_topic_progression
    where user_id = p_user_id and topic_id = v_topic;

    insert into public.learner_topic_progression (
      user_id, topic_id, rank_level, rank_tier, rank_progress,
      highest_difficulty_passed, objective_coverage, retention_passes,
      promoted_at, updated_at
    ) values (
      p_user_id, v_topic, v_rank, v_tier, v_progress,
      v_highest, v_coverage, v_retention,
      case when coalesce(v_old_rank, 0) < v_rank then now() else null end,
      now()
    )
    on conflict (user_id, topic_id) do update set
      rank_level = excluded.rank_level,
      rank_tier = excluded.rank_tier,
      rank_progress = excluded.rank_progress,
      highest_difficulty_passed = excluded.highest_difficulty_passed,
      objective_coverage = excluded.objective_coverage,
      retention_passes = excluded.retention_passes,
      promoted_at = case
        when public.learner_topic_progression.rank_level < excluded.rank_level
          then now()
        else public.learner_topic_progression.promoted_at
      end,
      updated_at = now();
  end loop;
end;
$$;


ALTER FUNCTION "public"."refresh_learner_topic_progression"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_my_learning_progression"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  perform public.refresh_learner_topic_progression(auth.uid());
end;
$$;


ALTER FUNCTION "public"."refresh_my_learning_progression"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refund_prompt_coach_ai_use"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user uuid := auth.uid();
  v_day date := (now() at time zone 'Asia/Manila')::date;
begin
  if v_user is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user::text || '|prompt_coach_ai|' || v_day::text, 0)
  );

  update public.prompt_coach_daily_usage
  set ai_uses = greatest(0, ai_uses - 1), updated_at = now()
  where user_id = v_user and usage_date = v_day;

  return public.prompt_coach_ai_usage_status();
end;
$$;


ALTER FUNCTION "public"."refund_prompt_coach_ai_use"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reject_generated_content_draft"("p_draft_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if not public.is_promptwise_admin() then
    raise exception 'Administrator access required.' using errcode = '42501';
  end if;
  update public.generated_content_drafts
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_draft_id and status = 'draft';
end;
$$;


ALTER FUNCTION "public"."reject_generated_content_draft"("p_draft_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reject_verification_case_draft"("p_draft_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if not public.phase9_is_admin() then raise exception 'Administrator access required.' using errcode='42501'; end if;
  update public.verification_case_drafts
  set status='rejected', reviewed_at=now(), updated_at=now()
  where id=p_draft_id and status='draft';
end;
$$;


ALTER FUNCTION "public"."reject_verification_case_draft"("p_draft_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reserve_prompt_coach_ai_use"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user uuid := auth.uid();
  v_day date := (now() at time zone 'Asia/Manila')::date;
  v_used integer := 0;
begin
  if v_user is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user::text || '|prompt_coach_ai|' || v_day::text, 0)
  );

  select coalesce(ai_uses, 0) into v_used
  from public.prompt_coach_daily_usage
  where user_id = v_user and usage_date = v_day;
  v_used := coalesce(v_used, 0);

  if v_used >= 3 then
    raise exception 'AI Coach daily limit reached.' using errcode = 'P0001';
  end if;

  insert into public.prompt_coach_daily_usage (user_id, usage_date, ai_uses, updated_at)
  values (v_user, v_day, 1, now())
  on conflict (user_id, usage_date) do update set
    ai_uses = public.prompt_coach_daily_usage.ai_uses + 1,
    updated_at = now();

  return public.prompt_coach_ai_usage_status();
end;
$$;


ALTER FUNCTION "public"."reserve_prompt_coach_ai_use"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retag_adaptive_item_history"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user record;
begin
  if new.adaptive_topic is null
     or new.adaptive_topic is not distinct from old.adaptive_topic then
    return new;
  end if;

  update public.question_attempts
  set topic_id = new.adaptive_topic
  where item_id = new.id
    and topic_id is distinct from new.adaptive_topic;

  -- If an old bad tag caused multiple counted events on the same day, retain
  -- one mastery event and keep the rest as non-counting history.
  with ranked as (
    select id,
      row_number() over (
        partition by user_id, item_id, topic_id,
                     (attempted_at at time zone 'Asia/Manila')::date
        order by attempted_at, id
      ) rn
    from public.question_attempts
    where item_id = new.id and counted_for_mastery = true
  )
  update public.question_attempts qa
  set counted_for_mastery = false
  from ranked r
  where qa.id = r.id and r.rn > 1;

  for v_user in
    select distinct user_id from public.question_attempts where item_id = new.id
  loop
    perform public.rebuild_adaptive_mastery_for_user(v_user.user_id);
  end loop;
  return new;
end;
$$;


ALTER FUNCTION "public"."retag_adaptive_item_history"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."review_question_bank_item"("p_question_id" "uuid", "p_stem" "text", "p_options" "jsonb", "p_correct_index" integer, "p_explanation" "text", "p_difficulty" integer, "p_question_type" "text", "p_action" "text" DEFAULT 'verify'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_source_status text;
  v_distinct_options integer;
begin
  if not public.is_promptwise_admin() then
    raise exception 'Administrator access required.' using errcode = '42501';
  end if;

  if p_action not in ('verify', 'reject') then
    raise exception 'Unknown question-review action.' using errcode = '22023';
  end if;

  if not exists (select 1 from public.question_bank where id = p_question_id) then
    raise exception 'Question-bank item not found.' using errcode = '22023';
  end if;

  if p_action = 'reject' then
    update public.question_bank
    set validation_status = 'rejected',
        status = 'archived',
        updated_at = now()
    where id = p_question_id;
    return;
  end if;

  if length(trim(coalesce(p_stem, ''))) < 12 then
    raise exception 'Question stem is too short.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_options) <> 'array' or jsonb_array_length(p_options) <> 4 then
    raise exception 'Exactly four answer options are required.' using errcode = '22023';
  end if;
  select count(distinct lower(trim(value)))::integer
    into v_distinct_options
  from jsonb_array_elements_text(p_options);
  if v_distinct_options <> 4 or exists (
    select 1 from jsonb_array_elements_text(p_options)
    where length(trim(value)) = 0
  ) then
    raise exception 'Answer options must be four distinct non-empty choices.' using errcode = '22023';
  end if;
  if p_correct_index not between 0 and 3 then
    raise exception 'Correct answer must point to one of the four options.' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_explanation, ''))) < 20 then
    raise exception 'A meaningful answer explanation is required.' using errcode = '22023';
  end if;
  if p_difficulty not between 1 and 5 then
    raise exception 'Difficulty must be from 1 to 5.' using errcode = '22023';
  end if;
  if p_question_type not in ('concept', 'scenario', 'best_response', 'evaluation') then
    raise exception 'Unsupported question type.' using errcode = '22023';
  end if;

  select ci.status
    into v_source_status
  from public.question_bank qb
  left join public.content_items ci on ci.id = qb.source_content_id
  where qb.id = p_question_id;

  update public.question_bank
  set stem = trim(p_stem),
      options = p_options,
      correct_index = p_correct_index,
      explanation = trim(p_explanation),
      difficulty = p_difficulty,
      question_type = p_question_type,
      validation_status = 'verified',
      quality_score = 1.000,
      status = case when v_source_status = 'published' then 'published' else 'draft' end,
      updated_at = now()
  where id = p_question_id;
end;
$$;


ALTER FUNCTION "public"."review_question_bank_item"("p_question_id" "uuid", "p_stem" "text", "p_options" "jsonb", "p_correct_index" integer, "p_explanation" "text", "p_difficulty" integer, "p_question_type" "text", "p_action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_verification_case_attempt"("p_session_id" "uuid", "p_case_id" "uuid", "p_selected_evidence" "text"[], "p_selected_actions" "text"[], "p_selected_source_index" integer, "p_decision" "text", "p_confidence" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user uuid := auth.uid();
  v_case public.verification_cases%rowtype;
  v_key_evidence text[];
  v_valid_evidence text[];
  v_useful_actions text[];
  v_valid_actions text[];
  v_correct_evidence integer := 0;
  v_wrong_evidence integer := 0;
  v_correct_actions integer := 0;
  v_wrong_actions integer := 0;
  v_evidence_score integer := 0;
  v_method_score integer := 0;
  v_decision_score integer := 0;
  v_source_score integer := 0;
  v_confidence_score integer := 0;
  v_total integer := 0;
  v_hist_score integer := 0;
  v_decision_correct boolean := false;
  v_last_counted timestamptz;
  v_due timestamptz;
  v_should_count boolean := false;
  v_mastery integer := 0;
  v_attempts integer := 0;
  v_success integer := 0;
  v_next_review timestamptz;
  v_days integer;
  v_existing jsonb;
begin
  if v_user is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  if p_decision not in ('supported','ai_generated','manipulated','misleading_context','unsupported_claim','unverified','insufficient_evidence') then
    raise exception 'Unknown verification decision.' using errcode = '22023';
  end if;
  if p_confidence not in ('low','medium','high') then
    raise exception 'Unknown confidence level.' using errcode = '22023';
  end if;
  if p_selected_source_index < 0 or p_selected_source_index > 3 then
    raise exception 'Source selection is invalid.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.verification_sessions s
    join public.verification_session_cases sc on sc.session_id = s.id
    where s.id = p_session_id and s.user_id = v_user and s.status = 'active'
      and sc.case_id = p_case_id
  ) then
    raise exception 'Verification case is not part of this active learner session.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'case_id', a.case_id,
    'subskill', a.subskill,
    'evidence_score', a.evidence_score,
    'method_score', a.method_score,
    'decision_score', a.decision_score,
    'source_score', a.source_score,
    'confidence_score', a.confidence_score,
    'total_score', a.total_score,
    'decision_correct', a.decision_correct,
    'counted_for_mastery', a.counted_for_mastery,
    'correct_decision', c.correct_decision,
    'explanation', c.explanation,
    'learning_point', c.learning_point,
    'subskill_mastery_after', m.mastery
  ) into v_existing
  from public.verification_case_attempts a
  join public.verification_cases c on c.id = a.case_id
  left join public.verification_subskill_mastery m
    on m.user_id = a.user_id and m.subskill = a.subskill
  where a.session_id = p_session_id and a.case_id = p_case_id;
  if v_existing is not null then return v_existing; end if;

  select * into v_case from public.verification_cases where id = p_case_id;
  if v_case.id is null or v_case.status <> 'published' then
    raise exception 'Verification case is unavailable.' using errcode = 'P0001';
  end if;

  select coalesce(array_agg(x->>'code'), '{}') into v_key_evidence
  from jsonb_array_elements(v_case.evidence) x
  where coalesce((x->>'is_key')::boolean, false) = true;
  select coalesce(array_agg(x->>'code'), '{}') into v_valid_evidence
  from jsonb_array_elements(v_case.evidence) x;
  select coalesce(array_agg(x->>'code'), '{}') into v_useful_actions
  from jsonb_array_elements(v_case.actions) x
  where coalesce((x->>'useful')::boolean, false) = true;
  select coalesce(array_agg(x->>'code'), '{}') into v_valid_actions
  from jsonb_array_elements(v_case.actions) x;

  select count(distinct x) into v_correct_evidence
  from unnest(coalesce(p_selected_evidence, '{}')) x
  where x = any(v_key_evidence);
  select count(distinct x) into v_wrong_evidence
  from unnest(coalesce(p_selected_evidence, '{}')) x
  where x = any(v_valid_evidence) and not (x = any(v_key_evidence));
  select count(distinct x) into v_correct_actions
  from unnest(coalesce(p_selected_actions, '{}')) x
  where x = any(v_useful_actions);
  select count(distinct x) into v_wrong_actions
  from unnest(coalesce(p_selected_actions, '{}')) x
  where x = any(v_valid_actions) and not (x = any(v_useful_actions));

  v_evidence_score := greatest(0, least(30,
    round(30.0 * v_correct_evidence / greatest(1, cardinality(v_key_evidence)))::integer
    - v_wrong_evidence * 6
  ));
  v_method_score := greatest(0, least(25,
    round(25.0 * v_correct_actions / greatest(1, cardinality(v_useful_actions)))::integer
    - v_wrong_actions * 5
  ));
  v_decision_correct := p_decision = v_case.correct_decision;
  v_decision_score := case when v_decision_correct then 25 else 0 end;
  v_source_score := case when p_selected_source_index = v_case.best_source_index then 10 else 0 end;
  v_confidence_score := case
    when v_decision_correct and p_confidence = v_case.expected_confidence then 10
    when v_decision_correct then 7
    when not v_decision_correct and p_confidence = 'low' then 6
    when not v_decision_correct and p_confidence = 'medium' then 3
    else 0
  end;
  v_total := greatest(0, least(100,
    v_evidence_score + v_method_score + v_decision_score + v_source_score + v_confidence_score
  ));

  perform pg_advisory_xact_lock(hashtextextended(v_user::text || '|verification_case|' || p_case_id::text, 0));

  select max(attempted_at) into v_last_counted
  from public.verification_case_attempts
  where user_id = v_user and case_id = p_case_id and counted_for_mastery = true;

  if v_last_counted is null then
    v_should_count := true;
  else
    select next_review_at into v_due
    from public.verification_subskill_mastery
    where user_id = v_user and subskill = v_case.subskill;
    v_should_count := v_due is not null and now() >= v_due and v_last_counted < v_due;
  end if;

  insert into public.verification_case_attempts (
    user_id, session_id, case_id, subskill, selected_evidence, selected_actions,
    selected_source_index, decision, confidence, evidence_score, method_score,
    decision_score, source_score, confidence_score, total_score,
    decision_correct, counted_for_mastery
  ) values (
    v_user, p_session_id, p_case_id, v_case.subskill,
    coalesce(p_selected_evidence, '{}'), coalesce(p_selected_actions, '{}'),
    p_selected_source_index, p_decision, p_confidence, v_evidence_score,
    v_method_score, v_decision_score, v_source_score, v_confidence_score,
    v_total, v_decision_correct, v_should_count
  );

  insert into public.verification_case_exposure (user_id, case_id, times_seen, last_seen_at, last_score)
  values (v_user, p_case_id, 1, now(), v_total)
  on conflict (user_id, case_id) do update set
    times_seen = public.verification_case_exposure.times_seen + 1,
    last_seen_at = now(),
    last_score = excluded.last_score;

  if v_should_count then
    -- Recalculate this verification subskill from canonical counted attempts.
    v_mastery := 0; v_attempts := 0; v_success := 0;
    for v_hist_score in
      select total_score from public.verification_case_attempts
      where user_id = v_user and subskill = v_case.subskill and counted_for_mastery = true
      order by attempted_at
    loop
      if v_attempts = 0 then
        v_mastery := v_hist_score;
      else
        v_mastery := round(v_mastery * 0.75 + v_hist_score * 0.25)::integer;
      end if;
      v_attempts := v_attempts + 1;
      if v_hist_score >= 70 then v_success := v_success + 1; end if;
    end loop;
    v_days := case
      when v_mastery < 40 then 1
      when v_mastery < 60 then 2
      when v_mastery < 80 then 4
      else 7
    end;
    v_next_review := now() + make_interval(days => v_days);

    insert into public.verification_subskill_mastery (
      user_id, subskill, mastery, attempts, successful_attempts,
      last_practiced_at, next_review_at, updated_at
    ) values (
      v_user, v_case.subskill, v_mastery, v_attempts, v_success,
      now(), v_next_review, now()
    ) on conflict (user_id, subskill) do update set
      mastery = excluded.mastery,
      attempts = excluded.attempts,
      successful_attempts = excluded.successful_attempts,
      last_practiced_at = excluded.last_practiced_at,
      next_review_at = excluded.next_review_at,
      updated_at = now();

    -- Roll the case into the existing Phase 6 Verification topic without exposing
    -- Phase 9 subskills to the older mastery schema.
    insert into public.question_attempts (
      user_id, item_id, topic_id, is_correct, attempt_type,
      counted_for_mastery, attempted_at, attempt_day
    ) values (
      v_user, 'verification_case:' || p_case_id::text, 'verification',
      v_total >= 70, 'verification_activity', true, now(),
      (now() at time zone 'Asia/Manila')::date
    );
    perform public.rebuild_adaptive_mastery_for_user(v_user);
  else
    select mastery into v_mastery
    from public.verification_subskill_mastery
    where user_id = v_user and subskill = v_case.subskill;
  end if;

  return jsonb_build_object(
    'case_id', p_case_id,
    'subskill', v_case.subskill,
    'evidence_score', v_evidence_score,
    'method_score', v_method_score,
    'decision_score', v_decision_score,
    'source_score', v_source_score,
    'confidence_score', v_confidence_score,
    'total_score', (select total_score from public.verification_case_attempts where session_id=p_session_id and case_id=p_case_id),
    'decision_correct', v_decision_correct,
    'counted_for_mastery', v_should_count,
    'correct_decision', v_case.correct_decision,
    'explanation', v_case.explanation,
    'learning_point', v_case.learning_point,
    'subskill_mastery_after', coalesce(v_mastery, 0)
  );
end;
$$;


ALTER FUNCTION "public"."submit_verification_case_attempt"("p_session_id" "uuid", "p_case_id" "uuid", "p_selected_evidence" "text"[], "p_selected_actions" "text"[], "p_selected_source_index" integer, "p_decision" "text", "p_confidence" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_verification_guess"("p_session_id" "uuid", "p_case_id" "uuid", "p_decision" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user uuid := auth.uid();
  v_case public.verification_cases%rowtype;
  v_decision_correct boolean := false;
  v_total integer := 0;
  v_last_counted timestamptz;
  v_due timestamptz;
  v_should_count boolean := false;
  v_mastery integer := 0;
  v_attempts integer := 0;
  v_success integer := 0;
  v_hist_score integer := 0;
  v_next_review timestamptz;
  v_days integer;
  v_existing jsonb;
begin
  if v_user is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  if p_decision not in ('supported','ai_generated','manipulated','misleading_context','unsupported_claim','unverified','insufficient_evidence') then
    raise exception 'Unknown verification decision.' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.verification_sessions s
    join public.verification_session_cases sc on sc.session_id = s.id
    where s.id = p_session_id
      and s.user_id = v_user
      and s.status = 'active'
      and sc.case_id = p_case_id
  ) then
    raise exception 'Verification case is not part of this active learner session.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'case_id', a.case_id,
    'subskill', a.subskill,
    'evidence_score', a.evidence_score,
    'method_score', a.method_score,
    'decision_score', a.decision_score,
    'source_score', a.source_score,
    'confidence_score', a.confidence_score,
    'total_score', a.total_score,
    'decision_correct', a.decision_correct,
    'counted_for_mastery', a.counted_for_mastery,
    'correct_decision', c.correct_decision,
    'explanation', c.explanation,
    'learning_point', c.learning_point,
    'subskill_mastery_after', m.mastery
  ) into v_existing
  from public.verification_case_attempts a
  join public.verification_cases c on c.id = a.case_id
  left join public.verification_subskill_mastery m
    on m.user_id = a.user_id and m.subskill = a.subskill
  where a.session_id = p_session_id and a.case_id = p_case_id;
  if v_existing is not null then return v_existing; end if;

  select * into v_case
  from public.verification_cases
  where id = p_case_id;

  if v_case.id is null or v_case.status <> 'published' then
    raise exception 'Verification case is unavailable.' using errcode = 'P0001';
  end if;

  v_decision_correct := p_decision = v_case.correct_decision;
  v_total := case when v_decision_correct then 100 else 0 end;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user::text || '|verification_case|' || p_case_id::text, 0)
  );

  select max(attempted_at) into v_last_counted
  from public.verification_case_attempts
  where user_id = v_user
    and case_id = p_case_id
    and counted_for_mastery = true;

  if v_last_counted is null then
    v_should_count := true;
  else
    select next_review_at into v_due
    from public.verification_subskill_mastery
    where user_id = v_user and subskill = v_case.subskill;
    v_should_count := v_due is not null and now() >= v_due and v_last_counted < v_due;
  end if;

  insert into public.verification_case_attempts (
    user_id, session_id, case_id, subskill,
    selected_evidence, selected_actions, selected_source_index,
    decision, confidence,
    evidence_score, method_score, decision_score, source_score, confidence_score,
    total_score, decision_correct, counted_for_mastery
  ) values (
    v_user, p_session_id, p_case_id, v_case.subskill,
    '{}', '{}', 0,
    p_decision, 'medium',
    0, 0, case when v_decision_correct then 25 else 0 end, 0, 0,
    v_total, v_decision_correct, v_should_count
  );

  insert into public.verification_case_exposure (
    user_id, case_id, times_seen, last_seen_at, last_score
  ) values (
    v_user, p_case_id, 1, now(), v_total
  )
  on conflict (user_id, case_id) do update set
    times_seen = public.verification_case_exposure.times_seen + 1,
    last_seen_at = now(),
    last_score = excluded.last_score;

  if v_should_count then
    v_mastery := 0;
    v_attempts := 0;
    v_success := 0;

    for v_hist_score in
      select total_score
      from public.verification_case_attempts
      where user_id = v_user
        and subskill = v_case.subskill
        and counted_for_mastery = true
      order by attempted_at
    loop
      if v_attempts = 0 then
        v_mastery := v_hist_score;
      else
        v_mastery := round(v_mastery * 0.75 + v_hist_score * 0.25)::integer;
      end if;
      v_attempts := v_attempts + 1;
      if v_hist_score >= 70 then
        v_success := v_success + 1;
      end if;
    end loop;

    v_days := case
      when v_mastery < 40 then 1
      when v_mastery < 60 then 2
      when v_mastery < 80 then 4
      else 7
    end;
    v_next_review := now() + make_interval(days => v_days);

    insert into public.verification_subskill_mastery (
      user_id, subskill, mastery, attempts, successful_attempts,
      last_practiced_at, next_review_at, updated_at
    ) values (
      v_user, v_case.subskill, v_mastery, v_attempts, v_success,
      now(), v_next_review, now()
    )
    on conflict (user_id, subskill) do update set
      mastery = excluded.mastery,
      attempts = excluded.attempts,
      successful_attempts = excluded.successful_attempts,
      last_practiced_at = excluded.last_practiced_at,
      next_review_at = excluded.next_review_at,
      updated_at = now();

    insert into public.question_attempts (
      user_id, item_id, topic_id, is_correct, attempt_type,
      counted_for_mastery, attempted_at, attempt_day
    ) values (
      v_user,
      'verification_case:' || p_case_id::text,
      'verification',
      v_decision_correct,
      'verification_activity',
      true,
      now(),
      (now() at time zone 'Asia/Manila')::date
    );

    perform public.rebuild_adaptive_mastery_for_user(v_user);
  else
    select mastery into v_mastery
    from public.verification_subskill_mastery
    where user_id = v_user and subskill = v_case.subskill;
  end if;

  return jsonb_build_object(
    'case_id', p_case_id,
    'subskill', v_case.subskill,
    'evidence_score', 0,
    'method_score', 0,
    'decision_score', case when v_decision_correct then 25 else 0 end,
    'source_score', 0,
    'confidence_score', 0,
    'total_score', v_total,
    'decision_correct', v_decision_correct,
    'counted_for_mastery', v_should_count,
    'correct_decision', v_case.correct_decision,
    'explanation', v_case.explanation,
    'learning_point', v_case.learning_point,
    'subskill_mastery_after', coalesce(v_mastery, 0)
  );
end;
$$;


ALTER FUNCTION "public"."submit_verification_guess"("p_session_id" "uuid", "p_case_id" "uuid", "p_decision" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_phase7_child_publish_status"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if new.status = 'published' and old.status is distinct from 'published' then
    update public.learning_objectives
    set status = 'published', updated_at = now()
    where content_item_id = new.id and status = 'draft';

    update public.question_bank
    set status = case when validation_status = 'verified' then 'published' else status end,
        updated_at = now()
    where source_content_id = new.id;
  elsif new.status = 'archived' and old.status is distinct from 'archived' then
    update public.learning_objectives
    set status = 'archived', updated_at = now()
    where content_item_id = new.id;
    update public.question_bank
    set status = 'archived', updated_at = now()
    where source_content_id = new.id;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."sync_phase7_child_publish_status"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text" DEFAULT ''::"text" NOT NULL,
    "full_name" "text" DEFAULT ''::"text" NOT NULL,
    "role" "public"."app_role" DEFAULT 'learner'::"public"."app_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "profiles_full_name_length" CHECK ((("char_length"("full_name") >= 0) AND ("char_length"("full_name") <= 80)))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_profile"("p_full_name" "text") RETURNS "public"."profiles"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  current_user_id uuid := (select auth.uid());
  normalized_name text := btrim(coalesce(p_full_name, ''));
  updated_profile public.profiles;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if char_length(normalized_name) < 2 or char_length(normalized_name) > 80 then
    raise exception 'Full name must contain 2 to 80 characters';
  end if;

  update public.profiles
  set full_name = normalized_name
  where id = current_user_id
  returning * into updated_profile;

  if updated_profile.id is null then
    raise exception 'Profile not found';
  end if;

  return updated_profile;
end;
$$;


ALTER FUNCTION "public"."update_my_profile"("p_full_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_verification_automation_settings"("p_enabled" boolean, "p_max_articles_per_run" integer, "p_max_drafts_per_run" integer, "p_max_drafts_per_day" integer, "p_monthly_draft_cap" integer, "p_monthly_groq_request_cap" integer, "p_max_pending_drafts" integer, "p_manual_cooldown_minutes" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if not public.phase9_is_admin() then
    raise exception 'Administrator access required.';
  end if;

  update public.verification_automation_settings
  set enabled = p_enabled,
      max_articles_per_run = greatest(1, least(20, p_max_articles_per_run)),
      max_drafts_per_run = greatest(1, least(10, p_max_drafts_per_run)),
      max_drafts_per_day = greatest(1, least(50, p_max_drafts_per_day)),
      monthly_draft_cap = greatest(1, least(1000, p_monthly_draft_cap)),
      monthly_groq_request_cap = greatest(1, least(5000, p_monthly_groq_request_cap)),
      max_pending_drafts = greatest(5, least(200, p_max_pending_drafts)),
      manual_cooldown_minutes = greatest(1, least(120, p_manual_cooldown_minutes)),
      updated_at = now()
  where id = 1;

  return (
    select to_jsonb(v)
    from public.verification_automation_settings v
    where v.id = 1
  );
end;
$$;


ALTER FUNCTION "public"."update_verification_automation_settings"("p_enabled" boolean, "p_max_articles_per_run" integer, "p_max_drafts_per_run" integer, "p_max_drafts_per_day" integer, "p_monthly_draft_cap" integer, "p_monthly_groq_request_cap" integer, "p_max_pending_drafts" integer, "p_manual_cooldown_minutes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_verification_case_core"("p_case_id" "uuid", "p_title" "text", "p_scenario" "text", "p_claim_text" "text", "p_subskill" "text", "p_case_type" "text", "p_difficulty" integer, "p_correct_decision" "text", "p_expected_confidence" "text", "p_explanation" "text", "p_learning_point" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if not public.phase9_is_admin() then
    raise exception 'Administrator access required.' using errcode='42501';
  end if;
  if nullif(trim(p_title),'') is null or nullif(trim(p_scenario),'') is null or
     nullif(trim(p_explanation),'') is null or nullif(trim(p_learning_point),'') is null then
    raise exception 'Verification case text fields cannot be empty.' using errcode='22023';
  end if;
  if p_subskill not in (
    'source_verification','claim_verification','media_provenance',
    'manipulation_detection','citation_verification','uncertainty_judgment'
  ) then raise exception 'Invalid verification subskill.' using errcode='22023'; end if;
  if p_case_type not in ('image','video','audio','claim','citation','scam') then
    raise exception 'Invalid verification case type.' using errcode='22023';
  end if;
  if p_correct_decision not in (
    'supported','ai_generated','manipulated','misleading_context',
    'unsupported_claim','unverified','insufficient_evidence'
  ) then raise exception 'Invalid verification decision.' using errcode='22023'; end if;
  if p_expected_confidence not in ('low','medium','high') then
    raise exception 'Invalid confidence.' using errcode='22023';
  end if;

  update public.verification_cases set
    title=trim(p_title), scenario=trim(p_scenario), claim_text=coalesce(trim(p_claim_text),''),
    subskill=p_subskill, case_type=p_case_type, difficulty=greatest(1,least(5,p_difficulty)),
    correct_decision=p_correct_decision, expected_confidence=p_expected_confidence,
    explanation=trim(p_explanation), learning_point=trim(p_learning_point), updated_at=now()
  where id=p_case_id;
end;
$$;


ALTER FUNCTION "public"."update_verification_case_core"("p_case_id" "uuid", "p_title" "text", "p_scenario" "text", "p_claim_text" "text", "p_subskill" "text", "p_case_type" "text", "p_difficulty" integer, "p_correct_decision" "text", "p_expected_confidence" "text", "p_explanation" "text", "p_learning_point" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."assessment_attempts" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "assessment_type" "text" DEFAULT 'diagnostic'::"text" NOT NULL,
    "score" integer NOT NULL,
    "correct_answers" integer DEFAULT 0 NOT NULL,
    "total_questions" integer DEFAULT 0 NOT NULL,
    "answers" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "completed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "assessment_attempts_score_check" CHECK ((("score" >= 0) AND ("score" <= 100)))
);


ALTER TABLE "public"."assessment_attempts" OWNER TO "postgres";


ALTER TABLE "public"."assessment_attempts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."assessment_attempts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."automation_runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "trigger_mode" "text" NOT NULL,
    "status" "text" DEFAULT 'running'::"text" NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "sources_checked" integer DEFAULT 0 NOT NULL,
    "articles_discovered" integer DEFAULT 0 NOT NULL,
    "drafts_created" integer DEFAULT 0 NOT NULL,
    "error_message" "text",
    "verification_drafts_created" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "automation_runs_status_check" CHECK (("status" = ANY (ARRAY['running'::"text", 'completed'::"text", 'failed'::"text", 'skipped'::"text"]))),
    CONSTRAINT "automation_runs_trigger_mode_check" CHECK (("trigger_mode" = ANY (ARRAY['scheduled'::"text", 'manual'::"text"])))
);


ALTER TABLE "public"."automation_runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."automation_settings" (
    "id" integer DEFAULT 1 NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "max_articles_per_run" integer DEFAULT 3 NOT NULL,
    "max_drafts_per_day" integer DEFAULT 3 NOT NULL,
    "monthly_draft_cap" integer DEFAULT 100 NOT NULL,
    "manual_cooldown_minutes" integer DEFAULT 30 NOT NULL,
    "last_manual_run_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "max_pending_drafts" integer DEFAULT 30 NOT NULL,
    "max_pending_questions" integer DEFAULT 100 NOT NULL,
    "draft_archive_days" integer DEFAULT 30 NOT NULL,
    "rejected_delete_days" integer DEFAULT 7 NOT NULL,
    "archived_delete_days" integer DEFAULT 90 NOT NULL,
    "article_cleanup_days" integer DEFAULT 60 NOT NULL,
    "run_log_retention_days" integer DEFAULT 30 NOT NULL,
    CONSTRAINT "automation_settings_archived_delete_days_check" CHECK ((("archived_delete_days" >= 30) AND ("archived_delete_days" <= 365))),
    CONSTRAINT "automation_settings_article_cleanup_days_check" CHECK ((("article_cleanup_days" >= 14) AND ("article_cleanup_days" <= 365))),
    CONSTRAINT "automation_settings_draft_archive_days_check" CHECK ((("draft_archive_days" >= 7) AND ("draft_archive_days" <= 180))),
    CONSTRAINT "automation_settings_id_check" CHECK (("id" = 1)),
    CONSTRAINT "automation_settings_manual_cooldown_minutes_check" CHECK ((("manual_cooldown_minutes" >= 1) AND ("manual_cooldown_minutes" <= 1440))),
    CONSTRAINT "automation_settings_max_articles_per_run_check" CHECK ((("max_articles_per_run" >= 1) AND ("max_articles_per_run" <= 10))),
    CONSTRAINT "automation_settings_max_drafts_per_day_check" CHECK ((("max_drafts_per_day" >= 1) AND ("max_drafts_per_day" <= 20))),
    CONSTRAINT "automation_settings_max_pending_drafts_check" CHECK ((("max_pending_drafts" >= 5) AND ("max_pending_drafts" <= 200))),
    CONSTRAINT "automation_settings_max_pending_questions_check" CHECK ((("max_pending_questions" >= 20) AND ("max_pending_questions" <= 1000))),
    CONSTRAINT "automation_settings_monthly_draft_cap_check" CHECK ((("monthly_draft_cap" >= 1) AND ("monthly_draft_cap" <= 1000))),
    CONSTRAINT "automation_settings_rejected_delete_days_check" CHECK ((("rejected_delete_days" >= 1) AND ("rejected_delete_days" <= 60))),
    CONSTRAINT "automation_settings_run_log_retention_days_check" CHECK ((("run_log_retention_days" >= 7) AND ("run_log_retention_days" <= 365)))
);


ALTER TABLE "public"."automation_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."awareness_articles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "summary" "text" DEFAULT ''::"text" NOT NULL,
    "why_it_matters" "text" DEFAULT ''::"text" NOT NULL,
    "source_name" "text" NOT NULL,
    "source_domain" "text" NOT NULL,
    "source_url" "text" NOT NULL,
    "image_url" "text",
    "published_at" timestamp with time zone,
    "discovered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "category" "text" DEFAULT 'online_safety'::"text" NOT NULL,
    "region" "text" DEFAULT 'Global'::"text" NOT NULL,
    "source_country" "text" DEFAULT ''::"text" NOT NULL,
    "trust_level" integer DEFAULT 70 NOT NULL,
    "relevance_score" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "content_excerpt" "text" DEFAULT ''::"text" NOT NULL,
    "content_fetch_status" "text" DEFAULT 'not_attempted'::"text" NOT NULL,
    "content_fetched_at" timestamp with time zone,
    "content_hash" "text",
    "ai_relevance_score" integer DEFAULT 0 NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "awareness_articles_ai_relevance_check" CHECK ((("ai_relevance_score" >= 0) AND ("ai_relevance_score" <= 20))),
    CONSTRAINT "awareness_articles_category_check" CHECK (("category" = ANY (ARRAY['scams'::"text", 'deepfakes'::"text", 'fake_news'::"text", 'privacy'::"text", 'online_safety'::"text", 'ai_misuse'::"text", 'fact_checking'::"text", 'cybersecurity'::"text"]))),
    CONSTRAINT "awareness_articles_content_fetch_status_check" CHECK (("content_fetch_status" = ANY (ARRAY['not_attempted'::"text", 'usable'::"text", 'insufficient'::"text", 'unavailable'::"text"]))),
    CONSTRAINT "awareness_articles_region_check" CHECK (("region" = ANY (ARRAY['Philippines'::"text", 'Global'::"text"]))),
    CONSTRAINT "awareness_articles_relevance_check" CHECK ((("relevance_score" >= 0) AND ("relevance_score" <= 100))),
    CONSTRAINT "awareness_articles_trust_check" CHECK ((("trust_level" >= 1) AND ("trust_level" <= 100)))
);


ALTER TABLE "public"."awareness_articles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."awareness_direct_sources" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "base_domain" "text" NOT NULL,
    "source_url" "text" NOT NULL,
    "source_type" "text" DEFAULT 'html_listing'::"text" NOT NULL,
    "region" "text" DEFAULT 'Global'::"text" NOT NULL,
    "trust_level" integer DEFAULT 80 NOT NULL,
    "priority" integer DEFAULT 50 NOT NULL,
    "relevance_keywords" "text"[] DEFAULT ARRAY[]::"text"[] NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "last_checked_at" timestamp with time zone,
    "last_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "awareness_direct_sources_priority_check" CHECK ((("priority" >= 1) AND ("priority" <= 100))),
    CONSTRAINT "awareness_direct_sources_region_check" CHECK (("region" = ANY (ARRAY['Philippines'::"text", 'Global'::"text"]))),
    CONSTRAINT "awareness_direct_sources_trust_check" CHECK ((("trust_level" >= 1) AND ("trust_level" <= 100))),
    CONSTRAINT "awareness_direct_sources_type_check" CHECK (("source_type" = ANY (ARRAY['html_listing'::"text", 'rss'::"text"])))
);


ALTER TABLE "public"."awareness_direct_sources" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."awareness_feed_settings" (
    "id" integer DEFAULT 1 NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "refresh_minutes" integer DEFAULT 120 NOT NULL,
    "max_articles_per_refresh" integer DEFAULT 24 NOT NULL,
    "max_active_articles" integer DEFAULT 200 NOT NULL,
    "archive_after_days" integer DEFAULT 45 NOT NULL,
    "last_refresh_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_attempt_at" timestamp with time zone,
    "last_success_at" timestamp with time zone,
    "last_success_count" integer DEFAULT 0 NOT NULL,
    "last_error" "text",
    "direct_source_limit" integer DEFAULT 6 NOT NULL,
    "min_direct_candidates_before_fallback" integer DEFAULT 8 NOT NULL,
    "min_ph_direct_candidates_before_fallback" integer DEFAULT 3 NOT NULL,
    "article_snapshot_hours" integer DEFAULT 24 NOT NULL,
    "min_active_ai_articles" integer DEFAULT 12 NOT NULL,
    "manual_check_cooldown_minutes" integer DEFAULT 10 NOT NULL,
    CONSTRAINT "awareness_feed_settings_active_check" CHECK ((("max_active_articles" >= 50) AND ("max_active_articles" <= 500))),
    CONSTRAINT "awareness_feed_settings_archive_check" CHECK ((("archive_after_days" >= 14) AND ("archive_after_days" <= 180))),
    CONSTRAINT "awareness_feed_settings_manual_check_cooldown_check" CHECK ((("manual_check_cooldown_minutes" >= 1) AND ("manual_check_cooldown_minutes" <= 60))),
    CONSTRAINT "awareness_feed_settings_min_ai_check" CHECK ((("min_active_ai_articles" >= 4) AND ("min_active_ai_articles" <= 50))),
    CONSTRAINT "awareness_feed_settings_per_refresh_check" CHECK ((("max_articles_per_refresh" >= 8) AND ("max_articles_per_refresh" <= 40))),
    CONSTRAINT "awareness_feed_settings_refresh_check" CHECK ((("refresh_minutes" >= 30) AND ("refresh_minutes" <= 1440))),
    CONSTRAINT "awareness_feed_settings_singleton" CHECK (("id" = 1))
);


ALTER TABLE "public"."awareness_feed_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."awareness_refresh_runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "status" "text" DEFAULT 'running'::"text" NOT NULL,
    "articles_discovered" integer DEFAULT 0 NOT NULL,
    "articles_saved" integer DEFAULT 0 NOT NULL,
    "error_message" "text",
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "trusted_matched" integer DEFAULT 0 NOT NULL,
    "articles_usable" integer DEFAULT 0 NOT NULL,
    "active_articles" integer DEFAULT 0 NOT NULL,
    "provider_warnings" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    CONSTRAINT "awareness_refresh_runs_status_check" CHECK (("status" = ANY (ARRAY['running'::"text", 'completed'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."awareness_refresh_runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."awareness_source_domains" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "domain" "text" NOT NULL,
    "name" "text" NOT NULL,
    "region" "text" DEFAULT 'Global'::"text" NOT NULL,
    "trust_level" integer DEFAULT 80 NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "awareness_source_domains_region_check" CHECK (("region" = ANY (ARRAY['Philippines'::"text", 'Global'::"text"]))),
    CONSTRAINT "awareness_source_domains_trust_check" CHECK ((("trust_level" >= 1) AND ("trust_level" <= 100)))
);


ALTER TABLE "public"."awareness_source_domains" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."awareness_user_actions" (
    "user_id" "uuid" NOT NULL,
    "article_id" "uuid" NOT NULL,
    "read_at" timestamp with time zone,
    "saved_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."awareness_user_actions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."content_item_versions" (
    "id" bigint NOT NULL,
    "content_id" "text" NOT NULL,
    "content_type" "public"."content_type" NOT NULL,
    "version" integer NOT NULL,
    "operation" "text" NOT NULL,
    "snapshot" "jsonb" NOT NULL,
    "changed_by" "uuid",
    "changed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "content_item_versions_operation" CHECK (("operation" = ANY (ARRAY['UPDATE'::"text", 'DELETE'::"text"])))
);


ALTER TABLE "public"."content_item_versions" OWNER TO "postgres";


ALTER TABLE "public"."content_item_versions" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."content_item_versions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."content_items" (
    "id" "text" NOT NULL,
    "content_type" "public"."content_type" NOT NULL,
    "parent_id" "text",
    "title" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "body" "text" DEFAULT ''::"text" NOT NULL,
    "icon" "text" DEFAULT ''::"text" NOT NULL,
    "estimated_minutes" integer DEFAULT 0 NOT NULL,
    "quiz_id" "text",
    "question" "text" DEFAULT ''::"text" NOT NULL,
    "options" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "correct_index" integer,
    "explanation" "text" DEFAULT ''::"text" NOT NULL,
    "image_path_a" "text" DEFAULT ''::"text" NOT NULL,
    "image_path_b" "text" DEFAULT ''::"text" NOT NULL,
    "is_a_ai" boolean,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "status" "public"."content_status" DEFAULT 'draft'::"public"."content_status" NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    "source_url" "text",
    "publication_date" "date",
    "review_date" "date",
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "adaptive_topic" "text",
    "learning_level" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "content_items_activity_fields" CHECK ((("content_type" <> 'activity'::"public"."content_type") OR (("char_length"("btrim"("image_path_a")) >= 2) AND ("char_length"("btrim"("image_path_b")) >= 2) AND ("is_a_ai" IS NOT NULL) AND ("char_length"("btrim"("explanation")) >= 2)))),
    CONSTRAINT "content_items_adaptive_topic_check" CHECK ((("adaptive_topic" IS NULL) OR ("adaptive_topic" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"])))),
    CONSTRAINT "content_items_awareness_fields" CHECK ((("content_type" <> 'awareness'::"public"."content_type") OR ("char_length"("btrim"("description")) >= 2))),
    CONSTRAINT "content_items_estimated_minutes" CHECK ((("estimated_minutes" >= 0) AND ("estimated_minutes" <= 600))),
    CONSTRAINT "content_items_id_format" CHECK ((("id" ~ '^[a-z0-9_-]+$'::"text") AND (("char_length"("id") >= 2) AND ("char_length"("id") <= 120)))),
    CONSTRAINT "content_items_learning_level_check" CHECK ((("learning_level" >= 1) AND ("learning_level" <= 5))),
    CONSTRAINT "content_items_lesson_fields" CHECK ((("content_type" <> 'lesson'::"public"."content_type") OR (("parent_id" IS NOT NULL) AND ("char_length"("btrim"("body")) >= 2) AND ("estimated_minutes" >= 1)))),
    CONSTRAINT "content_items_module_fields" CHECK ((("content_type" <> 'module'::"public"."content_type") OR ("char_length"("btrim"("description")) >= 2))),
    CONSTRAINT "content_items_options_array" CHECK (("jsonb_typeof"("options") = 'array'::"text")),
    CONSTRAINT "content_items_quiz_fields" CHECK ((("content_type" <> 'quiz'::"public"."content_type") OR (("char_length"("btrim"("question")) >= 2) AND ("jsonb_array_length"("options") >= 2) AND ("correct_index" IS NOT NULL) AND ("correct_index" >= 0) AND ("correct_index" < "jsonb_array_length"("options")) AND ("char_length"("btrim"("explanation")) >= 2)))),
    CONSTRAINT "content_items_review_after_publication" CHECK ((("publication_date" IS NULL) OR ("review_date" IS NULL) OR ("review_date" >= "publication_date"))),
    CONSTRAINT "content_items_title_length" CHECK ((("char_length"("btrim"("title")) >= 2) AND ("char_length"("btrim"("title")) <= 180))),
    CONSTRAINT "content_items_version_positive" CHECK (("version" >= 1))
);

ALTER TABLE ONLY "public"."content_items" REPLICA IDENTITY FULL;


ALTER TABLE "public"."content_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."content_sources" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "source_url" "text" NOT NULL,
    "feed_url" "text",
    "source_type" "text" DEFAULT 'page'::"text" NOT NULL,
    "trust_level" integer DEFAULT 3 NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "relevance_keywords" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "last_checked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "content_sources_source_type_check" CHECK (("source_type" = ANY (ARRAY['rss'::"text", 'page'::"text"]))),
    CONSTRAINT "content_sources_trust_level_check" CHECK ((("trust_level" >= 1) AND ("trust_level" <= 5)))
);


ALTER TABLE "public"."content_sources" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."discovered_articles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "source_id" "uuid" NOT NULL,
    "article_url" "text" NOT NULL,
    "title" "text" NOT NULL,
    "summary" "text" DEFAULT ''::"text" NOT NULL,
    "published_at" timestamp with time zone,
    "fingerprint" "text" NOT NULL,
    "relevance_score" numeric(5,2) DEFAULT 0 NOT NULL,
    "topic_hint" "text",
    "status" "text" DEFAULT 'new'::"text" NOT NULL,
    "discovered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone,
    CONSTRAINT "discovered_articles_status_check" CHECK (("status" = ANY (ARRAY['new'::"text", 'processed'::"text", 'ignored'::"text", 'failed'::"text"]))),
    CONSTRAINT "discovered_articles_topic_hint_check" CHECK ((("topic_hint" IS NULL) OR ("topic_hint" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"]))))
);


ALTER TABLE "public"."discovered_articles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."generated_content_drafts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "article_id" "uuid",
    "title" "text" NOT NULL,
    "summary" "text" DEFAULT ''::"text" NOT NULL,
    "topic_id" "text" NOT NULL,
    "target_level" integer DEFAULT 2 NOT NULL,
    "source_name" "text" NOT NULL,
    "source_url" "text" NOT NULL,
    "source_published_at" timestamp with time zone,
    "draft_payload" "jsonb" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "published_content_id" "text",
    "archived_at" timestamp with time zone,
    CONSTRAINT "generated_content_drafts_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'approved'::"text", 'rejected'::"text", 'published'::"text", 'archived'::"text"]))),
    CONSTRAINT "generated_content_drafts_target_level_check" CHECK ((("target_level" >= 1) AND ("target_level" <= 5))),
    CONSTRAINT "generated_content_drafts_topic_id_check" CHECK (("topic_id" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"])))
);


ALTER TABLE "public"."generated_content_drafts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."knowledge_check_session_questions" (
    "session_id" "uuid" NOT NULL,
    "question_id" "uuid" NOT NULL,
    "sequence" integer NOT NULL,
    "topic_id" "text" NOT NULL,
    "objective_id" "uuid",
    "difficulty" integer NOT NULL,
    "selected_index" integer,
    "is_correct" boolean,
    "counted_for_mastery" boolean,
    "answered_at" timestamp with time zone,
    CONSTRAINT "knowledge_check_session_questions_difficulty_check" CHECK ((("difficulty" >= 1) AND ("difficulty" <= 5)))
);


ALTER TABLE "public"."knowledge_check_session_questions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."knowledge_check_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "mode" "text" DEFAULT 'adaptive'::"text" NOT NULL,
    "focus_topic" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "question_count" integer NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "knowledge_check_sessions_focus_topic_check" CHECK ((("focus_topic" IS NULL) OR ("focus_topic" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"])))),
    CONSTRAINT "knowledge_check_sessions_mode_check" CHECK (("mode" = ANY (ARRAY['adaptive'::"text", 'review'::"text", 'focused'::"text"]))),
    CONSTRAINT "knowledge_check_sessions_question_count_check" CHECK ((("question_count" >= 1) AND ("question_count" <= 20))),
    CONSTRAINT "knowledge_check_sessions_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'completed'::"text", 'abandoned'::"text"])))
);


ALTER TABLE "public"."knowledge_check_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."learner_progress" (
    "user_id" "uuid" NOT NULL,
    "completed_lesson_ids" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "quiz_best_scores" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "badges" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "knowledge_level" "text" DEFAULT 'Beginner'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "learner_progress_level_check" CHECK (("knowledge_level" = ANY (ARRAY['Beginner'::"text", 'Intermediate'::"text", 'Advanced'::"text"]))),
    CONSTRAINT "learner_progress_scores_are_object" CHECK (("jsonb_typeof"("quiz_best_scores") = 'object'::"text"))
);


ALTER TABLE "public"."learner_progress" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."learner_topic_progression" (
    "user_id" "uuid" NOT NULL,
    "topic_id" "text" NOT NULL,
    "rank_level" integer DEFAULT 1 NOT NULL,
    "rank_tier" integer DEFAULT 1 NOT NULL,
    "rank_progress" integer DEFAULT 0 NOT NULL,
    "highest_difficulty_passed" integer DEFAULT 0 NOT NULL,
    "objective_coverage" integer DEFAULT 0 NOT NULL,
    "retention_passes" integer DEFAULT 0 NOT NULL,
    "promoted_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "learner_topic_progression_highest_difficulty_passed_check" CHECK ((("highest_difficulty_passed" >= 0) AND ("highest_difficulty_passed" <= 5))),
    CONSTRAINT "learner_topic_progression_objective_coverage_check" CHECK ((("objective_coverage" >= 0) AND ("objective_coverage" <= 100))),
    CONSTRAINT "learner_topic_progression_rank_level_check" CHECK ((("rank_level" >= 1) AND ("rank_level" <= 5))),
    CONSTRAINT "learner_topic_progression_rank_progress_check" CHECK ((("rank_progress" >= 0) AND ("rank_progress" <= 100))),
    CONSTRAINT "learner_topic_progression_rank_tier_check" CHECK ((("rank_tier" >= 1) AND ("rank_tier" <= 3))),
    CONSTRAINT "learner_topic_progression_topic_id_check" CHECK (("topic_id" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"])))
);


ALTER TABLE "public"."learner_topic_progression" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."learning_objectives" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "content_item_id" "text" NOT NULL,
    "topic_id" "text" NOT NULL,
    "objective_code" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "required_level" integer DEFAULT 1 NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'published'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "learning_objectives_required_level_check" CHECK ((("required_level" >= 1) AND ("required_level" <= 5))),
    CONSTRAINT "learning_objectives_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'published'::"text", 'archived'::"text"]))),
    CONSTRAINT "learning_objectives_topic_id_check" CHECK (("topic_id" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"])))
);


ALTER TABLE "public"."learning_objectives" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."question_bank" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "question_code" "text" NOT NULL,
    "source_content_id" "text",
    "objective_id" "uuid",
    "topic_id" "text" NOT NULL,
    "question_type" "text" DEFAULT 'concept'::"text" NOT NULL,
    "stem" "text" NOT NULL,
    "options" "jsonb" NOT NULL,
    "correct_index" integer NOT NULL,
    "explanation" "text" NOT NULL,
    "difficulty" integer NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "validation_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "quality_score" numeric(4,3) DEFAULT 0.000 NOT NULL,
    "source_url" "text",
    "source_published_at" timestamp with time zone,
    "generated_by" "text" DEFAULT 'manual'::"text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "question_bank_correct_index_check" CHECK ((("correct_index" >= 0) AND ("correct_index" <= 3))),
    CONSTRAINT "question_bank_difficulty_check" CHECK ((("difficulty" >= 1) AND ("difficulty" <= 5))),
    CONSTRAINT "question_bank_four_options_check" CHECK ((("jsonb_typeof"("options") = 'array'::"text") AND ("jsonb_array_length"("options") = 4))),
    CONSTRAINT "question_bank_quality_score_check" CHECK ((("quality_score" >= (0)::numeric) AND ("quality_score" <= (1)::numeric))),
    CONSTRAINT "question_bank_question_type_check" CHECK (("question_type" = ANY (ARRAY['concept'::"text", 'scenario'::"text", 'best_response'::"text", 'evaluation'::"text"]))),
    CONSTRAINT "question_bank_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'published'::"text", 'archived'::"text"]))),
    CONSTRAINT "question_bank_topic_id_check" CHECK (("topic_id" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"]))),
    CONSTRAINT "question_bank_validation_status_check" CHECK (("validation_status" = ANY (ARRAY['pending'::"text", 'verified'::"text", 'needs_review'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."question_bank" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."phase7_content_health" WITH ("security_invoker"='true') AS
 SELECT "t"."topic_id",
    (COALESCE("l"."lesson_count", (0)::bigint))::integer AS "lesson_count",
    (COALESCE("o"."objective_count", (0)::bigint))::integer AS "objective_count",
    (COALESCE("q"."published_question_count", (0)::bigint))::integer AS "published_question_count",
    (COALESCE("q"."level_1_questions", (0)::bigint))::integer AS "level_1_questions",
    (COALESCE("q"."level_2_questions", (0)::bigint))::integer AS "level_2_questions",
    (COALESCE("q"."level_3_questions", (0)::bigint))::integer AS "level_3_questions",
    (COALESCE("q"."level_4_questions", (0)::bigint))::integer AS "level_4_questions",
    (COALESCE("q"."level_5_questions", (0)::bigint))::integer AS "level_5_questions"
   FROM (((( VALUES ('prompt_clarity'::"text"), ('context'::"text"), ('specificity'::"text"), ('responsible_use'::"text"), ('verification'::"text")) "t"("topic_id")
     LEFT JOIN ( SELECT "content_items"."adaptive_topic" AS "topic_id",
            "count"(*) AS "lesson_count"
           FROM "public"."content_items"
          WHERE (("content_items"."content_type" = 'lesson'::"public"."content_type") AND ("content_items"."status" = 'published'::"public"."content_status"))
          GROUP BY "content_items"."adaptive_topic") "l" ON (("l"."topic_id" = "t"."topic_id")))
     LEFT JOIN ( SELECT "learning_objectives"."topic_id",
            "count"(*) AS "objective_count"
           FROM "public"."learning_objectives"
          WHERE ("learning_objectives"."status" = 'published'::"text")
          GROUP BY "learning_objectives"."topic_id") "o" ON (("o"."topic_id" = "t"."topic_id")))
     LEFT JOIN ( SELECT "question_bank"."topic_id",
            "count"(*) FILTER (WHERE ("question_bank"."status" = 'published'::"text")) AS "published_question_count",
            "count"(*) FILTER (WHERE (("question_bank"."status" = 'published'::"text") AND ("question_bank"."difficulty" = 1))) AS "level_1_questions",
            "count"(*) FILTER (WHERE (("question_bank"."status" = 'published'::"text") AND ("question_bank"."difficulty" = 2))) AS "level_2_questions",
            "count"(*) FILTER (WHERE (("question_bank"."status" = 'published'::"text") AND ("question_bank"."difficulty" = 3))) AS "level_3_questions",
            "count"(*) FILTER (WHERE (("question_bank"."status" = 'published'::"text") AND ("question_bank"."difficulty" = 4))) AS "level_4_questions",
            "count"(*) FILTER (WHERE (("question_bank"."status" = 'published'::"text") AND ("question_bank"."difficulty" = 5))) AS "level_5_questions"
           FROM "public"."question_bank"
          GROUP BY "question_bank"."topic_id") "q" ON (("q"."topic_id" = "t"."topic_id")));


ALTER VIEW "public"."phase7_content_health" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_cases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "case_code" "text" NOT NULL,
    "title" "text" NOT NULL,
    "scenario" "text" NOT NULL,
    "claim_text" "text" DEFAULT ''::"text" NOT NULL,
    "case_type" "text" NOT NULL,
    "subskill" "text" NOT NULL,
    "difficulty" integer DEFAULT 1 NOT NULL,
    "media_type" "text" DEFAULT 'text'::"text" NOT NULL,
    "media_url" "text",
    "media_description" "text" DEFAULT ''::"text" NOT NULL,
    "evidence" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "actions" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "source_options" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "best_source_index" integer DEFAULT 0 NOT NULL,
    "correct_decision" "text" NOT NULL,
    "expected_confidence" "text" DEFAULT 'medium'::"text" NOT NULL,
    "explanation" "text" NOT NULL,
    "learning_point" "text" NOT NULL,
    "source_name" "text" DEFAULT ''::"text" NOT NULL,
    "source_url" "text" DEFAULT ''::"text" NOT NULL,
    "source_published_at" timestamp with time zone,
    "generated_by" "text" DEFAULT 'curated'::"text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "expires_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "verification_cases_confidence_check" CHECK (("expected_confidence" = ANY (ARRAY['low'::"text", 'medium'::"text", 'high'::"text"]))),
    CONSTRAINT "verification_cases_decision_check" CHECK (("correct_decision" = ANY (ARRAY['supported'::"text", 'ai_generated'::"text", 'manipulated'::"text", 'misleading_context'::"text", 'unsupported_claim'::"text", 'unverified'::"text", 'insufficient_evidence'::"text"]))),
    CONSTRAINT "verification_cases_difficulty_check" CHECK ((("difficulty" >= 1) AND ("difficulty" <= 5))),
    CONSTRAINT "verification_cases_generated_by_check" CHECK (("generated_by" = ANY (ARRAY['curated'::"text", 'content_automation'::"text", 'administrator'::"text"]))),
    CONSTRAINT "verification_cases_source_index_check" CHECK ((("best_source_index" >= 0) AND ("best_source_index" <= 3))),
    CONSTRAINT "verification_cases_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'published'::"text", 'archived'::"text"]))),
    CONSTRAINT "verification_cases_subskill_check" CHECK (("subskill" = ANY (ARRAY['source_verification'::"text", 'claim_verification'::"text", 'media_provenance'::"text", 'manipulation_detection'::"text", 'citation_verification'::"text", 'uncertainty_judgment'::"text"]))),
    CONSTRAINT "verification_cases_type_check" CHECK (("case_type" = ANY (ARRAY['image'::"text", 'video'::"text", 'audio'::"text", 'claim'::"text", 'citation'::"text", 'scam'::"text"])))
);


ALTER TABLE "public"."verification_cases" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."phase9_verification_case_health" AS
 SELECT "subskill",
    ("count"(*) FILTER (WHERE ("status" = 'published'::"text")))::integer AS "published_cases",
    ("count"(*) FILTER (WHERE (("status" = 'published'::"text") AND ("difficulty" = 1))))::integer AS "foundation",
    ("count"(*) FILTER (WHERE (("status" = 'published'::"text") AND ("difficulty" = 2))))::integer AS "developing",
    ("count"(*) FILTER (WHERE (("status" = 'published'::"text") AND ("difficulty" = 3))))::integer AS "proficient",
    ("count"(*) FILTER (WHERE (("status" = 'published'::"text") AND ("difficulty" = 4))))::integer AS "advanced",
    ("count"(*) FILTER (WHERE (("status" = 'published'::"text") AND ("difficulty" = 5))))::integer AS "expert"
   FROM "public"."verification_cases"
  GROUP BY "subskill";


ALTER VIEW "public"."phase9_verification_case_health" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prompt_coach_daily_usage" (
    "user_id" "uuid" NOT NULL,
    "usage_date" "date" NOT NULL,
    "ai_uses" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "prompt_coach_daily_usage_count_check" CHECK ((("ai_uses" >= 0) AND ("ai_uses" <= 3)))
);


ALTER TABLE "public"."prompt_coach_daily_usage" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prompt_coach_mastery_evidence" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "session_id" "uuid" NOT NULL,
    "revision_id" "uuid" NOT NULL,
    "topic_id" "text" NOT NULL,
    "is_correct" boolean DEFAULT true NOT NULL,
    "counted_for_mastery" boolean DEFAULT true NOT NULL,
    "score_before" integer NOT NULL,
    "score_after" integer NOT NULL,
    "evidence_day" "date" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "prompt_coach_mastery_score_after_check" CHECK ((("score_after" >= 0) AND ("score_after" <= 100))),
    CONSTRAINT "prompt_coach_mastery_score_before_check" CHECK ((("score_before" >= 0) AND ("score_before" <= 100))),
    CONSTRAINT "prompt_coach_mastery_topic_check" CHECK (("topic_id" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text"])))
);


ALTER TABLE "public"."prompt_coach_mastery_evidence" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prompt_coach_revisions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "revision_number" integer NOT NULL,
    "prompt_text" "text" NOT NULL,
    "mode" "text" DEFAULT 'standard'::"text" NOT NULL,
    "overall_score" integer DEFAULT 0 NOT NULL,
    "rubric" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "privacy_flags" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "standard_feedback" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "ai_guidance" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "prompt_coach_revisions_mode_check" CHECK (("mode" = ANY (ARRAY['standard'::"text", 'ai'::"text"]))),
    CONSTRAINT "prompt_coach_revisions_number_check" CHECK (("revision_number" >= 1)),
    CONSTRAINT "prompt_coach_revisions_prompt_length_check" CHECK ((("char_length"("prompt_text") >= 10) AND ("char_length"("prompt_text") <= 1500))),
    CONSTRAINT "prompt_coach_revisions_score_check" CHECK ((("overall_score" >= 0) AND ("overall_score" <= 100)))
);


ALTER TABLE "public"."prompt_coach_revisions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prompt_coach_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "focus_topic" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "prompt_coach_sessions_focus_topic_check" CHECK ((("focus_topic" IS NULL) OR ("focus_topic" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"]))))
);


ALTER TABLE "public"."prompt_coach_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."question_attempts" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "item_id" "text" NOT NULL,
    "topic_id" "text" NOT NULL,
    "is_correct" boolean NOT NULL,
    "attempt_type" "text" DEFAULT 'quiz'::"text" NOT NULL,
    "counted_for_mastery" boolean DEFAULT true NOT NULL,
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "attempt_day" "date" DEFAULT (("now"() AT TIME ZONE 'Asia/Manila'::"text"))::"date" NOT NULL,
    CONSTRAINT "question_attempts_topic_id_check" CHECK (("topic_id" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"])))
);


ALTER TABLE "public"."question_attempts" OWNER TO "postgres";


ALTER TABLE "public"."question_attempts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."question_attempts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."question_exposure" (
    "user_id" "uuid" NOT NULL,
    "question_id" "uuid" NOT NULL,
    "times_seen" integer DEFAULT 0 NOT NULL,
    "times_answered" integer DEFAULT 0 NOT NULL,
    "correct_count" integer DEFAULT 0 NOT NULL,
    "first_seen_at" timestamp with time zone,
    "last_seen_at" timestamp with time zone,
    "last_answered_at" timestamp with time zone,
    "last_is_correct" boolean
);


ALTER TABLE "public"."question_exposure" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."review_schedule" (
    "user_id" "uuid" NOT NULL,
    "topic_id" "text" NOT NULL,
    "due_at" timestamp with time zone NOT NULL,
    "mastery_snapshot" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "review_schedule_mastery_snapshot_check" CHECK ((("mastery_snapshot" >= 0) AND ("mastery_snapshot" <= 100))),
    CONSTRAINT "review_schedule_topic_id_check" CHECK (("topic_id" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"])))
);


ALTER TABLE "public"."review_schedule" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."topic_mastery" (
    "user_id" "uuid" NOT NULL,
    "topic_id" "text" NOT NULL,
    "mastery" integer DEFAULT 0 NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL,
    "correct_answers" integer DEFAULT 0 NOT NULL,
    "last_practiced_at" timestamp with time zone,
    "next_review_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "topic_mastery_attempts_check" CHECK (("attempts" >= 0)),
    CONSTRAINT "topic_mastery_correct_answers_check" CHECK (("correct_answers" >= 0)),
    CONSTRAINT "topic_mastery_mastery_check" CHECK ((("mastery" >= 0) AND ("mastery" <= 100))),
    CONSTRAINT "topic_mastery_topic_id_check" CHECK (("topic_id" = ANY (ARRAY['prompt_clarity'::"text", 'context'::"text", 'specificity'::"text", 'responsible_use'::"text", 'verification'::"text"])))
);


ALTER TABLE "public"."topic_mastery" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_automation_settings" (
    "id" integer DEFAULT 1 NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "max_pending_drafts" integer DEFAULT 40 NOT NULL,
    "draft_archive_days" integer DEFAULT 30 NOT NULL,
    "rejected_delete_days" integer DEFAULT 7 NOT NULL,
    "archived_delete_days" integer DEFAULT 90 NOT NULL,
    "max_dynamic_published" integer DEFAULT 120 NOT NULL,
    "dynamic_case_max_age_days" integer DEFAULT 180 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "manual_cooldown_minutes" integer DEFAULT 10 NOT NULL,
    "last_manual_run_at" timestamp with time zone,
    "last_manual_attempt_at" timestamp with time zone,
    "last_manual_success_at" timestamp with time zone,
    "last_manual_error" "text",
    "max_articles_per_run" integer DEFAULT 6 NOT NULL,
    "max_drafts_per_run" integer DEFAULT 2 NOT NULL,
    "max_drafts_per_day" integer DEFAULT 4 NOT NULL,
    "monthly_draft_cap" integer DEFAULT 40 NOT NULL,
    "monthly_groq_request_cap" integer DEFAULT 80 NOT NULL,
    CONSTRAINT "verification_automation_settings_age_check" CHECK ((("dynamic_case_max_age_days" >= 30) AND ("dynamic_case_max_age_days" <= 730))),
    CONSTRAINT "verification_automation_settings_archive_check" CHECK ((("draft_archive_days" >= 7) AND ("draft_archive_days" <= 180))),
    CONSTRAINT "verification_automation_settings_archived_delete_check" CHECK ((("archived_delete_days" >= 30) AND ("archived_delete_days" <= 365))),
    CONSTRAINT "verification_automation_settings_articles_run_check" CHECK ((("max_articles_per_run" >= 1) AND ("max_articles_per_run" <= 20))),
    CONSTRAINT "verification_automation_settings_delete_check" CHECK ((("rejected_delete_days" >= 1) AND ("rejected_delete_days" <= 60))),
    CONSTRAINT "verification_automation_settings_drafts_day_check" CHECK ((("max_drafts_per_day" >= 1) AND ("max_drafts_per_day" <= 50))),
    CONSTRAINT "verification_automation_settings_drafts_run_check" CHECK ((("max_drafts_per_run" >= 1) AND ("max_drafts_per_run" <= 10))),
    CONSTRAINT "verification_automation_settings_groq_monthly_cap_check" CHECK ((("monthly_groq_request_cap" >= 1) AND ("monthly_groq_request_cap" <= 5000))),
    CONSTRAINT "verification_automation_settings_manual_cooldown_check" CHECK ((("manual_cooldown_minutes" >= 1) AND ("manual_cooldown_minutes" <= 120))),
    CONSTRAINT "verification_automation_settings_monthly_cap_check" CHECK ((("monthly_draft_cap" >= 1) AND ("monthly_draft_cap" <= 1000))),
    CONSTRAINT "verification_automation_settings_pending_check" CHECK ((("max_pending_drafts" >= 5) AND ("max_pending_drafts" <= 200))),
    CONSTRAINT "verification_automation_settings_published_check" CHECK ((("max_dynamic_published" >= 20) AND ("max_dynamic_published" <= 500))),
    CONSTRAINT "verification_automation_settings_singleton" CHECK (("id" = 1))
);


ALTER TABLE "public"."verification_automation_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_case_attempts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "session_id" "uuid" NOT NULL,
    "case_id" "uuid" NOT NULL,
    "subskill" "text" NOT NULL,
    "selected_evidence" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "selected_actions" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "selected_source_index" integer NOT NULL,
    "decision" "text" NOT NULL,
    "confidence" "text" NOT NULL,
    "evidence_score" integer DEFAULT 0 NOT NULL,
    "method_score" integer DEFAULT 0 NOT NULL,
    "decision_score" integer DEFAULT 0 NOT NULL,
    "source_score" integer DEFAULT 0 NOT NULL,
    "confidence_score" integer DEFAULT 0 NOT NULL,
    "total_score" integer DEFAULT 0 NOT NULL,
    "decision_correct" boolean DEFAULT false NOT NULL,
    "counted_for_mastery" boolean DEFAULT false NOT NULL,
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "verification_case_attempts_confidence_check" CHECK (("confidence" = ANY (ARRAY['low'::"text", 'medium'::"text", 'high'::"text"]))),
    CONSTRAINT "verification_case_attempts_decision_check" CHECK (("decision" = ANY (ARRAY['supported'::"text", 'ai_generated'::"text", 'manipulated'::"text", 'misleading_context'::"text", 'unsupported_claim'::"text", 'unverified'::"text", 'insufficient_evidence'::"text"]))),
    CONSTRAINT "verification_case_attempts_score_check" CHECK (((("evidence_score" >= 0) AND ("evidence_score" <= 30)) AND (("method_score" >= 0) AND ("method_score" <= 25)) AND (("decision_score" >= 0) AND ("decision_score" <= 25)) AND (("source_score" >= 0) AND ("source_score" <= 10)) AND (("confidence_score" >= 0) AND ("confidence_score" <= 10)) AND (("total_score" >= 0) AND ("total_score" <= 100)))),
    CONSTRAINT "verification_case_attempts_subskill_check" CHECK (("subskill" = ANY (ARRAY['source_verification'::"text", 'claim_verification'::"text", 'media_provenance'::"text", 'manipulation_detection'::"text", 'citation_verification'::"text", 'uncertainty_judgment'::"text"])))
);


ALTER TABLE "public"."verification_case_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_case_drafts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "article_id" "uuid",
    "title" "text" NOT NULL,
    "summary" "text" NOT NULL,
    "source_name" "text" DEFAULT ''::"text" NOT NULL,
    "source_url" "text" NOT NULL,
    "source_published_at" timestamp with time zone,
    "draft_payload" "jsonb" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_at" timestamp with time zone,
    CONSTRAINT "verification_case_drafts_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'approved'::"text", 'rejected'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."verification_case_drafts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_case_exposure" (
    "user_id" "uuid" NOT NULL,
    "case_id" "uuid" NOT NULL,
    "times_seen" integer DEFAULT 0 NOT NULL,
    "last_seen_at" timestamp with time zone,
    "last_score" integer,
    CONSTRAINT "verification_case_exposure_score_check" CHECK ((("last_score" IS NULL) OR (("last_score" >= 0) AND ("last_score" <= 100)))),
    CONSTRAINT "verification_case_exposure_seen_check" CHECK (("times_seen" >= 0))
);


ALTER TABLE "public"."verification_case_exposure" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_groq_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "model" "text",
    "success" boolean DEFAULT false NOT NULL,
    "error_code" "text",
    "source_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."verification_groq_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_media_exposure" (
    "user_id" "uuid" NOT NULL,
    "media_id" "text" NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."verification_media_exposure" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_session_cases" (
    "session_id" "uuid" NOT NULL,
    "case_id" "uuid" NOT NULL,
    "sequence" integer NOT NULL
);


ALTER TABLE "public"."verification_session_cases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "rank_level" integer DEFAULT 1 NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    CONSTRAINT "verification_sessions_rank_check" CHECK ((("rank_level" >= 1) AND ("rank_level" <= 5))),
    CONSTRAINT "verification_sessions_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'completed'::"text", 'abandoned'::"text"])))
);


ALTER TABLE "public"."verification_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."verification_subskill_mastery" (
    "user_id" "uuid" NOT NULL,
    "subskill" "text" NOT NULL,
    "mastery" integer DEFAULT 0 NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL,
    "successful_attempts" integer DEFAULT 0 NOT NULL,
    "last_practiced_at" timestamp with time zone,
    "next_review_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "verification_subskill_mastery_attempts_check" CHECK ((("attempts" >= 0) AND ("successful_attempts" >= 0))),
    CONSTRAINT "verification_subskill_mastery_subskill_check" CHECK (("subskill" = ANY (ARRAY['source_verification'::"text", 'claim_verification'::"text", 'media_provenance'::"text", 'manipulation_detection'::"text", 'citation_verification'::"text", 'uncertainty_judgment'::"text"]))),
    CONSTRAINT "verification_subskill_mastery_value_check" CHECK ((("mastery" >= 0) AND ("mastery" <= 100)))
);


ALTER TABLE "public"."verification_subskill_mastery" OWNER TO "postgres";


ALTER TABLE ONLY "public"."assessment_attempts"
    ADD CONSTRAINT "assessment_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."automation_runs"
    ADD CONSTRAINT "automation_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."automation_settings"
    ADD CONSTRAINT "automation_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."awareness_articles"
    ADD CONSTRAINT "awareness_articles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."awareness_direct_sources"
    ADD CONSTRAINT "awareness_direct_sources_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."awareness_feed_settings"
    ADD CONSTRAINT "awareness_feed_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."awareness_refresh_runs"
    ADD CONSTRAINT "awareness_refresh_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."awareness_source_domains"
    ADD CONSTRAINT "awareness_source_domains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."awareness_user_actions"
    ADD CONSTRAINT "awareness_user_actions_pkey" PRIMARY KEY ("user_id", "article_id");



ALTER TABLE ONLY "public"."content_item_versions"
    ADD CONSTRAINT "content_item_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_items"
    ADD CONSTRAINT "content_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_sources"
    ADD CONSTRAINT "content_sources_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."content_sources"
    ADD CONSTRAINT "content_sources_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_sources"
    ADD CONSTRAINT "content_sources_source_url_key" UNIQUE ("source_url");



ALTER TABLE ONLY "public"."discovered_articles"
    ADD CONSTRAINT "discovered_articles_article_url_key" UNIQUE ("article_url");



ALTER TABLE ONLY "public"."discovered_articles"
    ADD CONSTRAINT "discovered_articles_fingerprint_key" UNIQUE ("fingerprint");



ALTER TABLE ONLY "public"."discovered_articles"
    ADD CONSTRAINT "discovered_articles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."generated_content_drafts"
    ADD CONSTRAINT "generated_content_drafts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge_check_session_questions"
    ADD CONSTRAINT "knowledge_check_session_questions_pkey" PRIMARY KEY ("session_id", "question_id");



ALTER TABLE ONLY "public"."knowledge_check_session_questions"
    ADD CONSTRAINT "knowledge_check_session_questions_session_id_sequence_key" UNIQUE ("session_id", "sequence");



ALTER TABLE ONLY "public"."knowledge_check_sessions"
    ADD CONSTRAINT "knowledge_check_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."learner_progress"
    ADD CONSTRAINT "learner_progress_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."learner_topic_progression"
    ADD CONSTRAINT "learner_topic_progression_pkey" PRIMARY KEY ("user_id", "topic_id");



ALTER TABLE ONLY "public"."learning_objectives"
    ADD CONSTRAINT "learning_objectives_objective_code_key" UNIQUE ("objective_code");



ALTER TABLE ONLY "public"."learning_objectives"
    ADD CONSTRAINT "learning_objectives_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prompt_coach_daily_usage"
    ADD CONSTRAINT "prompt_coach_daily_usage_pkey" PRIMARY KEY ("user_id", "usage_date");



ALTER TABLE ONLY "public"."prompt_coach_mastery_evidence"
    ADD CONSTRAINT "prompt_coach_mastery_day_topic_unique" UNIQUE ("user_id", "topic_id", "evidence_day");



ALTER TABLE ONLY "public"."prompt_coach_mastery_evidence"
    ADD CONSTRAINT "prompt_coach_mastery_evidence_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prompt_coach_mastery_evidence"
    ADD CONSTRAINT "prompt_coach_mastery_session_topic_unique" UNIQUE ("user_id", "session_id", "topic_id");



ALTER TABLE ONLY "public"."prompt_coach_revisions"
    ADD CONSTRAINT "prompt_coach_revisions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prompt_coach_revisions"
    ADD CONSTRAINT "prompt_coach_revisions_session_number_unique" UNIQUE ("session_id", "revision_number");



ALTER TABLE ONLY "public"."prompt_coach_sessions"
    ADD CONSTRAINT "prompt_coach_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."question_attempts"
    ADD CONSTRAINT "question_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."question_bank"
    ADD CONSTRAINT "question_bank_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."question_bank"
    ADD CONSTRAINT "question_bank_question_code_key" UNIQUE ("question_code");



ALTER TABLE ONLY "public"."question_exposure"
    ADD CONSTRAINT "question_exposure_pkey" PRIMARY KEY ("user_id", "question_id");



ALTER TABLE ONLY "public"."review_schedule"
    ADD CONSTRAINT "review_schedule_pkey" PRIMARY KEY ("user_id", "topic_id");



ALTER TABLE ONLY "public"."topic_mastery"
    ADD CONSTRAINT "topic_mastery_pkey" PRIMARY KEY ("user_id", "topic_id");



ALTER TABLE ONLY "public"."verification_automation_settings"
    ADD CONSTRAINT "verification_automation_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."verification_case_attempts"
    ADD CONSTRAINT "verification_case_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."verification_case_attempts"
    ADD CONSTRAINT "verification_case_attempts_session_case_unique" UNIQUE ("session_id", "case_id");



ALTER TABLE ONLY "public"."verification_case_drafts"
    ADD CONSTRAINT "verification_case_drafts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."verification_case_exposure"
    ADD CONSTRAINT "verification_case_exposure_pkey" PRIMARY KEY ("user_id", "case_id");



ALTER TABLE ONLY "public"."verification_cases"
    ADD CONSTRAINT "verification_cases_case_code_key" UNIQUE ("case_code");



ALTER TABLE ONLY "public"."verification_cases"
    ADD CONSTRAINT "verification_cases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."verification_groq_requests"
    ADD CONSTRAINT "verification_groq_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."verification_media_exposure"
    ADD CONSTRAINT "verification_media_exposure_pkey" PRIMARY KEY ("user_id", "media_id");



ALTER TABLE ONLY "public"."verification_session_cases"
    ADD CONSTRAINT "verification_session_cases_pkey" PRIMARY KEY ("session_id", "case_id");



ALTER TABLE ONLY "public"."verification_session_cases"
    ADD CONSTRAINT "verification_session_cases_session_id_sequence_key" UNIQUE ("session_id", "sequence");



ALTER TABLE ONLY "public"."verification_sessions"
    ADD CONSTRAINT "verification_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."verification_subskill_mastery"
    ADD CONSTRAINT "verification_subskill_mastery_pkey" PRIMARY KEY ("user_id", "subskill");



CREATE INDEX "content_item_versions_content_idx" ON "public"."content_item_versions" USING "btree" ("content_id", "version" DESC);



CREATE INDEX "content_items_parent_idx" ON "public"."content_items" USING "btree" ("parent_id", "sort_order");



CREATE INDEX "content_items_review_date_idx" ON "public"."content_items" USING "btree" ("review_date") WHERE ("review_date" IS NOT NULL);



CREATE INDEX "content_items_type_status_order_idx" ON "public"."content_items" USING "btree" ("content_type", "status", "sort_order");



CREATE INDEX "idx_assessment_attempts_user_completed" ON "public"."assessment_attempts" USING "btree" ("user_id", "completed_at" DESC);



CREATE INDEX "idx_assessment_attempts_user_type_time" ON "public"."assessment_attempts" USING "btree" ("user_id", "assessment_type", "completed_at");



CREATE INDEX "idx_awareness_actions_user_article" ON "public"."awareness_user_actions" USING "btree" ("user_id", "article_id");



CREATE INDEX "idx_awareness_active_rank_time" ON "public"."awareness_articles" USING "btree" ("is_active", "relevance_score" DESC, "published_at" DESC);



CREATE INDEX "idx_awareness_articles_ai_feed" ON "public"."awareness_articles" USING "btree" ("is_active", "ai_relevance_score" DESC, "relevance_score" DESC, "published_at" DESC) WHERE ("ai_relevance_score" >= 4);



CREATE INDEX "idx_awareness_articles_category_time" ON "public"."awareness_articles" USING "btree" ("category", "published_at" DESC) WHERE ("is_active" = true);



CREATE INDEX "idx_awareness_articles_content_hash" ON "public"."awareness_articles" USING "btree" ("content_hash") WHERE ("content_hash" IS NOT NULL);



CREATE INDEX "idx_awareness_articles_feed" ON "public"."awareness_articles" USING "btree" ("is_active", "relevance_score" DESC, "published_at" DESC);



CREATE INDEX "idx_awareness_articles_region_time" ON "public"."awareness_articles" USING "btree" ("region", "published_at" DESC) WHERE ("is_active" = true);



CREATE INDEX "idx_awareness_direct_sources_enabled_priority" ON "public"."awareness_direct_sources" USING "btree" ("enabled", "priority" DESC);



CREATE INDEX "idx_awareness_refresh_runs_time" ON "public"."awareness_refresh_runs" USING "btree" ("started_at" DESC);



CREATE INDEX "idx_awareness_user_actions_saved" ON "public"."awareness_user_actions" USING "btree" ("user_id", "saved_at" DESC) WHERE ("saved_at" IS NOT NULL);



CREATE INDEX "idx_content_items_status_order" ON "public"."content_items" USING "btree" ("status", "sort_order", "created_at");



CREATE INDEX "idx_generated_content_drafts_queue" ON "public"."generated_content_drafts" USING "btree" ("status", "created_at");



CREATE INDEX "idx_kc_session_questions_session" ON "public"."knowledge_check_session_questions" USING "btree" ("session_id", "sequence");



CREATE INDEX "idx_kc_sessions_user_time" ON "public"."knowledge_check_sessions" USING "btree" ("user_id", "started_at" DESC);



CREATE INDEX "idx_learner_topic_progression_user_topic" ON "public"."learner_topic_progression" USING "btree" ("user_id", "topic_id");



CREATE INDEX "idx_learning_objectives_content" ON "public"."learning_objectives" USING "btree" ("content_item_id", "sort_order");



CREATE INDEX "idx_learning_objectives_published_order" ON "public"."learning_objectives" USING "btree" ("status", "topic_id", "required_level", "sort_order");



CREATE INDEX "idx_learning_objectives_topic_level" ON "public"."learning_objectives" USING "btree" ("topic_id", "required_level", "status");



CREATE INDEX "idx_prompt_coach_mastery_user_topic_time" ON "public"."prompt_coach_mastery_evidence" USING "btree" ("user_id", "topic_id", "created_at");



CREATE INDEX "idx_prompt_coach_revisions_session_number" ON "public"."prompt_coach_revisions" USING "btree" ("session_id", "revision_number");



CREATE INDEX "idx_prompt_coach_revisions_user_created" ON "public"."prompt_coach_revisions" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_prompt_coach_revisions_user_session_revision" ON "public"."prompt_coach_revisions" USING "btree" ("user_id", "session_id", "revision_number");



CREATE INDEX "idx_prompt_coach_sessions_user_updated" ON "public"."prompt_coach_sessions" USING "btree" ("user_id", "updated_at" DESC);



CREATE INDEX "idx_question_attempts_user_attempted" ON "public"."question_attempts" USING "btree" ("user_id", "attempted_at" DESC);



CREATE INDEX "idx_question_attempts_user_counted_time" ON "public"."question_attempts" USING "btree" ("user_id", "counted_for_mastery", "attempted_at");



CREATE INDEX "idx_question_attempts_user_day" ON "public"."question_attempts" USING "btree" ("user_id", "attempt_day" DESC);



CREATE INDEX "idx_question_attempts_user_item_topic_time" ON "public"."question_attempts" USING "btree" ("user_id", "item_id", "topic_id", "attempted_at" DESC);



CREATE INDEX "idx_question_attempts_user_topic" ON "public"."question_attempts" USING "btree" ("user_id", "topic_id");



CREATE INDEX "idx_question_bank_objective" ON "public"."question_bank" USING "btree" ("objective_id", "status");



CREATE INDEX "idx_question_bank_review_queue" ON "public"."question_bank" USING "btree" ("generated_by", "validation_status", "status", "created_at");



CREATE INDEX "idx_question_bank_selection" ON "public"."question_bank" USING "btree" ("status", "validation_status", "topic_id", "difficulty");



CREATE INDEX "idx_review_schedule_user_due" ON "public"."review_schedule" USING "btree" ("user_id", "due_at");



CREATE INDEX "idx_topic_mastery_user_topic" ON "public"."topic_mastery" USING "btree" ("user_id", "topic_id");



CREATE INDEX "idx_verification_attempts_user_case_time" ON "public"."verification_case_attempts" USING "btree" ("user_id", "case_id", "attempted_at" DESC);



CREATE INDEX "idx_verification_attempts_user_subskill_time" ON "public"."verification_case_attempts" USING "btree" ("user_id", "subskill", "attempted_at" DESC);



CREATE INDEX "idx_verification_case_drafts_status_created" ON "public"."verification_case_drafts" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_verification_cases_selection" ON "public"."verification_cases" USING "btree" ("status", "subskill", "difficulty", "created_at" DESC);



CREATE INDEX "idx_verification_cases_source_url" ON "public"."verification_cases" USING "btree" ("source_url") WHERE ("source_url" <> ''::"text");



CREATE INDEX "idx_verification_groq_requests_requested_at" ON "public"."verification_groq_requests" USING "btree" ("requested_at" DESC);



CREATE INDEX "idx_verification_mastery_user_subskill" ON "public"."verification_subskill_mastery" USING "btree" ("user_id", "subskill");



CREATE INDEX "idx_verification_sessions_user_time" ON "public"."verification_sessions" USING "btree" ("user_id", "started_at" DESC);



CREATE INDEX "learner_progress_updated_at_idx" ON "public"."learner_progress" USING "btree" ("updated_at" DESC);



CREATE INDEX "profiles_role_idx" ON "public"."profiles" USING "btree" ("role");



CREATE UNIQUE INDEX "uq_assessment_one_diagnostic" ON "public"."assessment_attempts" USING "btree" ("user_id", "assessment_type") WHERE ("assessment_type" = 'diagnostic'::"text");



CREATE UNIQUE INDEX "uq_awareness_articles_source_url" ON "public"."awareness_articles" USING "btree" ("source_url");



CREATE UNIQUE INDEX "uq_awareness_direct_sources_url" ON "public"."awareness_direct_sources" USING "btree" ("source_url");



CREATE UNIQUE INDEX "uq_awareness_source_domains_domain" ON "public"."awareness_source_domains" USING "btree" ("lower"("domain"));



CREATE UNIQUE INDEX "uq_generated_draft_article" ON "public"."generated_content_drafts" USING "btree" ("article_id") WHERE (("article_id" IS NOT NULL) AND ("status" <> 'rejected'::"text"));



CREATE UNIQUE INDEX "uq_verification_case_drafts_source" ON "public"."verification_case_drafts" USING "btree" ("source_url") WHERE ("status" <> 'rejected'::"text");



CREATE UNIQUE INDEX "uq_verification_case_drafts_source_active" ON "public"."verification_case_drafts" USING "btree" ("source_url") WHERE ("status" = ANY (ARRAY['draft'::"text", 'approved'::"text", 'archived'::"text"]));



CREATE INDEX "verification_media_exposure_recent_idx" ON "public"."verification_media_exposure" USING "btree" ("user_id", "last_seen_at" DESC);



CREATE OR REPLACE TRIGGER "content_items_versioning" BEFORE INSERT OR DELETE OR UPDATE ON "public"."content_items" FOR EACH ROW EXECUTE FUNCTION "public"."capture_content_item_version"();



CREATE OR REPLACE TRIGGER "learner_progress_set_updated_at" BEFORE UPDATE ON "public"."learner_progress" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "profiles_set_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_enforce_verification_activity_topic" BEFORE INSERT OR UPDATE ON "public"."content_items" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_verification_activity_topic"();



CREATE OR REPLACE TRIGGER "trg_phase7_generated_draft_queue_cap" BEFORE INSERT OR UPDATE OF "status" ON "public"."generated_content_drafts" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_phase7_generated_draft_queue_cap"();



CREATE OR REPLACE TRIGGER "trg_phase7_question_review_queue_cap" BEFORE INSERT OR UPDATE OF "generated_by", "validation_status", "status" ON "public"."question_bank" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_phase7_question_review_queue_cap"();



CREATE OR REPLACE TRIGGER "trg_retag_adaptive_item_history" AFTER UPDATE ON "public"."content_items" FOR EACH ROW EXECUTE FUNCTION "public"."retag_adaptive_item_history"();



CREATE OR REPLACE TRIGGER "trg_sync_phase7_child_publish_status" AFTER UPDATE OF "status" ON "public"."content_items" FOR EACH ROW EXECUTE FUNCTION "public"."sync_phase7_child_publish_status"();



ALTER TABLE ONLY "public"."assessment_attempts"
    ADD CONSTRAINT "assessment_attempts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."awareness_user_actions"
    ADD CONSTRAINT "awareness_user_actions_article_id_fkey" FOREIGN KEY ("article_id") REFERENCES "public"."awareness_articles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."awareness_user_actions"
    ADD CONSTRAINT "awareness_user_actions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_item_versions"
    ADD CONSTRAINT "content_item_versions_changed_by_fkey" FOREIGN KEY ("changed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_items"
    ADD CONSTRAINT "content_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_items"
    ADD CONSTRAINT "content_items_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."discovered_articles"
    ADD CONSTRAINT "discovered_articles_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."content_sources"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."generated_content_drafts"
    ADD CONSTRAINT "generated_content_drafts_article_id_fkey" FOREIGN KEY ("article_id") REFERENCES "public"."discovered_articles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."generated_content_drafts"
    ADD CONSTRAINT "generated_content_drafts_published_content_id_fkey" FOREIGN KEY ("published_content_id") REFERENCES "public"."content_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."generated_content_drafts"
    ADD CONSTRAINT "generated_content_drafts_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."knowledge_check_session_questions"
    ADD CONSTRAINT "knowledge_check_session_questions_objective_id_fkey" FOREIGN KEY ("objective_id") REFERENCES "public"."learning_objectives"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."knowledge_check_session_questions"
    ADD CONSTRAINT "knowledge_check_session_questions_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "public"."question_bank"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."knowledge_check_session_questions"
    ADD CONSTRAINT "knowledge_check_session_questions_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."knowledge_check_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge_check_sessions"
    ADD CONSTRAINT "knowledge_check_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."learner_progress"
    ADD CONSTRAINT "learner_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."learner_topic_progression"
    ADD CONSTRAINT "learner_topic_progression_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."learning_objectives"
    ADD CONSTRAINT "learning_objectives_content_item_id_fkey" FOREIGN KEY ("content_item_id") REFERENCES "public"."content_items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prompt_coach_daily_usage"
    ADD CONSTRAINT "prompt_coach_daily_usage_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prompt_coach_mastery_evidence"
    ADD CONSTRAINT "prompt_coach_mastery_evidence_revision_id_fkey" FOREIGN KEY ("revision_id") REFERENCES "public"."prompt_coach_revisions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prompt_coach_mastery_evidence"
    ADD CONSTRAINT "prompt_coach_mastery_evidence_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."prompt_coach_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prompt_coach_mastery_evidence"
    ADD CONSTRAINT "prompt_coach_mastery_evidence_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prompt_coach_revisions"
    ADD CONSTRAINT "prompt_coach_revisions_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."prompt_coach_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prompt_coach_revisions"
    ADD CONSTRAINT "prompt_coach_revisions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prompt_coach_sessions"
    ADD CONSTRAINT "prompt_coach_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."question_attempts"
    ADD CONSTRAINT "question_attempts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."question_bank"
    ADD CONSTRAINT "question_bank_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."question_bank"
    ADD CONSTRAINT "question_bank_objective_id_fkey" FOREIGN KEY ("objective_id") REFERENCES "public"."learning_objectives"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."question_bank"
    ADD CONSTRAINT "question_bank_source_content_id_fkey" FOREIGN KEY ("source_content_id") REFERENCES "public"."content_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."question_exposure"
    ADD CONSTRAINT "question_exposure_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "public"."question_bank"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."question_exposure"
    ADD CONSTRAINT "question_exposure_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."review_schedule"
    ADD CONSTRAINT "review_schedule_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."topic_mastery"
    ADD CONSTRAINT "topic_mastery_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."verification_case_attempts"
    ADD CONSTRAINT "verification_case_attempts_case_id_fkey" FOREIGN KEY ("case_id") REFERENCES "public"."verification_cases"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."verification_case_attempts"
    ADD CONSTRAINT "verification_case_attempts_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."verification_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."verification_case_attempts"
    ADD CONSTRAINT "verification_case_attempts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."verification_case_exposure"
    ADD CONSTRAINT "verification_case_exposure_case_id_fkey" FOREIGN KEY ("case_id") REFERENCES "public"."verification_cases"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."verification_case_exposure"
    ADD CONSTRAINT "verification_case_exposure_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."verification_media_exposure"
    ADD CONSTRAINT "verification_media_exposure_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."verification_session_cases"
    ADD CONSTRAINT "verification_session_cases_case_id_fkey" FOREIGN KEY ("case_id") REFERENCES "public"."verification_cases"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."verification_session_cases"
    ADD CONSTRAINT "verification_session_cases_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."verification_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."verification_sessions"
    ADD CONSTRAINT "verification_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."verification_subskill_mastery"
    ADD CONSTRAINT "verification_subskill_mastery_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."assessment_attempts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "assessment_attempts_select_own_or_admin" ON "public"."assessment_attempts" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'administrator'::"public"."app_role"))))));



ALTER TABLE "public"."automation_runs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "automation_runs_admin_read" ON "public"."automation_runs" FOR SELECT TO "authenticated" USING ("public"."is_promptwise_admin"());



ALTER TABLE "public"."automation_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "automation_settings_admin_all" ON "public"."automation_settings" TO "authenticated" USING ("public"."is_promptwise_admin"()) WITH CHECK ("public"."is_promptwise_admin"());



CREATE POLICY "awareness_actions_own_insert" ON "public"."awareness_user_actions" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "awareness_actions_own_select" ON "public"."awareness_user_actions" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "awareness_actions_own_update" ON "public"."awareness_user_actions" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."awareness_articles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "awareness_articles_learner_read" ON "public"."awareness_articles" FOR SELECT TO "authenticated" USING ((("is_active" = true) OR "public"."awareness_is_admin"()));



ALTER TABLE "public"."awareness_direct_sources" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "awareness_direct_sources_admin_read" ON "public"."awareness_direct_sources" FOR SELECT TO "authenticated" USING ("public"."awareness_is_admin"());



ALTER TABLE "public"."awareness_feed_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."awareness_refresh_runs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "awareness_runs_admin_read" ON "public"."awareness_refresh_runs" FOR SELECT TO "authenticated" USING ("public"."awareness_is_admin"());



CREATE POLICY "awareness_settings_admin_read" ON "public"."awareness_feed_settings" FOR SELECT TO "authenticated" USING ("public"."awareness_is_admin"());



ALTER TABLE "public"."awareness_source_domains" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "awareness_sources_admin_read" ON "public"."awareness_source_domains" FOR SELECT TO "authenticated" USING ("public"."awareness_is_admin"());



ALTER TABLE "public"."awareness_user_actions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "content_admin_delete" ON "public"."content_items" FOR DELETE TO "authenticated" USING (( SELECT "public"."is_administrator"() AS "is_administrator"));



CREATE POLICY "content_admin_insert" ON "public"."content_items" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."is_administrator"() AS "is_administrator"));



CREATE POLICY "content_admin_update" ON "public"."content_items" FOR UPDATE TO "authenticated" USING (( SELECT "public"."is_administrator"() AS "is_administrator")) WITH CHECK (( SELECT "public"."is_administrator"() AS "is_administrator"));



ALTER TABLE "public"."content_item_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."content_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "content_read_published_or_admin" ON "public"."content_items" FOR SELECT TO "authenticated" USING ((("status" = 'published'::"public"."content_status") OR ( SELECT "public"."is_administrator"() AS "is_administrator")));



ALTER TABLE "public"."content_sources" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "content_sources_admin_all" ON "public"."content_sources" TO "authenticated" USING ("public"."is_promptwise_admin"()) WITH CHECK ("public"."is_promptwise_admin"());



CREATE POLICY "content_versions_admin_read" ON "public"."content_item_versions" FOR SELECT TO "authenticated" USING (( SELECT "public"."is_administrator"() AS "is_administrator"));



ALTER TABLE "public"."discovered_articles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "discovered_articles_admin_all" ON "public"."discovered_articles" TO "authenticated" USING ("public"."is_promptwise_admin"()) WITH CHECK ("public"."is_promptwise_admin"());



ALTER TABLE "public"."generated_content_drafts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "generated_drafts_admin_all" ON "public"."generated_content_drafts" TO "authenticated" USING ("public"."is_promptwise_admin"()) WITH CHECK ("public"."is_promptwise_admin"());



CREATE POLICY "kc_session_questions_read_own" ON "public"."knowledge_check_session_questions" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."knowledge_check_sessions" "s"
  WHERE (("s"."id" = "knowledge_check_session_questions"."session_id") AND (("s"."user_id" = "auth"."uid"()) OR "public"."is_promptwise_admin"())))));



CREATE POLICY "kc_sessions_read_own" ON "public"."knowledge_check_sessions" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_promptwise_admin"()));



ALTER TABLE "public"."knowledge_check_session_questions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_check_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."learner_progress" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "learner_progression_read_own" ON "public"."learner_topic_progression" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_promptwise_admin"()));



ALTER TABLE "public"."learner_topic_progression" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."learning_objectives" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "learning_objectives_admin_all" ON "public"."learning_objectives" TO "authenticated" USING ("public"."is_promptwise_admin"()) WITH CHECK ("public"."is_promptwise_admin"());



CREATE POLICY "learning_objectives_read" ON "public"."learning_objectives" FOR SELECT TO "authenticated" USING ((("status" = 'published'::"text") OR "public"."is_promptwise_admin"()));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_own_or_admin" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "public"."is_administrator"() AS "is_administrator")));



CREATE POLICY "progress_insert_own" ON "public"."learner_progress" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "progress_select_own_or_admin" ON "public"."learner_progress" FOR SELECT TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "public"."is_administrator"() AS "is_administrator")));



CREATE POLICY "progress_update_own" ON "public"."learner_progress" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."prompt_coach_daily_usage" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "prompt_coach_daily_usage_select_own" ON "public"."prompt_coach_daily_usage" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."prompt_coach_mastery_evidence" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "prompt_coach_mastery_select_own" ON "public"."prompt_coach_mastery_evidence" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."prompt_coach_revisions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "prompt_coach_revisions_select_own" ON "public"."prompt_coach_revisions" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."prompt_coach_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "prompt_coach_sessions_select_own" ON "public"."prompt_coach_sessions" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."question_attempts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "question_attempts_select_own_or_admin" ON "public"."question_attempts" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'administrator'::"public"."app_role"))))));



ALTER TABLE "public"."question_bank" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "question_bank_admin_all" ON "public"."question_bank" TO "authenticated" USING ("public"."is_promptwise_admin"()) WITH CHECK ("public"."is_promptwise_admin"());



ALTER TABLE "public"."question_exposure" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "question_exposure_read_own" ON "public"."question_exposure" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_promptwise_admin"()));



ALTER TABLE "public"."review_schedule" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "review_schedule_select_own_or_admin" ON "public"."review_schedule" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'administrator'::"public"."app_role"))))));



ALTER TABLE "public"."topic_mastery" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "topic_mastery_select_own_or_admin" ON "public"."topic_mastery" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'administrator'::"public"."app_role"))))));



CREATE POLICY "verification_attempts_select_own" ON "public"."verification_case_attempts" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."verification_automation_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."verification_case_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."verification_case_drafts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "verification_case_drafts_admin_select" ON "public"."verification_case_drafts" FOR SELECT TO "authenticated" USING ("public"."phase9_is_admin"());



ALTER TABLE "public"."verification_case_exposure" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."verification_cases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "verification_cases_select_published" ON "public"."verification_cases" FOR SELECT TO "authenticated" USING ((("status" = 'published'::"text") OR "public"."phase9_is_admin"()));



CREATE POLICY "verification_exposure_select_own" ON "public"."verification_case_exposure" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."verification_groq_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "verification_groq_requests_admin_read" ON "public"."verification_groq_requests" FOR SELECT TO "authenticated" USING ("public"."phase9_is_admin"());



ALTER TABLE "public"."verification_media_exposure" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."verification_session_cases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "verification_session_cases_select_own" ON "public"."verification_session_cases" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."verification_sessions" "s"
  WHERE (("s"."id" = "verification_session_cases"."session_id") AND ("s"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."verification_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "verification_sessions_select_own" ON "public"."verification_sessions" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "verification_settings_admin_select" ON "public"."verification_automation_settings" FOR SELECT TO "authenticated" USING ("public"."phase9_is_admin"());



ALTER TABLE "public"."verification_subskill_mastery" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "verification_subskill_select_own" ON "public"."verification_subskill_mastery" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."abandon_adaptive_knowledge_check"("p_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."abandon_adaptive_knowledge_check"("p_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."abandon_adaptive_knowledge_check"("p_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."abandon_verification_session"("p_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."abandon_verification_session"("p_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."abandon_verification_session"("p_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_list_verification_cases"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_verification_cases"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_verification_cases"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."approve_verification_case_draft"("p_draft_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."approve_verification_case_draft"("p_draft_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_verification_case_draft"("p_draft_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."archive_verification_case"("p_case_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."archive_verification_case"("p_case_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."archive_verification_case"("p_case_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."awareness_ai_topic_score"("p_title" "text", "p_summary" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."awareness_ai_topic_score"("p_title" "text", "p_summary" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."awareness_ai_topic_score"("p_title" "text", "p_summary" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."awareness_is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."awareness_is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."awareness_is_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."capture_content_item_version"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."capture_content_item_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."capture_content_item_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."capture_content_item_version"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_adaptive_knowledge_check"("p_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_adaptive_knowledge_check"("p_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_adaptive_knowledge_check"("p_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_verification_session"("p_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_verification_session"("p_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_verification_session"("p_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_adaptive_knowledge_check"("p_question_count" integer, "p_focus_topic" "text", "p_mode" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_adaptive_knowledge_check"("p_question_count" integer, "p_focus_topic" "text", "p_mode" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_adaptive_knowledge_check"("p_question_count" integer, "p_focus_topic" "text", "p_mode" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_adaptive_verification_session"("p_case_count" integer, "p_rank_level" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_adaptive_verification_session"("p_case_count" integer, "p_rank_level" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_adaptive_verification_session"("p_case_count" integer, "p_rank_level" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_phase7_generated_draft_queue_cap"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_phase7_generated_draft_queue_cap"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_phase7_generated_draft_queue_cap"() TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_phase7_question_review_queue_cap"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_phase7_question_review_queue_cap"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_phase7_question_review_queue_cap"() TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_verification_activity_topic"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_verification_activity_topic"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_verification_activity_topic"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_adaptive_state"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_adaptive_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_adaptive_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_awareness_feed_cache"("p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_awareness_feed_cache"("p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_awareness_feed_cache"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_phase7_queue_health"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_phase7_queue_health"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_phase7_queue_health"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_prompt_coach_recent_sessions"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_prompt_coach_recent_sessions"("p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_prompt_coach_recent_sessions"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_verification_automation_overview"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_verification_automation_overview"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_verification_automation_overview"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_administrator"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_administrator"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_administrator"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_administrator"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_promptwise_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_promptwise_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_promptwise_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."phase7_cleanup_content_queues"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."phase7_cleanup_content_queues"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."phase9_cleanup_awareness_feed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."phase9_cleanup_awareness_feed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."phase9_cleanup_awareness_feed"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."phase9_cleanup_verification_queues"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."phase9_cleanup_verification_queues"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."phase9_is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."phase9_is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."phase9_is_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prompt_coach_ai_usage_status"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prompt_coach_ai_usage_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prompt_coach_ai_usage_status"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prompt_coach_server_topic_score"("p_prompt" "text", "p_topic" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prompt_coach_server_topic_score"("p_prompt" "text", "p_topic" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."publish_generated_content_draft"("p_draft_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."publish_generated_content_draft"("p_draft_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."publish_generated_content_draft"("p_draft_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rebuild_adaptive_mastery_for_user"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rebuild_adaptive_mastery_for_user"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rebuild_my_adaptive_mastery"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rebuild_my_adaptive_mastery"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rebuild_my_adaptive_mastery"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_adaptive_attempt"("p_user_id" "uuid", "p_item_id" "text", "p_topic_id" "text", "p_is_correct" boolean, "p_attempt_type" "text", "p_counted_for_mastery" boolean, "p_attempted_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_adaptive_attempt"("p_user_id" "uuid", "p_item_id" "text", "p_topic_id" "text", "p_is_correct" boolean, "p_attempt_type" "text", "p_counted_for_mastery" boolean, "p_attempted_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_adaptive_attempt"("p_user_id" "uuid", "p_item_id" "text", "p_topic_id" "text", "p_is_correct" boolean, "p_attempt_type" "text", "p_counted_for_mastery" boolean, "p_attempted_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_adaptive_diagnostic"("p_user_id" "uuid", "p_score" integer, "p_correct_answers" integer, "p_total_questions" integer, "p_answers" "jsonb", "p_completed_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_adaptive_diagnostic"("p_user_id" "uuid", "p_score" integer, "p_correct_answers" integer, "p_total_questions" integer, "p_answers" "jsonb", "p_completed_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_adaptive_diagnostic"("p_user_id" "uuid", "p_score" integer, "p_correct_answers" integer, "p_total_questions" integer, "p_answers" "jsonb", "p_completed_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_learning_question_answer"("p_session_id" "uuid", "p_question_id" "uuid", "p_selected_index" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_learning_question_answer"("p_session_id" "uuid", "p_question_id" "uuid", "p_selected_index" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_learning_question_answer"("p_session_id" "uuid", "p_question_id" "uuid", "p_selected_index" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_prompt_coach_revision"("p_session_id" "uuid", "p_prompt_text" "text", "p_mode" "text", "p_rubric" "jsonb", "p_privacy_flags" "jsonb", "p_standard_feedback" "jsonb", "p_ai_guidance" "jsonb", "p_focus_topic" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_prompt_coach_revision"("p_session_id" "uuid", "p_prompt_text" "text", "p_mode" "text", "p_rubric" "jsonb", "p_privacy_flags" "jsonb", "p_standard_feedback" "jsonb", "p_ai_guidance" "jsonb", "p_focus_topic" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_prompt_coach_revision"("p_session_id" "uuid", "p_prompt_text" "text", "p_mode" "text", "p_rubric" "jsonb", "p_privacy_flags" "jsonb", "p_standard_feedback" "jsonb", "p_ai_guidance" "jsonb", "p_focus_topic" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."refresh_learner_topic_progression"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."refresh_learner_topic_progression"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."refresh_my_learning_progression"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."refresh_my_learning_progression"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_my_learning_progression"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."refund_prompt_coach_ai_use"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."refund_prompt_coach_ai_use"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."refund_prompt_coach_ai_use"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."reject_generated_content_draft"("p_draft_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reject_generated_content_draft"("p_draft_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reject_generated_content_draft"("p_draft_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reject_verification_case_draft"("p_draft_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reject_verification_case_draft"("p_draft_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reject_verification_case_draft"("p_draft_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reserve_prompt_coach_ai_use"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reserve_prompt_coach_ai_use"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."reserve_prompt_coach_ai_use"() TO "service_role";



GRANT ALL ON FUNCTION "public"."retag_adaptive_item_history"() TO "anon";
GRANT ALL ON FUNCTION "public"."retag_adaptive_item_history"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."retag_adaptive_item_history"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."review_question_bank_item"("p_question_id" "uuid", "p_stem" "text", "p_options" "jsonb", "p_correct_index" integer, "p_explanation" "text", "p_difficulty" integer, "p_question_type" "text", "p_action" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."review_question_bank_item"("p_question_id" "uuid", "p_stem" "text", "p_options" "jsonb", "p_correct_index" integer, "p_explanation" "text", "p_difficulty" integer, "p_question_type" "text", "p_action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."review_question_bank_item"("p_question_id" "uuid", "p_stem" "text", "p_options" "jsonb", "p_correct_index" integer, "p_explanation" "text", "p_difficulty" integer, "p_question_type" "text", "p_action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_verification_case_attempt"("p_session_id" "uuid", "p_case_id" "uuid", "p_selected_evidence" "text"[], "p_selected_actions" "text"[], "p_selected_source_index" integer, "p_decision" "text", "p_confidence" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_verification_case_attempt"("p_session_id" "uuid", "p_case_id" "uuid", "p_selected_evidence" "text"[], "p_selected_actions" "text"[], "p_selected_source_index" integer, "p_decision" "text", "p_confidence" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_verification_case_attempt"("p_session_id" "uuid", "p_case_id" "uuid", "p_selected_evidence" "text"[], "p_selected_actions" "text"[], "p_selected_source_index" integer, "p_decision" "text", "p_confidence" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_verification_guess"("p_session_id" "uuid", "p_case_id" "uuid", "p_decision" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_verification_guess"("p_session_id" "uuid", "p_case_id" "uuid", "p_decision" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_verification_guess"("p_session_id" "uuid", "p_case_id" "uuid", "p_decision" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_phase7_child_publish_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_phase7_child_publish_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_phase7_child_publish_status"() TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "service_role";
GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_my_profile"("p_full_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_profile"("p_full_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_my_profile"("p_full_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_my_profile"("p_full_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_verification_automation_settings"("p_enabled" boolean, "p_max_articles_per_run" integer, "p_max_drafts_per_run" integer, "p_max_drafts_per_day" integer, "p_monthly_draft_cap" integer, "p_monthly_groq_request_cap" integer, "p_max_pending_drafts" integer, "p_manual_cooldown_minutes" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_verification_automation_settings"("p_enabled" boolean, "p_max_articles_per_run" integer, "p_max_drafts_per_run" integer, "p_max_drafts_per_day" integer, "p_monthly_draft_cap" integer, "p_monthly_groq_request_cap" integer, "p_max_pending_drafts" integer, "p_manual_cooldown_minutes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_verification_automation_settings"("p_enabled" boolean, "p_max_articles_per_run" integer, "p_max_drafts_per_run" integer, "p_max_drafts_per_day" integer, "p_monthly_draft_cap" integer, "p_monthly_groq_request_cap" integer, "p_max_pending_drafts" integer, "p_manual_cooldown_minutes" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_verification_case_core"("p_case_id" "uuid", "p_title" "text", "p_scenario" "text", "p_claim_text" "text", "p_subskill" "text", "p_case_type" "text", "p_difficulty" integer, "p_correct_decision" "text", "p_expected_confidence" "text", "p_explanation" "text", "p_learning_point" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_verification_case_core"("p_case_id" "uuid", "p_title" "text", "p_scenario" "text", "p_claim_text" "text", "p_subskill" "text", "p_case_type" "text", "p_difficulty" integer, "p_correct_decision" "text", "p_expected_confidence" "text", "p_explanation" "text", "p_learning_point" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_verification_case_core"("p_case_id" "uuid", "p_title" "text", "p_scenario" "text", "p_claim_text" "text", "p_subskill" "text", "p_case_type" "text", "p_difficulty" integer, "p_correct_decision" "text", "p_expected_confidence" "text", "p_explanation" "text", "p_learning_point" "text") TO "service_role";



GRANT ALL ON TABLE "public"."assessment_attempts" TO "anon";
GRANT ALL ON TABLE "public"."assessment_attempts" TO "authenticated";
GRANT ALL ON TABLE "public"."assessment_attempts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."assessment_attempts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."assessment_attempts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."assessment_attempts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."automation_runs" TO "anon";
GRANT ALL ON TABLE "public"."automation_runs" TO "authenticated";
GRANT ALL ON TABLE "public"."automation_runs" TO "service_role";



GRANT ALL ON TABLE "public"."automation_settings" TO "anon";
GRANT ALL ON TABLE "public"."automation_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."automation_settings" TO "service_role";



GRANT ALL ON TABLE "public"."awareness_articles" TO "anon";
GRANT ALL ON TABLE "public"."awareness_articles" TO "authenticated";
GRANT ALL ON TABLE "public"."awareness_articles" TO "service_role";



GRANT ALL ON TABLE "public"."awareness_direct_sources" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."awareness_direct_sources" TO "authenticated";
GRANT ALL ON TABLE "public"."awareness_direct_sources" TO "service_role";



GRANT ALL ON TABLE "public"."awareness_feed_settings" TO "anon";
GRANT ALL ON TABLE "public"."awareness_feed_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."awareness_feed_settings" TO "service_role";



GRANT ALL ON TABLE "public"."awareness_refresh_runs" TO "anon";
GRANT ALL ON TABLE "public"."awareness_refresh_runs" TO "authenticated";
GRANT ALL ON TABLE "public"."awareness_refresh_runs" TO "service_role";



GRANT ALL ON TABLE "public"."awareness_source_domains" TO "anon";
GRANT ALL ON TABLE "public"."awareness_source_domains" TO "authenticated";
GRANT ALL ON TABLE "public"."awareness_source_domains" TO "service_role";



GRANT ALL ON TABLE "public"."awareness_user_actions" TO "anon";
GRANT ALL ON TABLE "public"."awareness_user_actions" TO "authenticated";
GRANT ALL ON TABLE "public"."awareness_user_actions" TO "service_role";



GRANT ALL ON TABLE "public"."content_item_versions" TO "service_role";
GRANT SELECT ON TABLE "public"."content_item_versions" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."content_item_versions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."content_item_versions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."content_item_versions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."content_items" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."content_items" TO "authenticated";



GRANT ALL ON TABLE "public"."content_sources" TO "anon";
GRANT ALL ON TABLE "public"."content_sources" TO "authenticated";
GRANT ALL ON TABLE "public"."content_sources" TO "service_role";



GRANT ALL ON TABLE "public"."discovered_articles" TO "anon";
GRANT ALL ON TABLE "public"."discovered_articles" TO "authenticated";
GRANT ALL ON TABLE "public"."discovered_articles" TO "service_role";



GRANT ALL ON TABLE "public"."generated_content_drafts" TO "anon";
GRANT ALL ON TABLE "public"."generated_content_drafts" TO "authenticated";
GRANT ALL ON TABLE "public"."generated_content_drafts" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_check_session_questions" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_check_session_questions" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_check_session_questions" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_check_sessions" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_check_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_check_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."learner_progress" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."learner_progress" TO "authenticated";



GRANT ALL ON TABLE "public"."learner_topic_progression" TO "anon";
GRANT ALL ON TABLE "public"."learner_topic_progression" TO "authenticated";
GRANT ALL ON TABLE "public"."learner_topic_progression" TO "service_role";



GRANT ALL ON TABLE "public"."learning_objectives" TO "anon";
GRANT ALL ON TABLE "public"."learning_objectives" TO "authenticated";
GRANT ALL ON TABLE "public"."learning_objectives" TO "service_role";



GRANT ALL ON TABLE "public"."question_bank" TO "anon";
GRANT ALL ON TABLE "public"."question_bank" TO "authenticated";
GRANT ALL ON TABLE "public"."question_bank" TO "service_role";



GRANT ALL ON TABLE "public"."phase7_content_health" TO "anon";
GRANT ALL ON TABLE "public"."phase7_content_health" TO "authenticated";
GRANT ALL ON TABLE "public"."phase7_content_health" TO "service_role";



GRANT ALL ON TABLE "public"."verification_cases" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."verification_cases" TO "authenticated";
GRANT ALL ON TABLE "public"."verification_cases" TO "service_role";



GRANT ALL ON TABLE "public"."phase9_verification_case_health" TO "anon";
GRANT ALL ON TABLE "public"."phase9_verification_case_health" TO "authenticated";
GRANT ALL ON TABLE "public"."phase9_verification_case_health" TO "service_role";



GRANT ALL ON TABLE "public"."prompt_coach_daily_usage" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."prompt_coach_daily_usage" TO "authenticated";
GRANT ALL ON TABLE "public"."prompt_coach_daily_usage" TO "service_role";



GRANT ALL ON TABLE "public"."prompt_coach_mastery_evidence" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."prompt_coach_mastery_evidence" TO "authenticated";
GRANT ALL ON TABLE "public"."prompt_coach_mastery_evidence" TO "service_role";



GRANT ALL ON TABLE "public"."prompt_coach_revisions" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."prompt_coach_revisions" TO "authenticated";
GRANT ALL ON TABLE "public"."prompt_coach_revisions" TO "service_role";



GRANT ALL ON TABLE "public"."prompt_coach_sessions" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."prompt_coach_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."prompt_coach_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."question_attempts" TO "anon";
GRANT ALL ON TABLE "public"."question_attempts" TO "authenticated";
GRANT ALL ON TABLE "public"."question_attempts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."question_attempts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."question_attempts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."question_attempts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."question_exposure" TO "anon";
GRANT ALL ON TABLE "public"."question_exposure" TO "authenticated";
GRANT ALL ON TABLE "public"."question_exposure" TO "service_role";



GRANT ALL ON TABLE "public"."review_schedule" TO "anon";
GRANT ALL ON TABLE "public"."review_schedule" TO "authenticated";
GRANT ALL ON TABLE "public"."review_schedule" TO "service_role";



GRANT ALL ON TABLE "public"."topic_mastery" TO "anon";
GRANT ALL ON TABLE "public"."topic_mastery" TO "authenticated";
GRANT ALL ON TABLE "public"."topic_mastery" TO "service_role";



GRANT ALL ON TABLE "public"."verification_automation_settings" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."verification_automation_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."verification_automation_settings" TO "service_role";



GRANT ALL ON TABLE "public"."verification_case_attempts" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."verification_case_attempts" TO "authenticated";
GRANT ALL ON TABLE "public"."verification_case_attempts" TO "service_role";



GRANT ALL ON TABLE "public"."verification_case_drafts" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."verification_case_drafts" TO "authenticated";
GRANT ALL ON TABLE "public"."verification_case_drafts" TO "service_role";



GRANT ALL ON TABLE "public"."verification_case_exposure" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."verification_case_exposure" TO "authenticated";
GRANT ALL ON TABLE "public"."verification_case_exposure" TO "service_role";



GRANT ALL ON TABLE "public"."verification_groq_requests" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."verification_groq_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."verification_groq_requests" TO "service_role";



GRANT ALL ON TABLE "public"."verification_media_exposure" TO "service_role";



GRANT ALL ON TABLE "public"."verification_session_cases" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."verification_session_cases" TO "authenticated";
GRANT ALL ON TABLE "public"."verification_session_cases" TO "service_role";



GRANT ALL ON TABLE "public"."verification_sessions" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."verification_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."verification_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."verification_subskill_mastery" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."verification_subskill_mastery" TO "authenticated";
GRANT ALL ON TABLE "public"."verification_subskill_mastery" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







