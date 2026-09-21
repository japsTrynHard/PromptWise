-- Keep approved AI lesson children aligned with the administrator's publication
-- decision, including returning to draft and republishing an archived lesson.
-- Rejected questions never become published through a parent status change.
create or replace function public.sync_phase7_child_publish_status()
returns trigger
language plpgsql
security definer
set search_path to public, pg_temp
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  update public.learning_objectives
  set status = new.status::text, updated_at = now()
  where content_item_id = new.id;

  update public.question_bank
  set status = case
        when validation_status = 'rejected' then 'archived'
        when new.status = 'archived' then 'archived'
        when new.status = 'published' and validation_status = 'verified'
          then 'published'
        else 'draft'
      end,
      updated_at = now()
  where source_content_id = new.id;

  return new;
end;
$$;
