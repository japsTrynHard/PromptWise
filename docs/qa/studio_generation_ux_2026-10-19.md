# Studio generation UI/UX update

## Reported symptom and diagnosis

The supplied screenshot shows the server's manual generation cooldown, not a topic-validation error. Learning generation uses one shared cooldown across all learning topics. The old UI incorrectly displayed an action error under “Some Learning Studio data could not load,” making a blocked generation look like a broken workspace or topic.

All five learning topic IDs are forwarded independently in repository tests. This verifies request wiring, not the availability of eligible live sources for each topic. No live provider request was made.

## Changes

- Both Studios use the same card-based one-run focus picker: selected count, select all, clear selection, cancel, and an explicit Generate drafts action. Learning exposes five curriculum topics; Verification exposes its six existing verification skills.
- Generation panels use the same hierarchy: icon/header, three responsive metrics, schedule/review badges, availability notice, generation/settings actions, and expandable limit details.
- Design inspiration comes from the welcome/summary cards and dashboard spacing in `flexy/main/index.html` inside the supplied `flexy.zip`. No template scripts, application code, or assets were installed or executed.
- PromptWise theme and palette source files remain unchanged. Components use existing theme colors and spacing. Mobile and desktop renders were inspected; optional preview tests load a local font only when requested through environment variables.
- Learning load failures and action failures have separate state. Generation feedback is compact and dismissible; cooldown no longer claims that workspace data failed to load.
- Learning shows the remaining shared cooldown and disables generation during that period. Both Studios update displayed cooldown availability periodically without polling the server. Server cooldowns, quotas, locking, approval, source eligibility, and publication rules remain in force.
- Verification focus choices are sent as `focus_skills`. The server validates the selected IDs, includes the requested skill in the generation instruction and JSON example, and rejects generated cases with a different skill. Multiple selections are rotated within the existing per-run budget; a selected skill is not a guarantee that a suitable draft exists.
- Verify source preparation prevents overlapping generation flows. After a generation response, the case queue and limits refresh even when a partial/failed run might already have saved drafts or consumed budget.

## Validation

- Full Flutter suite: 228 passed.
- Final affected UI/mobile suite: 15 passed after the last availability-refresh adjustment.
- Node focus/quality suite: 46 passed.
- Analyzer: no issues found.
- Existing static admin, automation-lock, content-quality, orientation, and QA contracts passed.
- TypeScript syntax checked with `node --experimental-strip-types --check`; this is not a Deno type-check or live Edge Function execution.
- Repository tests cover each learning topic and verification skill independently. Widget tests cover Context and Citation verification through the actual Studio pickers at 320px and 1280px, cancellation, clear-all, empty selection, and cooldown feedback. Existing layout tests cover 320px, 360px, and 400px.

## Deployment and remaining limits

No remote function deployment, database migration, provider generation, or remote data mutation was performed. Deploy the updated `content-automation` function together with the Flutter frontend to activate live Verification skill enforcement; an older deployed function does not implement the new `focus_skills` field. Existing learning focus selection does not require a new schema change.

Live source availability and actual generated content for every selected topic still need a bounded staging check. A topic with no suitable trusted source must report that condition rather than generate unrelated material. A cooldown still blocks subsequent requests across topics until it expires; the UI now explains this behavior.
