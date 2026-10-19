# AI content generation fix — 19 October 2026

## Scope and status

Implemented locally. No deployment, migration execution, commit, push, or paid AI calls.
Only the content-generation Edge Function, its runtime helpers, focused tests,
and a generated-content objective mapping migration changed. No Flutter product
files, themes, navigation, learner scoring, or other Edge Functions changed.

## Confirmed causes and trace

The frontend already sends the complete `focus_topics` / `focus_skills` arrays.
Identifiers match the server enums. The defect was downstream of the picker.

1. Learning discovery previously required a narrow AI substring list. An article
   saying **AI** plus audience/context/output-format terminology could be rejected
   before topic matching. “Prompt engineering” was itself an accepted AI anchor,
   giving that topic an advantage. The regression fixtures reproduce this mismatch.
2. Learning assigned each candidate to `focusTopics.find(...)`: the first matching
   selected topic. Sorting and truncating afterward could crowd out other topics.
   One source mentioning several topics was never a guarantee of coverage.
3. Discovery used only feed headline/summary or anchor label. There was no bounded
   fallback to the administrator-enabled source page and its actual topical links.
   The small signal vocabulary missed some legitimate synonyms.
4. Verify read only a small, relevance-sorted Awareness pool, discovered within
   21 days. It assigned a skill using `stats.created % focusSkills.length`.
   A failure before saving could repeatedly target the same skill. Sources were
   not matched to that skill before calling the AI.
5. Duplicate checks intentionally exclude previously used sources. A small pool
   can therefore produce zero new drafts despite containing topical articles.
6. Zero-output runs could report `success: true`, and multi-topic responses did
   not identify uncovered topics. Existing daily/queue/per-run limits can also
   be smaller than the number of selected topics.

These are confirmed code defects and constraints, not a diagnosis of the deployed
database's precise source inventory. No live logs, provider credentials, or
production topic-by-topic generation were tested. The exact source availability
and provider failure responsible for any particular live request remain unknown.

The current trace is: complete selection → authorized request validation → bounded
source discovery/fallback → AI relevance and topic relevance → rotating round-robin
candidate allocation → full-source topic check → topic-enforced AI output → existing
draft validation → draft persistence → per-topic outcome in the existing admin
generation message. Approval/rejection RPCs remain separate.

## Changes

- Learning now uses the existing boundary-aware AI relevance detector used by Verify.
  It still requires independent topic relevance, including on fetched article text.
- Added context/specificity synonyms and verification-specific source signals.
  A generic mention of “source material” does not qualify as source verification.
- Missing topics fall back to up to four enabled trusted source roots, with two
  roots processed concurrently and at most one actual same-host topical link per
  root. Fallback fetch timeout is eight seconds. No search service, fabricated
  URL, hardcoded article, or new paid dependency was introduced.
- Verify considers up to 96 active AI-relevant Awareness rows before topic matching.
  The blanket 21-day discovery cutoff was removed so evergreen material remains
  eligible. Prompts include the known publication date and prohibit presenting
  historical events as current news. Missing skills also use the trusted-page fallback.
- Candidate allocation rotates its starting topic and distributes distinct sources
  across selected topics. Canonical URL variants and matching normalized syndicated
  headlines are deduplicated. Existing database duplicate protection is preserved.
- A failed topic does not repeatedly occupy the next skill assignment. Successful
  draft saves survive failures elsewhere. Sources and output topic IDs are checked
  before saving. No generated draft is automatically published.
- Saved item count stays within existing per-run/daily/monthly/queue limits.
  AI attempts are capped per run (roughly twice the draft budget, minimum three,
  maximum twenty), and each article can try at most three models. Verify also
  retains monthly usage reservation before each AI call.
- Every explicit selection gets `created`, `no_matching_sources`,
  `no_new_valid_draft`, or `deferred_by_limit`. Messages include those outcomes;
  incomplete coverage and zero output cannot claim full success.
- Legacy Verify requests with no explicit selection retain automatic relevant
  skill selection. Existing frontend handling of partial/error results is reused.
- Replaced a generic `ReturnType<typeof createClient>` annotation with the SDK's
  `SupabaseClient` type to pass current Edge type checking; runtime authorization
  behavior is unchanged.

## Fourth objective

Confirmed in `publish_generated_content_draft(uuid)`: the question-objective offset
was capped at index two despite generation requiring four objectives. The new
migration uses the actual objective-array length. For five questions and four
objectives, offsets become `0, 1, 2, 3, 3`.

The migration changes only that expression in the existing function, preserves
its admin checks/permissions and approval behavior, rejects an unexpected function
definition, and supports reruns. It does not rewrite already published records.
Its SQL contract was checked statically; PostgreSQL execution is still required.

## Topic support matrix

“Pass” below means the actual Edge handler ran against mocked database, source,
and AI responses and saved a validated draft with the correct topic. It does not
mean live providers have a suitable unused source for every topic today.

| Learning topic | Relevant signals / discovery | Offline result | Production |
|---|---|---|---|
| Prompt clarity | prompts, clear/ambiguous instructions | Pass | Not live-tested |
| Context | context, audience, background/relevant information | Pass | Not live-tested |
| Specificity | constraints, output/response formats, acceptance criteria | Pass | Not live-tested |
| Responsible AI use | privacy, fairness, integrity, responsible/ethical AI | Pass | Not live-tested |
| Verification | fact checking, citations, hallucinations, evidence quality | Pass | Not live-tested |

