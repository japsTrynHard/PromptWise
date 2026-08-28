-- PromptWise forward-only runtime contract reconciliation.
--
-- This migration is additive and is based on a read-only inspection of the
-- linked database on 2026-08-28. It does not rewrite historical migrations,
-- delete learner data, or fabricate learning-objective coverage.

create table if not exists public.verification_media_rounds (
  user_id uuid not null references auth.users(id) on delete cascade,
  round_id text not null,
  subskill text not null default 'media_provenance',
  correct_side text not null,
  explanation text not null,
  correct_source jsonb not null,
  image_a_url text not null,
  image_b_url text not null,
  served_at timestamptz not null default now(),
  expires_at timestamptz not null,
  answered_at timestamptz,
  selected_side text,
  is_correct boolean,
  counted_for_mastery boolean not null default false,
  primary key (user_id, round_id),
  constraint verification_media_rounds_round_id_unique unique (round_id),
  constraint verification_media_rounds_id_check
    check (char_length(btrim(round_id)) between 1 and 160),
  constraint verification_media_rounds_subskill_check
    check (subskill = 'media_provenance'),
  constraint verification_media_rounds_correct_side_check
    check (correct_side in ('A', 'B')),
  constraint verification_media_rounds_feedback_check
    check (
      char_length(btrim(explanation)) between 1 and 4000
      and jsonb_typeof(correct_source) = 'object'
    ),
  constraint verification_media_rounds_image_urls_check
    check (
      image_a_url like 'https://upload.wikimedia.org/%'
      and image_b_url like 'https://upload.wikimedia.org/%'
    ),
  constraint verification_media_rounds_selected_side_check
    check (selected_side is null or selected_side in ('A', 'B')),
  constraint verification_media_rounds_answer_check
    check (
      (answered_at is null and selected_side is null and is_correct is null)
      or
      (answered_at is not null and selected_side is not null and is_correct is not null)
    )
);

create index if not exists verification_media_rounds_user_time_idx
  on public.verification_media_rounds (user_id, served_at desc);

create index if not exists verification_media_rounds_counted_idx
  on public.verification_media_rounds (user_id, subskill, answered_at)
  where counted_for_mastery = true;

alter table public.verification_media_rounds enable row level security;

-- The answer key stays server-only. Learners submit an opaque round UUID to
-- the dedicated RPC and never receive direct table access to correct_side.
revoke all on table public.verification_media_rounds
  from public, anon, authenticated;
grant all on table public.verification_media_rounds to service_role;

-- The existing verification RPCs rebuild subskill mastery from case attempts.
-- This trigger extends that canonical calculation with server-issued online
-- image rounds, without changing the existing RPC signatures.
create or replace function public.normalize_verification_subskill_mastery()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_event record;
  v_mastery integer := 0;
  v_attempts integer := 0;
  v_success integer := 0;
  v_last timestamptz;
  v_days integer;
begin
  for v_event in
    select occurred_at, score
    from (
      select a.attempted_at as occurred_at, a.total_score as score
      from public.verification_case_attempts a
      where a.user_id = new.user_id
        and a.subskill = new.subskill
        and a.counted_for_mastery = true

      union all

      select r.answered_at as occurred_at,
             case when r.is_correct then 100 else 0 end as score
      from public.verification_media_rounds r
      where r.user_id = new.user_id
        and r.subskill = new.subskill
        and r.counted_for_mastery = true
        and r.answered_at is not null
    ) evidence
    order by occurred_at
  loop
    if v_attempts = 0 then
      v_mastery := v_event.score;
    else
      v_mastery := round(v_mastery * 0.75 + v_event.score * 0.25)::integer;
    end if;
    v_attempts := v_attempts + 1;
    if v_event.score >= 70 then v_success := v_success + 1; end if;
    v_last := v_event.occurred_at;
  end loop;

  new.mastery := greatest(0, least(100, v_mastery));
  new.attempts := v_attempts;
  new.successful_attempts := v_success;
  new.last_practiced_at := v_last;
  if v_last is null then
    new.next_review_at := null;
  else
    v_days := case
      when new.mastery < 40 then 1
      when new.mastery < 60 then 2
      when new.mastery < 80 then 4
      else 7
    end;
    new.next_review_at := v_last + make_interval(days => v_days);
  end if;
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.normalize_verification_subskill_mastery()
  from public, anon, authenticated;
grant execute on function public.normalize_verification_subskill_mastery()
  to service_role;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.verification_subskill_mastery'::regclass
      and tgname = 'normalize_verification_subskill_mastery_before_write'
      and not tgisinternal
  ) then
    create trigger normalize_verification_subskill_mastery_before_write
      before insert or update on public.verification_subskill_mastery
      for each row execute function public.normalize_verification_subskill_mastery();
  end if;
end
$$;

