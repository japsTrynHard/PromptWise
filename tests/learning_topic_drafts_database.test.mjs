import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

test('Learning deduplication allows different topics per article and prevents repeated topics', {
  skip: !process.env.PGLITE_MODULE,
}, async () => {
  const { PGlite } = await import(pathToFileURL(process.env.PGLITE_MODULE).href);
  const db = new PGlite();
  try {
    await db.exec(`CREATE TABLE public.generated_content_drafts (
      article_id uuid, topic_id text, status text DEFAULT 'draft');
      CREATE UNIQUE INDEX uq_generated_draft_article ON public.generated_content_drafts(article_id)
      WHERE article_id IS NOT NULL AND status <> 'rejected';`);
    const migration = readFileSync(new URL('../supabase/migrations/20261020060000_learning_topic_drafts.sql', import.meta.url), 'utf8');
    await db.exec(migration);
    const article = '11111111-1111-4111-8111-111111111111';
    const insert = topic => db.exec(`INSERT INTO public.generated_content_drafts(article_id,topic_id) VALUES('${article}','${topic}')`);
    await insert('context');
    await insert('specificity');
    await assert.rejects(insert('context'), /duplicate key/);
    await db.exec(`UPDATE public.generated_content_drafts SET status='rejected' WHERE topic_id='context'`);
    await insert('context');
    await db.exec(`UPDATE public.generated_content_drafts SET status='archived' WHERE topic_id='specificity'`);
    await assert.rejects(insert('specificity'), /duplicate key/);
    await db.exec(migration);
    assert.equal((await db.query('SELECT count(*)::integer AS count FROM public.generated_content_drafts')).rows[0].count, 3);
  } finally { await db.close(); }
});
