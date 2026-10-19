# Learning Studio: one lesson per selected topic

20 October 2026. The user confirmed that questions and Verification generation
work; this change leaves those flows intact.

Manual Learning generation now targets exactly one lesson for each selected topic,
instead of taking its total from the scheduled batch-size setting. It skips further
candidates once that topic has a saved lesson. Topic work runs concurrently within
the five-topic selection limit and a bounded 120-second processing window, so a slow
first lesson does not consume the entire batch's AI time before others start.

A trusted guide may support several different skills. Planning now permits that
for Learning, rechecks each topic against the actual source text, and deduplicates
by article/topic. The migration changes the corresponding unique index. Concurrent
topics share fetched source text and recover a simultaneous article-insert conflict.
Repeating an existing source/topic draft is still prevented.

Daily/monthly allowance and draft review capacity must fit the entire manual
selection. If they do not, the backend rejects the request before AI calls with an
actionable capacity message. It no longer silently saves fewer lessons merely
because the old scheduled per-run cap was smaller. Source outages, missing relevant
material and provider/validation failures can still produce an explicitly partial
result; no unrelated or fabricated lesson is inserted to meet a count.

Questions retain their existing generation/approval/review behavior. The working
Verification generation branch and its generation function are unchanged. The
shared planner defaults to its original source-exclusion behavior for Verify.

Validation:

- 115 Node/PostgreSQL tests passed without skips, including single/multiple/all
  topic selection, a one-source/many-topic batch, old per-run cap override, one
  lesson despite extra matching sources, insufficient daily allowance with zero
  AI calls, shared-source insertion races, and the real index migration.
- 22 Studio UX tests passed. Flutter analysis and Edge Deno type check passed.
- No live AI call or production deployment was performed.

Deploy the new migration, function and updated frontend:

```powershell
npx --yes supabase@latest db push --linked --skip-vault
npx --yes supabase@latest functions deploy content-automation --use-api
```

New migration: `20261020060000_learning_topic_drafts.sql`. After the updated admin
web deployment loads, select two eligible topics with enough remaining allowance;
expect two lesson drafts with distinct topic IDs and five questions in each payload.
Selecting all five needs at least five available daily/monthly/review slots.