create or replace function public.submit_image_comparison_attempt(
  p_round_id text,
  p_selected_side text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_user uuid := auth.uid();
  v_round public.verification_media_rounds%rowtype;
  v_side text := upper(btrim(coalesce(p_selected_side, '')));
  v_correct boolean;
  v_last_counted timestamptz;
  v_due timestamptz;
  v_should_count boolean := false;
  v_mastery integer := 0;
begin
  if v_user is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  if nullif(btrim(p_round_id), '') is null then
    raise exception 'Image comparison round is required.' using errcode = '22023';
  end if;
  if v_side not in ('A', 'B') then
    raise exception 'Image comparison choice is invalid.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user::text || '|verification_media|' || btrim(p_round_id), 0)
  );

  select * into v_round
  from public.verification_media_rounds
  where user_id = v_user and round_id = btrim(p_round_id)
  for update;

  if v_round.round_id is null then
    raise exception 'This image comparison round was not issued to the current learner.'
      using errcode = '42501';
  end if;

  if v_round.answered_at is not null then
    select mastery into v_mastery
    from public.verification_subskill_mastery
    where user_id = v_user and subskill = v_round.subskill;
    return jsonb_build_object(
      'round_id', v_round.round_id,
      'is_correct', v_round.is_correct,
      'selected_side', v_round.selected_side,
      'correct_side', v_round.correct_side,
      'explanation', v_round.explanation,
      'correct_source', v_round.correct_source,
      'counted_for_mastery', v_round.counted_for_mastery,
      'subskill', v_round.subskill,
      'subskill_mastery_after', coalesce(v_mastery, 0),
      'duplicate', true
    );
  end if;

  if now() > v_round.expires_at then
    raise exception 'This image comparison round has expired. Request another set.'
      using errcode = 'P0001';
  end if;

  v_correct := v_side = v_round.correct_side;

  select max(occurred_at) into v_last_counted
  from (
    select attempted_at as occurred_at
    from public.verification_case_attempts
    where user_id = v_user
      and subskill = v_round.subskill
      and counted_for_mastery = true
    union all
    select answered_at
    from public.verification_media_rounds
    where user_id = v_user
      and subskill = v_round.subskill
      and counted_for_mastery = true
      and answered_at is not null
  ) evidence;

  if v_last_counted is null then
    v_should_count := true;
  else
    select next_review_at into v_due
    from public.verification_subskill_mastery
    where user_id = v_user and subskill = v_round.subskill;
    v_should_count := v_due is not null
      and now() >= v_due
      and v_last_counted < v_due;
  end if;

  update public.verification_media_rounds
  set answered_at = now(),
      selected_side = v_side,
      is_correct = v_correct,
      counted_for_mastery = v_should_count
  where user_id = v_user and round_id = v_round.round_id;

  insert into public.verification_subskill_mastery (
    user_id, subskill, mastery, attempts, successful_attempts, updated_at
  ) values (
    v_user, v_round.subskill, 0, 0, 0, now()
  )
  on conflict (user_id, subskill) do update set updated_at = now();

  select mastery into v_mastery
  from public.verification_subskill_mastery
  where user_id = v_user and subskill = v_round.subskill;

  if v_should_count then
    insert into public.question_attempts (
      user_id, item_id, topic_id, is_correct, attempt_type,
      counted_for_mastery, attempted_at, attempt_day
    ) values (
      v_user,
      'verification_media_round:' || v_round.round_id,
      'verification',
      v_correct,
      'verification_activity',
      true,
      now(),
      (now() at time zone 'Asia/Manila')::date
    );
    perform public.rebuild_adaptive_mastery_for_user(v_user);
  end if;

  return jsonb_build_object(
    'round_id', v_round.round_id,
    'is_correct', v_correct,
    'selected_side', v_side,
    'correct_side', v_round.correct_side,
    'explanation', v_round.explanation,
    'correct_source', v_round.correct_source,
    'counted_for_mastery', v_should_count,
    'subskill', v_round.subskill,
    'subskill_mastery_after', coalesce(v_mastery, 0),
    'duplicate', false
  );
end;
$$;

revoke all on function public.submit_image_comparison_attempt(text, text) from public, anon;
grant execute on function public.submit_image_comparison_attempt(text, text) to authenticated, service_role;

-- Reconcile the live learner-feed RPC with the AI-only contract already used
-- by the Flutter fallback query and CURRENT_DB_ONE_RUN finalizer.
create or replace function public.get_my_awareness_feed_cache(
  p_limit integer default 80
)
returns jsonb
language sql
stable
set search_path to 'public'
as $$
  select coalesce(
    jsonb_agg(
      item order by ai_relevance_score desc,
                    relevance_score desc,
                    published_at desc nulls last
    ),
    '[]'::jsonb
  )
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
        'ai_relevance_score', a.ai_relevance_score,
        'read', (ua.read_at is not null),
        'saved', (ua.saved_at is not null)
      ) as item,
      a.ai_relevance_score,
      a.relevance_score,
      a.published_at
    from public.awareness_articles a
    left join public.awareness_user_actions ua
      on ua.article_id = a.id
     and ua.user_id = auth.uid()
    where a.is_active = true
      and a.ai_relevance_score >= 4
    order by a.ai_relevance_score desc,
             a.relevance_score desc,
             a.published_at desc nulls last
    limit least(greatest(coalesce(p_limit, 80), 10), 80)
  ) q;
$$;

revoke all on function public.get_my_awareness_feed_cache(integer) from public, anon;
grant execute on function public.get_my_awareness_feed_cache(integer) to authenticated, service_role;
