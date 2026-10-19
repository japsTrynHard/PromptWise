# Finals fixes and commit validation (2026-10-19)

This follow-up supersedes the local coverage gaps in the Phase 1 report where explicitly closed below. It includes the relevant application fixes, tests, scripts, and migrations already uncommitted when the work began.

## Fixed and verified

- Corrected the stale readiness assertion: repeated ready notifications do nothing, while a late image failure disables submission.
- Added a successful Retry images widget flow: restored images enable choices on the same round, retain zero score until an answer, and then score once.
- Added unavailable-source retry and return-to-Verify navigation coverage without fabricated rounds or answers.
- Changed the broken-image widget fixture to exactly one broken image and one valid image; both choices remain disabled. The separate recovery test covers both images initially failing.
- Fixed the required-field admin test to scroll to Create content and settle the layout before tapping. The full suite initially reported 207 passes and this one failure; the corrected suite passes.
- Made the static automation-validation contract accept Dart formatter whitespace and trailing commas without removing its requirement that validation precede the database write.
- Corrected the older audit's acceptance-document reference and marked its historical origin. Keep the Phase 1 report as the record of the earlier run, not the latest coverage state.
- Formatted changed Dart files.

## Validation

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --reporter expanded` | 210 passed, zero failed |
| `flutter test test/paired_image_cases_test.dart --reporter expanded` | 4 passed after the final one-broken-image fixture refinement |
| `node --test tests/automation_focus.test.mjs tests/automation_quality.test.mjs` | 39 passed |
| All four `tests/verify_*.cjs` scripts | 52 static source-contract checks passed |
| `node scripts/qa_static_contracts.mjs` | 8 static checks passed after formatting |
| `node scripts/qa_focus_logic_smoke.mjs` | 17 local smoke checks passed |
| `git diff --check` | No whitespace errors |

Automated test counts are not PDF acceptance-case counts. Static checks do not execute SQL, enforce live RLS, or prove runtime provider behavior. A basic scan of changed files found no recognized private-key/token patterns; generated build output and local environment files remain ignored.

## Remaining verification limits

No paid AI calls, provider smoke tests, remote migrations, or remote data mutations were performed. Real image/source availability, actual ground truth, remote persistence, database constraints/RLS/concurrency, and browser/device media behavior remain pending isolated staging verification. The two included migrations and rollback-based SQL regression fixture are committed source, not a claim of deployment.

Known reproducible local failures from this run have been resolved. Full-system live acceptance remains unverified; the remaining phased staging work from the Phase 1 report still applies.
