import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

test('Verify unlimited policy persists, reports accurate availability and remains admin-only', {
  skip: !process.env.PGLITE_MODULE,
}, async () => {
  const { PGlite } = await import(pathToFileURL(process.env.PGLITE_MODULE).href);
  const db = new PGlite();
  try {
    const schema = readFileSync(new URL('../supabase/schema.sql', import.meta.url), 'utf8').replaceAll('\r\n', '\n');
    const start = schema.indexOf('CREATE TABLE IF NOT EXISTS "public"."verification_automation_settings"');
    // Start with the pre-migration table, then execute the actual new migration.
    const table = schema.slice(start, schema.indexOf('\n);', start) + 3)
      .replace('    "unlimited_generation" boolean DEFAULT false NOT NULL,\n', '')
      .replace('("manual_cooldown_minutes" >= 0)', '("manual_cooldown_minutes" >= 1)');
    await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
      CREATE FUNCTION public.phase9_is_admin() RETURNS boolean LANGUAGE sql AS
      $$ SELECT coalesce(current_setting('test.is_admin',true),'false') = 'true' $$;
      CREATE TABLE public.verification_case_drafts(status text, created_at timestamptz DEFAULT now());
      CREATE TABLE public.verification_groq_requests(requested_at timestamptz DEFAULT now());`);
    await db.exec(table);
    await db.exec(`INSERT INTO public.verification_automation_settings(id,last_manual_success_at) VALUES(1,now());
      INSERT INTO public.verification_case_drafts(status) SELECT 'draft' FROM generate_series(1,100);
      INSERT INTO public.verification_groq_requests SELECT now() FROM generate_series(1,100);`);
    const migration = readFileSync(new URL('../supabase/migrations/20261020040000_verify_unlimited_generation.sql', import.meta.url), 'utf8');
    await db.exec(migration);
    const sourceStart = schema.indexOf('CREATE TABLE IF NOT EXISTS "public"."content_sources"');
    await db.exec(schema.slice(sourceStart, schema.indexOf('\n);', sourceStart) + 3));
    await db.exec('ALTER TABLE public.content_sources ADD UNIQUE (source_url), ADD UNIQUE(name)');
    const sourceMigration = readFileSync(new URL('../supabase/migrations/20261020050000_learning_prompt_strategy_source.sql', import.meta.url), 'utf8');
    await db.exec(sourceMigration);
    assert.equal((await db.query('SELECT count(*)::integer AS count FROM public.content_sources')).rows[0].count, 1);
    await db.exec('UPDATE public.content_sources SET enabled = false');
    await db.exec(sourceMigration);
    assert.equal((await db.query('SELECT enabled FROM public.content_sources')).rows[0].enabled, false);
    const query = async sql => (await db.query(sql)).rows[0];
    assert.equal((await query('SELECT unlimited_generation FROM public.verification_automation_settings')).unlimited_generation, false);
    await assert.rejects(db.query('SELECT public.update_verification_automation_settings(true,6,2,4,40,80,40,0,true)'), /Administrator access/);
    await db.exec("SET test.is_admin = 'true'; SET ROLE authenticated;");
    await db.query('SELECT public.update_verification_automation_settings(true,6,2,4,40,80,40,0,true)');
    const unlimited = (await query('SELECT public.get_verification_automation_overview() AS value')).value;
    assert.equal(unlimited.settings.unlimited_generation, true);
    assert.equal(unlimited.settings.manual_cooldown_minutes, 0);
    assert.equal(unlimited.remaining_today, null);
    assert.equal(unlimited.groq_requests_remaining, null);
    assert.equal(unlimited.cooldown_remaining_minutes, 0);
    // Original eight-argument callers still resolve and restore capped settings.
    await db.query('SELECT public.update_verification_automation_settings(true,6,2,4,40,80,40,15)');
    const limited = (await query('SELECT public.get_verification_automation_overview() AS value')).value;
    assert.equal(limited.settings.unlimited_generation, false);
    assert.equal(limited.remaining_today, 0);
    assert.equal(limited.groq_requests_remaining, 0);
    assert.ok(limited.cooldown_remaining_minutes > 0);
    await db.exec('RESET ROLE; SET ROLE anon;');
    await assert.rejects(db.query('SELECT public.update_verification_automation_settings(true,6,2,4,40,80,40,0,true)'), /permission denied/);
    await db.exec('RESET ROLE;');
    // Migration can be reapplied without creating ambiguous overloads.
    await db.exec(migration);
  } finally {
    await db.close();
  }
});
