-- Phase 2A: account-scoped orientation. Apply BEFORE deploying the Flutter client.
-- Existing accounts are backfilled as complete, so no prior learner is locked
-- out or loses progress. Newly created accounts will have no row until they
-- acknowledge orientation. Phase 2B will introduce the separate survey flow.

create table if not exists public.learner_onboarding (
  user_id uuid primary key references auth.users(id) on delete cascade,
  orientation_completed_at timestamptz,
  video_watched_at timestamptz,
  survey_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint video_requires_orientation check (
    video_watched_at is null or orientation_completed_at is not null
  )
);

alter table public.learner_onboarding enable row level security;

revoke all on table public.learner_onboarding from public, anon;
grant select, insert, update on table public.learner_onboarding to authenticated;

create policy learner_onboarding_select_own on public.learner_onboarding
  for select to authenticated using ((select auth.uid()) = user_id);
create policy learner_onboarding_insert_own on public.learner_onboarding
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy learner_onboarding_update_own on public.learner_onboarding
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Existing accounts: do not re-onboard. Do NOT mark their video watched.
insert into public.learner_onboarding (user_id, orientation_completed_at)
select id, now() from auth.users
on conflict (user_id) do nothing;

-- SECURITY INVOKER: RLS applies to the actual signed-in learner. No client
-- supplied user ID or timestamp. On replay, Watch later cannot clear a prior
-- watched timestamp. Do not treat self-reported watching as verified learning.
create or replace function public.complete_my_orientation(p_watched boolean)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_record record;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  insert into public.learner_onboarding (
    user_id, orientation_completed_at, video_watched_at
  ) values (
    auth.uid(), now(), case when coalesce(p_watched, false) then now() else null end
  )
  on conflict (user_id) do update set
    orientation_completed_at = coalesce(
      learner_onboarding.orientation_completed_at, now()
    ),
    video_watched_at = case
      when coalesce(p_watched, false) then
        coalesce(learner_onboarding.video_watched_at, now())
      else learner_onboarding.video_watched_at
    end,
    updated_at = now()
  returning learner_onboarding.orientation_completed_at,
            learner_onboarding.video_watched_at
  into v_record;
  return jsonb_build_object(
    'orientation_completed_at', v_record.orientation_completed_at,
    'video_watched_at', v_record.video_watched_at
  );
end;
$$;

revoke all on function public.complete_my_orientation(boolean)
  from public, anon;
grant execute on function public.complete_my_orientation(boolean)
  to authenticated;