| Verification skill | Relevant signals / discovery | Offline result | Production |
|---|---|---|---|
| Source verification | source credibility/reliability, authorship, original sources | Pass | Not live-tested |
| Claim verification | claims, fact checking, misinformation, hallucinations | Pass | Not live-tested |
| Media provenance | image/video/audio/media, provenance, watermarks | Pass | Not live-tested |
| Manipulation detection | altered/edited media, deepfakes, synthetic/AI-generated media | Pass | Not live-tested |
| Citation verification | citations, references, cited material | Pass | Not live-tested |
| Uncertainty judgment | uncertainty, evidence, confidence, limitations | Pass | Not live-tested |

Both matrices also have two-topic, three-topic, all-topic, partial-failure and
count-limit fixture coverage. If five/six selected topics exceed the configured
draft allowance, all are planned/reported but only the permitted number can be
generated. Increase the existing limits deliberately or use separate runs to
obtain a draft for every topic; the function does not bypass those limits.

## Validation

- 91 Node tests passed across `automation_generation`, `automation_focus`, and
  `automation_quality`: each topic, single/multiple/all selections, correct IDs,
  count caps, missing sources, unrelated article bodies, duplicates, empty/broken
  primary discovery, trusted-page fallback, provider timeout/429, invalid output,
  persistence failure, partial saves, and legacy no-picker compatibility.
- The actual Edge handler is executed using Node TypeScript stripping and offline
  adapters. RSS parsing itself is mocked; live feeds/providers/Supabase are not tested.
- 43 targeted Flutter tests passed: focus validation/models, repository request and
  response contracts, generation picker, mobile/desktop UI, existing bank paging.
- 40 existing static wiring/lock/quality checks passed (19 + 10 + 11).
- `flutter analyze --no-pub`: no issues. Edge Deno type check passed.
- No broad full-system test run; no live database or AI generation test.

## Files changed

1. `supabase/functions/content-automation/index.ts`
2. `supabase/functions/content-automation/focus.mjs`
3. `supabase/functions/content-automation/planning.mjs` (new)
4. `supabase/functions/content-automation/discovery.mjs` (new)
5. `supabase/migrations/20261019120000_generated_objective_mapping.sql` (new)
6. `tests/automation_generation.test.mjs` (new)
7. `tests/verify_admin_focus_contract.cjs`
8. This report.

## Remaining limits and manual deployment

Credible unused sources still have to exist. Disabled sources, blocked sites,
JavaScript-only pages, stale snapshots, a provider outage, limited candidate pools,
duplicate sources, and AI validation failures can prevent generation. The fallback
is bounded, not a full crawl or internet search. Keyword relevance cannot prove
factual correctness or eliminate semantic near-duplicates; human review remains
necessary. Generated evidence/verdicts have not been independently fact-checked
by these fixture tests. The separate incomplete Verify review UI remains a concern.

One new migration and an Edge redeployment are required. From the repo root,
after reviewing the changes and providing the intended project/database values:

```powershell
# Assumes psql is installed and SUPABASE_DB_URL contains the intended DB connection.
psql "$env:SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "supabase/migrations/20261019120000_generated_objective_mapping.sql"
npx supabase functions deploy content-automation --project-ref "YOUR_PROJECT_REF"
```

These commands were NOT executed. The deploy flags were verified using CLI help.
This does not apply the earlier, separately pending bank-approval timestamp migration.
No new secrets, schema columns, or frontend deployment are needed for this fix.

Smallest optional live smoke test after deployment: one lesson and one Verify
draft, selecting the previously failing topic/skill with a known unused trusted
source. Keep publication off; inspect source URL, relevance, payload, queue entry,
and reported counters. That two-draft test would still not prove all production
topics; validate additional topics individually when source coverage allows.

## Separate source-level findings — not fixed in this task

| Finding | Classification | Evidence / implication |
|---|---|---|
| AI usage refund authorization | Confirmed security/integrity concern | `refund_prompt_coach_ai_use()` is executable by authenticated users and decrements their usage without a server-proven failed AI request. Authentication alone does not authorize a refund. |
| Client-supplied legacy correctness | Confirmed security/integrity concern | `record_adaptive_attempt()` validates identity/item/topic but persists caller-supplied `p_is_correct` without grading an answer. |
| Diagnostic score validation | Confirmed security/integrity concern | `record_adaptive_diagnostic()` clamps but stores supplied score/correct/total without reconciling them with answers. Mastery rebuilding does not make stored assessment metrics trustworthy. |
| Quick Check answer-key exposure | Confirmed security/integrity concern | `start_verification_quick_check()` returns `correct_decision` and `explanation` in learner session data before answering. |
| Verification draft review completeness | Confirmed security/integrity concern (review quality) | `_DraftCard` displays title, labels, summary and date, then Approve/Reject; it does not expose the full evidence/actions/keyed verdict/source material required by the approval confirmation. |

Evidence was checked in the repository schema, migrations and current Dart
source. Deployment state/exploitability was not tested. These findings do not
assert that ordinary learner use is visibly broken. They need separately approved
work; none of their implementations were changed here.
