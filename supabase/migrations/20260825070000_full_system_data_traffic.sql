-- PromptWise full-system data-traffic optimization
-- Safe to run more than once.

create or replace function public.get_my_awareness_feed_cache(
  p_limit integer default 80
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
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

grant execute on function public.get_my_awareness_feed_cache(integer) to authenticated;


-- One compact adaptive snapshot replaces the old repair RPC + three learner
-- reads. It also returns only the latest counted attempt per item/topic because
-- the rebuilt topic_mastery rows are canonical; the client only needs recent
-- item timing metadata for offline anti-farming checks.
create or replace function public.get_my_adaptive_state()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
$$;

revoke all on function public.get_my_adaptive_state() from public, anon;
grant execute on function public.get_my_adaptive_state() to authenticated;

-- Hot learner paths. These are guarded because some installations may be
-- applying the consolidated one-run files in a different order.
do $$
begin
  if to_regclass('public.question_attempts') is not null then
    execute 'create index if not exists idx_question_attempts_user_counted_time on public.question_attempts (user_id, counted_for_mastery, attempted_at desc)';
  end if;

  if to_regclass('public.assessment_attempts') is not null then
    execute 'create index if not exists idx_assessment_attempts_user_type_time on public.assessment_attempts (user_id, assessment_type, completed_at desc)';
  end if;

  if to_regclass('public.topic_mastery') is not null then
    execute 'create index if not exists idx_topic_mastery_user_topic on public.topic_mastery (user_id, topic_id)';
  end if;

  if to_regclass('public.content_items') is not null then
    execute 'create index if not exists idx_content_items_status_order on public.content_items (status, sort_order, created_at)';
  end if;

  if to_regclass('public.learning_objectives') is not null then
    execute 'create index if not exists idx_learning_objectives_published_order on public.learning_objectives (status, topic_id, required_level, sort_order)';
  end if;

  if to_regclass('public.learner_topic_progression') is not null then
    execute 'create index if not exists idx_learner_topic_progression_user_topic on public.learner_topic_progression (user_id, topic_id)';
  end if;

  if to_regclass('public.prompt_coach_revisions') is not null then
    execute 'create index if not exists idx_prompt_coach_revisions_user_session_revision on public.prompt_coach_revisions (user_id, session_id, revision_number)';
  end if;

  if to_regclass('public.verification_subskill_mastery') is not null then
    execute 'create index if not exists idx_verification_mastery_user_subskill on public.verification_subskill_mastery (user_id, subskill)';
  end if;

  if to_regclass('public.awareness_articles') is not null then
    execute 'create index if not exists idx_awareness_active_rank_time on public.awareness_articles (is_active, relevance_score desc, published_at desc)';
  end if;

  if to_regclass('public.awareness_user_actions') is not null then
    execute 'create index if not exists idx_awareness_actions_user_article on public.awareness_user_actions (user_id, article_id)';
  end if;
end
$$;
