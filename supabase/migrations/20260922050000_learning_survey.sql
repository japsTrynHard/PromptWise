-- Phase 2B: persist the learner's explicit interests and prior experience.
-- This migration intentionally exempts accounts that existed before the survey
-- release; it does not invent survey answers or overwrite their existing progress.
alter table public.learner_onboarding
  add column if not exists survey_exempt boolean not null default false;

update public.learner_onboarding
set survey_exempt = true, updated_at = now()
where orientation_completed_at is not null
  and survey_completed_at is null
  and survey_exempt = false;

create table if not exists public.learner_survey (
  user_id uuid primary key references auth.users(id) on delete cascade,
  interests text[] not null,
  experience_level text not null,
  learning_goal text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint learner_survey_interests_valid check (
    cardinality(interests) between 1 and 3
    and interests <@ array[
      'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification'
    ]::text[]
  ),
  constraint learner_survey_experience_valid check (
    experience_level in ('beginner', 'some_experience', 'experienced')
  ),
  constraint learner_survey_goal_valid check (
    learning_goal in (
      'write_better_prompts', 'verify_information', 'use_ai_responsibly', 'explore_ai'
    )
  )
);

alter table public.learner_survey enable row level security;
revoke all on table public.learner_survey from public, anon;
grant select, insert, update on table public.learner_survey to authenticated;

create policy learner_survey_select_own on public.learner_survey
  for select to authenticated using (user_id = (select auth.uid()));
create policy learner_survey_insert_own on public.learner_survey
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy learner_survey_update_own on public.learner_survey
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- One database transaction saves both the answers and completion marker.
-- No client-supplied user ID or timestamps. Direct writes are revoked below;
-- the DEFINER RPC explicitly restricts writes to auth.uid().
create or replace function public.save_my_learning_survey(
  p_interests text[], p_experience_level text, p_learning_goal text
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_survey public.learner_survey%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.learner_onboarding
    where user_id = (select auth.uid())
      and orientation_completed_at is not null
  ) then
    raise exception 'Complete orientation before the learning survey';
  end if;

  -- Fail explicitly, including on null, instead of claiming completion.
  if p_interests is null or cardinality(p_interests) not between 1 and 3
     or not (p_interests <@ array[
       'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification'
     ]::text[])
     or p_experience_level is null or p_experience_level not in (
       'beginner', 'some_experience', 'experienced'
     )
     or p_learning_goal is null or p_learning_goal not in (
       'write_better_prompts', 'verify_information',
       'use_ai_responsibly', 'explore_ai'
     ) then
    raise exception 'Invalid survey answers' using errcode = '22023';
  end if;

  insert into public.learner_survey (
    user_id, interests, experience_level, learning_goal
  ) values (
    (select auth.uid()), p_interests, p_experience_level, p_learning_goal
  ) on conflict (user_id) do update set
    interests = excluded.interests,
    experience_level = excluded.experience_level,
    learning_goal = excluded.learning_goal,
    updated_at = now()
  returning * into v_survey;

  update public.learner_onboarding
  set survey_completed_at = coalesce(survey_completed_at, now()),
      survey_exempt = false,
      updated_at = now()
  where user_id = (select auth.uid());

  return jsonb_build_object(
    'interests', v_survey.interests,
    'experience_level', v_survey.experience_level,
    'learning_goal', v_survey.learning_goal,
    'updated_at', v_survey.updated_at
  );
end;
$$;
revoke all on function public.save_my_learning_survey(text[], text, text)
  from public, anon;
grant execute on function public.save_my_learning_survey(text[], text, text)
  to authenticated;

-- Prevent a client from fabricating completion timestamps or legacy exemption.
-- Both RPCs explicitly use auth.uid() and touch ONLY that account; their
-- owners perform the writes, while learners retain SELECT-only table grants.
alter function public.complete_my_orientation(boolean) security definer;
alter function public.save_my_learning_survey(text[], text, text) security definer;
revoke insert, update on public.learner_onboarding from authenticated;
revoke insert, update on public.learner_survey from authenticated;
