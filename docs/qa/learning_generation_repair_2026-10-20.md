# Learning generation repair and administrator generation policies

20 October 2026. Follow-up to `learning_generation_fix_2026-10-20.md`.

## Confirmed failure from the screenshot

The function was deployed and reached AI generation. It rejected lesson sections
with 104 and 113 instructional words because the contract requires at least 120.
Its fallback request also asked a model limited to 4096 output tokens for 6000,
causing HTTP 400. A separate FTC source returned 404 and no source matched the
selected Specificity topic. This was not simply an unreachable Edge Function.

## Fixes

- Learning generation and repair requests use a 4096-token output budget instead
  of 6000. GPT-OSS requests explicitly use `reasoning_effort: low`, supported by
  [Groq's reasoning documentation](https://console.groq.com/docs/reasoning).
- Prompts target 160–190 words per section, leaving room above the 120-word hard
  minimum. If the initial lesson contains short sections, one bounded repair
  request expands only those sections using the same trusted source. All repaired
  sections are validated again; no filler is appended and the minimum is unchanged.
- Repair must return exactly the requested section indices once each. It cannot
  replace the questions, change the selected topic or bypass normal validation.
  Repairs count against the existing per-run AI request budget and time budget.
- Enabled page sources can supply their own content directly, even without article
  links. A new migration adds the official
  [Google prompt design guide](https://ai.google.dev/gemini-api/docs/prompting-strategies)
  as an enabled source for prompt clarity/context/specificity. Existing entries and
  an administrator's disabled choice are preserved on migration reapplication.
- Verify settings have an administrator-controlled **Unlimited generation** switch.
  When enabled, the app bypasses daily/monthly draft caps, monthly request caps,
  the review queue cap and manual cooldown. Individual batches, source eligibility,
  duplicate protection, one-active-run locking and provider quotas still apply.
  Limited mode also accepts a 0-minute cooldown. Existing installations stay limited.
- Both settings dialogs have **Restore tipid defaults**. This fills the regular
  numeric defaults; changes apply only after **Save settings**. Verify also turns
  unlimited off. Learning retains the selected schedule topics and enabled state.
- Verify re-reads the server overview after a settings save so restored limits and
  cooldown reflect actual server availability. The UI shows “Unlimited” when active.

## Validation and limits

- 112 Node/PostgreSQL tests pass without skips. Real Edge handler fixtures reproduce
  the screenshot's short sections and a provider enforcing a 4096-token maximum.
  They verify successful targeted repair, rejection of invalid repairs, all-topic
  behavior, capped/unlimited generation, recent-run cooldown behavior and guide-page
  discovery. The actual migrations run in PGlite, including old RPC compatibility,
  admin authorization, availability counts and preserving disabled source choices.
- Full Flutter suite: **283 tests passed**. After a final server-overview refresh
  adjustment, **25 repository/controller tests passed**, including the new regression
  for switching unlimited on and restoring capped settings. Settings and reset flows
  are covered at 320 and 1280 pixels; existing generation animation tests pass.
- Flutter analysis and Edge Deno type check pass. Existing 30 focus/lock source
  contract checks pass. No product dependencies were added.
- Live public-source check: Google guide returned HTTP 200; the first 9000 cleaned
  characters match prompt clarity, context and specificity using the actual topic
  matcher. No live Groq call, production database mutation or deployment was run.

The original FTC URL is administrator data unavailable in the screenshot/repository.
It was not silently replaced or disabled. An unavailable source can still yield a
partial-result notice while other sources produce drafts. Unused eligible sources
and a functioning AI provider remain necessary; unlimited does not bypass provider
quota or authorize duplicate content. Live AI generation is still unverified.

## Deployment

Apply migrations before using the new settings UI, then deploy the function and
the updated admin web build through the existing frontend deployment workflow:

```powershell
npx --yes supabase@latest db push --linked --dry-run --skip-vault
npx --yes supabase@latest db push --linked --skip-vault
npx --yes supabase@latest functions deploy content-automation --use-api
```

New migrations are `20261020040000_verify_unlimited_generation.sql` and
`20261020050000_learning_prompt_strategy_source.sql`. Apply the earlier
`20261020030000_learning_manual_cooldown.sql` too if it is still pending.
No secret change or `promptwise-integrations` redeployment is required.

After deployment, generate a Learning draft for Specificity and Responsible AI use
using eligible unused sources, inspect section depth/source URLs, and keep drafts
unpublished until reviewed. In Verify settings, enable Unlimited generation and
save; then confirm another run is available after completion. Restore tipid defaults
and save to return to normal limits. Verify that prior usage is retained.
