# Learning generation and Studio loading feedback — 20 October 2026

Implemented locally; production generation has not been exercised. The user
reported that Verify works and Learning failed with an Edge Function message.
The original Learning error/log was unavailable, so its exact cause is unconfirmed.

## Changes

- Learning Automation settings now saves a manual cooldown from 0–1440 minutes.
  Zero disables the manual wait even when a recent run exists. The existing value
  remains 30 until the administrator changes it. Daily, monthly, queue, provider
  and active-run limits still apply; zero does not mean unlimited generation.
- Learning now uses “Choose topics to generate”, retaining its existing topic
  picker and selected-topic validation.
- Learning source discovery checks at most three sources concurrently with an
  eight-second fetch limit and a 24-second discovery budget. Trusted-page fallback
  gets a separate bounded window; fetched fallback content is reused.
- A 100-second Learning processing budget stops subsequent requests and preserves
  saved drafts. It does not guarantee a timeout-free run if the database stalls.
- Lesson JSON examples now show the required four objectives, six sections and
  five questions. Generation has an explicit output limit, detects truncation,
  passes validation feedback to the next model, and tries another text model
  after a transport failure. Existing validation remains enforced.
- Source/article errors include bounded samples in the returned diagnostic.
  Article persistence errors are isolated instead of aborting the entire batch.
- Confirmed UI bug: a generation error containing “Edge Function logs” was mapped
  to “function not deployed/could not be reached.” Generation errors now retain
  their actual cause instead of that misleading message.
- Both Studios show a spinning button icon and animated indeterminate progress
  bar while the request runs. Source preparation has a separate status. Indicators
  stop after completion/failure; review/settings mutations do not pretend to be
  generation. Colors use the existing theme palette. No fabricated percentage.

## Validation

- 103 Node/PostgreSQL tests pass, with no skipped tests in this run. These execute
  the real Edge handler against offline provider/database adapters, plus the real
  cooldown migration in PGlite. Coverage includes all topics, partial saves,
  timeout/model fallback, source relevance, persistence failure, time-budget
  exhaustion, zero cooldown, and positive cooldown enforcement.
- 60 targeted Flutter tests pass across model, repository, controller and Studio
  UX suites. They cover saving zero during an existing cooldown, rejecting invalid
  values, request payloads, topic selection, preserving provider diagnostics,
  and animations persisting through a pending request then disappearing.
- Flutter analysis: no issues. Content automation Deno type check: passed.
- No paid AI calls, live source fetches, production database writes or deployments.

## Deployment and demo

From the linked repository, apply the new migration and deploy the function:

```powershell
npx --yes supabase@latest db push --linked --dry-run --skip-vault
npx --yes supabase@latest db push --linked --skip-vault
npx --yes supabase@latest functions deploy content-automation --use-api
```

Deploy the updated Flutter admin web app through the existing Vercel workflow.
The database migration must be applied before saving a zero cooldown. After the
new frontend loads, open Learning Studio → Automation settings → Manual generation
cooldown, set 0 and save. Generation should unlock without waiting for the old
30-minute timer. Select one topic with an unused enabled trusted source, generate,
inspect the draft/source, then retry with another unused source. Check animation
and result handling in Verify as well. Do not publish unreviewed drafts.

Provider quotas, exhausted local caps, unavailable/irrelevant sources, and duplicate
sources can still block a new draft. A live post-deployment generation is required
before calling production Learning generation verified.
