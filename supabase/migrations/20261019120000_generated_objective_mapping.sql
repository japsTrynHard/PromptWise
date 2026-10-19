-- Only future administrator-approved generated lessons are affected.
-- Keep the existing function, permissions and approval checks intact.
BEGIN;
DO $migration$
DECLARE
  definition text := pg_get_functiondef('public.publish_generated_content_draft(uuid)'::regprocedure);
  old_mapping text := 'offset greatest(0, least(v_index - 1, 2))';
  new_mapping text := 'offset greatest(0, least(v_index - 1, jsonb_array_length(v_draft.draft_payload->''objectives'') - 1))';
BEGIN
  IF position(old_mapping IN definition) > 0 THEN
    EXECUTE replace(definition, old_mapping, new_mapping);
  ELSIF position(new_mapping IN definition) = 0 THEN
    RAISE EXCEPTION 'Unexpected generated lesson objective mapping; inspect function before applying.';
  END IF;
END;
$migration$;
COMMIT;
