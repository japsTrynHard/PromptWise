// Read-only source wiring checks. Live DB, deployed function and AI need smoke tests.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');
const read = path => fs.readFileSync(require('node:path').join(root, path), 'utf8');
const edge = read('supabase/functions/content-automation/index.ts');
const repo = read('lib/data/repositories/content_automation_repository.dart');
const controller = read('lib/presentation/controllers/content_automation_controller.dart');
const ui = read('lib/presentation/screens/admin/admin_learning_studio_screen.dart');
const migration = read('supabase/migrations/20260922060000_content_automation_admin_focus.sql');
const checks = [
  [migration, /ADD COLUMN IF NOT EXISTS focus_topics text\[\] NOT NULL DEFAULT '\{\}'::text\[\]/],
  [migration, /automation_settings_focus_topics_valid/],
  [repo, /last_manual_run_at,focus_topics/],
  [repo, /'focus_topics': focusTopics\.map\(\(topic\) => topic\.id\)\.toList\(\)/],
  [repo, /body: \{\s*'mode': 'manual',\s*'focus_topics': focusTopics/],
  [controller, /runAutomationNow\(\s*focusTopics\s*,?\s*\)/],
  [ui, /Scheduled generation focus areas/],
  [ui, /Choose topics for this run only/],
  [ui, /focusTopics: result\.focusTopics/],
  [edge, /resolveFocusTopics\(\{/],
  [edge, /savedTopics: settings\.focus_topics/],
  [edge, /requestedTopics: body\.focus_topics/],
  [edge, /focusPaused: true/],
  [edge, /const focusedCandidates = dedupeCandidates\(candidates\)/],
  [edge, /\.filter\(\(entry\): entry is \{ candidate: Candidate; focusTopic: string \} =>/],
  [edge, /if \(!textSupportsFocus\(articleText, focusTopic\)\)/],
  [edge, /ADMIN-SELECTED FOCUS AREA \(MANDATORY\): \$\{focusTopic\}/],
  [edge, /enforceDraftFocus\(draft, focusTopic\);[\s\S]*?\.from\('generated_content_drafts'\)/],
  [edge, /target === 'verification'/],
];
checks.forEach(([text, pattern], i) => assert.match(text, pattern, `focus wiring ${i + 1}`));
console.log(`PASS: ${checks.length} static admin focus wiring checks (NOT a live test).`);
