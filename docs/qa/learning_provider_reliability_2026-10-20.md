# Learning generation: JSON failures, provider backoff and existing drafts

20 October 2026. The user's screenshots show two different cases: a multi-topic
run received Groq `json_validate_failed` followed by HTTP 429 during section repair;
a single-topic request found an existing non-rejected source/topic draft.

## Changes

- GPT-OSS Learning requests now use strict JSON schemas, following
  [Groq's Structured Outputs contract](https://console.groq.com/docs/structured-outputs).
  Other text models retain JSON object mode. The existing four-objective,
  six-section, five-question and 120-word minimum checks remain enforced locally.
- Learning source workers can prepare topics concurrently, but their AI calls
  share a serial request queue. Initial generation and repair cannot stampede the
  same provider quota. A response-level JSON failure no longer marks the entire
  model unavailable for unrelated topics or repairs.
- Lesson prompts are shorter and quote relevant source passages as reference data.
  Optional verification companion metadata is still supported. The working
  Verification generation code and question approval flow are unchanged.
- Short-section repair retains the valid outline/questions and can switch to
  another available model after a failed/rate-limited repair. No filler or fake
  lesson is inserted to meet a count.
- Requests honor a short provider `Retry-After` once, within the Edge deadline and
  a shared 45-second in-function wait allowance. Longer temporary rate limits
  return HTTP 202 with pending topic IDs and retry timing. Daily/provider limits
  requiring a long wait do not trigger unlimited automatic retries. See
  [Groq's rate-limit headers](https://console.groq.com/docs/rate-limits).
- The frontend keeps the same generation action running, shows its wait/retry
  status, and continues only the unfinished selected topics. It allows at most
  six passes for a five-topic selection and stops after three passes without new
  saves. This supports all five topics even when only one can be saved per quota
  window. A permanently unavailable provider still ends with an explicit result.
- Automatic continuation stops if the administrator session changes. It cannot
  add topics outside the original selection or re-charge completed topics.
- Existing pending drafts are returned as ready for review, with
  `draftsCreated: 0` and an explicit existing-draft count. Re-selecting their topics
  does not cause a red generation failure or another AI call. Partial batches
  consider these drafts before checking remaining capacity.
- If only approved/previously-used sources remain, a zero-generation result is
  informational instead of a red system error. It still reports zero new drafts
  and does not pretend a new lesson was generated.
- Learning's configured manual cooldown starts after the requested topics finish,
  rather than after a failed/partial attempt. Daily/monthly/queue caps remain.

## Validation

- **163 Node/PostgreSQL tests pass without skips.** Tests cover all 31 nonempty
  topic combinations; the screenshot's JSON-failure/repair-429 sequence; 2/3/5-topic
  deferred continuation; per-topic deduplication; strict-schema contracts; serialized
  requests; Retry-After; daily limits; and existing-draft results with zero AI calls.
- **290 tests pass in the full Flutter suite.** New tests cover one-click
  continuation with request sizes 5→4→3→2→1, bounded waits, no false “drafts saved”
  outcome when none exist, cancellation on account change, rejecting unexpected
  pending topic IDs, and the waiting status alongside the loading animation.
  After the final informational-result adjustment, all 31 repository tests pass.
- Edge Deno type check and Flutter analysis pass; existing focus/lock source checks
  pass. Verification generation was compared to the prior commit and is unchanged.
- No product dependencies, database migrations or secrets were added. No paid AI
  calls or production deployments were performed. A Groq secret is not available
  locally; the actual deployed provider run remains unverified.

## Deployment and smoke check

Deploy the updated function (including `lesson_requests.mjs`):

```powershell
npx --yes supabase@latest functions deploy content-automation --use-api
```

Wait for the updated admin frontend build to deploy as well, then hard-refresh.
The automatic continuation requires this frontend update. The earlier
`20261020060000_learning_topic_drafts.sql` migration must already be applied for
different topics to share an eligible source.

Choose one existing pending topic: expect a ready-for-review message and no new
AI request. Choose two new topics, then all five with sufficient saved allowance:
expect one available draft per topic. A temporary provider limit should keep the
animation active, display its wait, and retry only the missing topics. Keep the
page open while this finishes; it can take minutes under provider limits. If the
page is closed, saved drafts remain and selecting the topics again reuses them.

Unavailable/irrelevant sources, exhausted configured capacity, daily provider
quota, refusals and invalid output can still prevent completion. These conditions
are reported; neither strict JSON nor automatic continuation guarantees content
quality or overrides provider quotas. Drafts still require administrator review.
