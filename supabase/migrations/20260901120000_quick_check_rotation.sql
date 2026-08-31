-- Rotate Quick Check cases when they are served, including abandoned sessions.
-- The learner's Verification-topic rank is supplied by Flutter; this function
-- selects a bounded adaptive range and keeps unseen/least-recent cases first.

create or replace function public.create_adaptive_verification_session(
  p_case_count integer default 5,
  p_rank_level integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
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
        (v_rank = 1 and c.difficulty between 1 and 2)
        or (v_rank = 2 and c.difficulty between 1 and 3)
        or (v_rank = 3 and c.difficulty between 2 and 4)
        or (v_rank = 4 and c.difficulty between 3 and 5)
        or (v_rank = 5 and c.difficulty between 4 and 5)
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
          md5(id::text || v_session::text)
      ) as seq
    from ranked
    order by
      diversity_bucket,
      subskill_mastery,
      case when times_seen is null then 0 else 1 end,
      coalesce(last_seen_at, '1900-01-01'::timestamptz),
      abs(difficulty - v_rank),
      md5(id::text || v_session::text)
    limit v_count
  )
  insert into public.verification_session_cases (session_id, case_id, sequence)
  select v_session, id, seq from chosen;

  select count(*) into v_selected
  from public.verification_session_cases
  where session_id = v_session;

  if v_selected < 4 then
    delete from public.verification_sessions where id = v_session;
    raise exception 'Not enough verification examples are available right now.'
      using errcode = 'P0001';
  end if;

  -- Exposure belongs to delivery, not answer submission. This makes an
  -- abandoned session rotate instead of returning the same cases immediately.
  insert into public.verification_case_exposure (
    user_id,
    case_id,
    times_seen,
    last_seen_at,
    last_score
  )
  select v_user, sc.case_id, 1, now(), null
  from public.verification_session_cases sc
  where sc.session_id = v_session
  on conflict (user_id, case_id) do update set
    times_seen = public.verification_case_exposure.times_seen + 1,
    last_seen_at = excluded.last_seen_at;

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

revoke all on function public.create_adaptive_verification_session(integer, integer)
  from public, anon;
grant execute on function public.create_adaptive_verification_session(integer, integer)
  to authenticated, service_role;
