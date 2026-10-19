import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

test('Learning cooldown migration preserves 30, accepts 0, rejects invalid waits', {
  skip: !process.env.PGLITE_MODULE,
}, async () => {
  const { PGlite } = await import(pathToFileURL(process.env.PGLITE_MODULE).href);
  const db = new PGlite();
  try {
    await db.exec(`CREATE TABLE public.automation_settings (
      id integer PRIMARY KEY, manual_cooldown_minutes integer NOT NULL DEFAULT 30,
      CONSTRAINT automation_settings_manual_cooldown_minutes_check
        CHECK (manual_cooldown_minutes BETWEEN 1 AND 1440));
      INSERT INTO public.automation_settings(id) VALUES(1);`);
    const migration = readFileSync(new URL(
      '../supabase/migrations/20261020030000_learning_manual_cooldown.sql', import.meta.url), 'utf8');
    await db.exec(migration);
    const value = async () => (await db.query('SELECT manual_cooldown_minutes AS value FROM public.automation_settings')).rows[0].value;
    assert.equal(await value(), 30);
    for (const minutes of [0, 1, 1440]) {
      await db.exec(`UPDATE public.automation_settings SET manual_cooldown_minutes = ${minutes}`);
      assert.equal(await value(), minutes);
    }
    for (const minutes of [-1, 1441]) {
      await assert.rejects(db.exec(`UPDATE public.automation_settings SET manual_cooldown_minutes = ${minutes}`), /check constraint/);
    }
    await db.exec(migration);
    assert.equal(await value(), 1440);
  } finally {
    await db.close();
  }
});
