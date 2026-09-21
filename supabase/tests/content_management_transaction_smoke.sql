-- Entire test rolls back. Only isolated fixtures are changed; no real account
-- or existing educational content is modified. No AI calls or emails are sent.
begin;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

insert into auth.users (id, email, raw_user_meta_data)
values ('a843e9b4-50a8-4861-baad-e7101398d715',
  'content-smoke@example.invalid', '{"full_name":"Content smoke fixture"}');
insert into public.profiles (id, email, full_name, role)
values ('a843e9b4-50a8-4861-baad-e7101398d715',
  'content-smoke@example.invalid', 'Content smoke fixture', 'administrator')
on conflict (id) do update set role = 'administrator';

select set_config('request.jwt.claim.sub', 'a843e9b4-50a8-4861-baad-e7101398d715', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $$
declare
  generated_id uuid := '691b5077-7783-42af-9a89-a52882d4e623';
  lesson_id text;
  verified_id uuid;
  rejected_id uuid;
begin
  if not public.is_administrator() then
    raise exception 'Synthetic admin fixture lacks administrator access';
  end if;

  insert into public.content_items (id, content_type, title, description, status)
    values ('__content_smoke_manual__', 'module', 'Smoke module', 'Rollback fixture', 'draft');
  update public.content_items set title = 'Edited module', status = 'published'
    where id = '__content_smoke_manual__';
  if not exists (select 1 from public.content_item_versions
      where content_id = '__content_smoke_manual__' and operation = 'UPDATE') then
    raise exception 'Content edit did not save version history';
  end if;
  update public.content_items set status = 'draft' where id = '__content_smoke_manual__';
  delete from public.content_items where id = '__content_smoke_manual__' and status = 'draft';
  if exists (select 1 from public.content_items where id = '__content_smoke_manual__') then
    raise exception 'Draft deletion failed';
  end if;

  insert into public.generated_content_drafts
    (id, title, summary, topic_id, source_name, source_url, draft_payload)
  values (generated_id, 'Smoke AI lesson', 'Rollback-only test', 'context',
    'Fixture', 'https://example.invalid/content-smoke',
    '{"lesson_sections":["Fixture lesson body"],
      "objectives":[{"title":"Use context","description":"Include the needed context"}],
      "questions":[
        {"stem":"Which context should be included?","options":["Audience","Color","Font","Device"],"correct_index":0,"explanation":"The audience provides the relevant context.","difficulty":1,"question_type":"concept"},
        {"stem":"Which context is most relevant?","options":["Goal","Color","Font","Device"],"correct_index":0,"explanation":"The goal provides the relevant context.","difficulty":1,"question_type":"concept"}
      ]}');
  lesson_id := public.publish_generated_content_draft(generated_id);
  if not exists (select 1 from public.content_items where id = lesson_id and status = 'draft') then
    raise exception 'Approval must create a draft lesson, not learner-visible content';
  end if;
  select id into verified_id from public.question_bank where source_content_id = lesson_id order by question_code limit 1;
  select id into rejected_id from public.question_bank where source_content_id = lesson_id order by question_code offset 1 limit 1;
  perform public.review_question_bank_item(verified_id, 'Which context should be included?',
    '["Audience","Color","Font","Device"]', 0,
    'The audience provides the relevant context.', 1, 'concept', 'verify');
  perform public.review_question_bank_item(rejected_id, '', '[]', 0, '', 1, 'concept', 'reject');

  update public.content_items set status = 'published' where id = lesson_id;
  if not exists (select 1 from public.question_bank where id = verified_id and status = 'published') then
    raise exception 'Verified question did not publish with the lesson';
  end if;
  update public.content_items set status = 'draft' where id = lesson_id;
  if exists (select 1 from public.learning_objectives where content_item_id = lesson_id and status = 'published')
      or exists (select 1 from public.question_bank where source_content_id = lesson_id and status = 'published') then
    raise exception 'Returning a lesson to draft must unpublish its children';
  end if;
  update public.content_items set status = 'archived' where id = lesson_id;
  update public.content_items set status = 'published' where id = lesson_id;
  if not exists (select 1 from public.learning_objectives where content_item_id = lesson_id and status = 'published')
      or not exists (select 1 from public.question_bank where id = verified_id and status = 'published') then
    raise exception 'Republishing a lesson must restore its approved children';
  end if;
  if not exists (select 1 from public.question_bank where id = rejected_id and status = 'archived' and validation_status = 'rejected') then
    raise exception 'Rejected questions must stay archived';
  end if;
end;
$$;

-- A separate authenticated identity without administrator privileges cannot
-- see drafts/settings or approve generated material.
select set_config('request.jwt.claim.sub', 'a843e9b4-50a8-4861-baad-e7101398d716', true);
do $$
begin
  if exists (select 1 from public.content_items where status <> 'published') then
    raise exception 'Non-admin identity can read unpublished content';
  end if;
  if exists (select 1 from public.automation_settings) then
    raise exception 'Non-admin identity can read automation settings';
  end if;
  begin
    insert into public.content_items (id, content_type, title, description)
      values ('__forbidden_content_smoke__', 'module', 'Forbidden', 'Rollback fixture');
    raise exception 'Non-admin mutation unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.publish_generated_content_draft('691b5077-7783-42af-9a89-a52882d4e623');
    raise exception 'Non-admin approval unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select 'PASS: CRUD, version history, AI draft approval, question review, publication lifecycle, and non-admin denial. All fixtures rolled back.' as result;
rollback;
