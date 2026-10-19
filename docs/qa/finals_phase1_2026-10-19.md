# Finals QA: Phase 1 (2026-10-19)

## Scope and verdict

Acceptance reference: `C:/Users/ligay/Downloads/ACTIVITY 1 – Finals Test Scenario and Test Cases (1).pdf`, 53 pages, 10 scenarios and 100 paired cases. Document instructions are acceptance criteria, not evidence of execution or authorization to change remote data. Authentication is excluded by the specification.

Phase 1 deliberately covers TS-08 Image Comparison locally plus project-wide static analysis. This is NOT a whole-system or live acceptance pass. Existing uncommitted application changes were preserved. No paid AI/provider calls or remote database changes were made.

## Executed evidence

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub` | No issues found (before the assertion-only edit) |
| `flutter test test/paired_image_cases_test.dart test/image_comparison_controller_test.dart test/image_round_readiness_test.dart --reporter expanded` | Initially 8 passed, 1 failed; after correction, 9 passed |
| `flutter test test/paired_service_cases_test.dart --name TC_IMAGE --reporter expanded` | 4 passed |

13 automated tests passed in the final targeted runs. This count is not 13 PDF cases and does not mean all 100 cases passed.

## TS-08 coverage against PDF pages 38-42

| PDF case(s) | Local evidence and remaining limits |
| --- | --- |
| POS/NEG_001 | Widget loads five fixture rounds; real service parser accepts five and rejects zero, two, or duplicate rounds using mock HTTP. Unavailable-service screen retry/back navigation remains untested. |
| POS/NEG_002 | Widget gives zero for one wrong answer, then four points for four correct answers. Ground truth comes from fake responses; actual source labeling remains unverified. |
| POS/NEG_003 | Rapid duplicate taps submit once; controller rejects invalid side/round and concurrent calls. Double Next does not skip a round. Remote idempotency remains unverified. |
| POS/NEG_004 | Source title shown after each answer; two broken image URLs disable choices and offer recovery. Controller/readiness tests cover one failed plus one ready image. The exact one-broken-image widget flow, successful Retry images recovery, and live source metadata remain untested. |
| POS/NEG_005 | Five rounds finish at 4/5; another fixture set starts at round one, zero score, without a prior choice. Actual fresh source selection remains unverified. |

## Problems and solutions

1. **Confirmed test defect, fixed:** `image_round_readiness_test.dart` expected a ready image's later failure to be ignored, contradicting both implementation and the dedicated late-failure safety test. Changed the duplicate-notification test to send `ready` twice and verify readiness remains ready without a failure. Kept the late-failure test and production behavior unchanged. Re-run: 9/9 passed.
2. **Coverage gap:** valid-image widget tests use cached 2x2 fixtures and a fake controller. They verify UI state/scoring, not real content quality, network delivery, backend scoring, or persistence. Solution: use isolated staging with two known five-round sets and verify responses, source evidence, and saved attempts.
3. **Coverage gap:** the broken-image widget test uses Try another set; it checks Retry images exists but never exercises successful retry. Solution: add a focused recovery widget test and unavailable-service navigation test before claiming full TS-08 acceptance.
4. **Documentation drift:** the older paired audit references a differently named 52-page PDF. The supplied finals document is 53 pages. Solution: use this dated report for the current run; do not copy old pass claims into the finals results.
5. **Release uncertainty:** many application files were already modified at the start. A clean analyzer and this targeted run cannot establish that unrelated modules work. Solution: run the remaining bounded phases against the same working tree and record failures separately.

## Remaining phases (not executed)

| Phase | Scope and exit requirement |
| --- | --- |
| 2 | TS-01 Lessons and TS-03 Knowledge Checks: search/filter, completion failure/retry, linked practice, scoring and best-score persistence. Fix confirmed failures and rerun affected tests. |
| 3 | TS-04 Survey/Diagnostic and TS-05 Adaptive: validation, duplicate completion, recommendations and refresh failure. |
| 4 | TS-02 Coach, TS-06 Awareness and TS-07 Quick Check: deterministic local tests first; failures, stale requests and recovery included. |
| 5 | TS-09 Admin Content and TS-10 Automation: validation, publication/rejection, temporary vs saved focus, quotas and concurrency. Local tests first; live destructive/error fixtures only in staging. |
| 6 | Close TS-08 gaps; full local regression and browser/device walkthrough; staging persistence/RLS/migrations/provider checks for all modules. Record unexecuted cases as pending, never passed. Minimize live AI calls using known fixtures and only the minimum provider smoke checks. |

Phase 1 exit: local baseline and targeted image checks pass after one test correction; live acceptance and the rest of the system remain pending.
