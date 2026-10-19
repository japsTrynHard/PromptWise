import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createLessonRequester,
  lessonSchema,
  responseFormat,
  sectionRepairSchema,
} from '../supabase/functions/content-automation/lesson_requests.mjs';

const options = (model) => ({
  model,
  schema: lessonSchema('context'),
  name: 'learning_lesson',
  messages: [{ role: 'user', content: 'Educational JSON lesson' }],
});
function client(
  fetcher,
  models = ['openai/gpt-oss-20b', 'openai/gpt-oss-120b'],
  remaining = 20,
) {
  const budget = { remaining, used: 0 }, waits = [];
  return {
    budget,
    models,
    waits,
    ...createLessonRequester({
      apiKey: 'fixture',
      models,
      budget,
      deadline: Date.now() + 120000,
      fetcher,
      wait: async (ms) => {
        waits.push(ms);
      },
    }),
  };
}
test('GPT-OSS uses strict closed JSON schemas; legacy text models retain JSON object mode', () => {
  const schema = lessonSchema('context');
  assert.equal(
    responseFormat('openai/gpt-oss-20b', schema, 'lesson').json_schema.strict,
    true,
  );
  assert.equal(
    responseFormat('openai/gpt-oss-120b', schema, 'lesson').type,
    'json_schema',
  );
  assert.equal(
    responseFormat('llama-3.3-70b-versatile', schema, 'lesson').type,
    'json_object',
  );
  function check(value) {
    if (!value || typeof value !== 'object') return;
    if (value.type === 'object') {
      assert.equal(value.additionalProperties, false);
      assert.deepEqual(value.required, Object.keys(value.properties));
    }
    for (const child of Object.values(value)) {
      if (typeof child === 'object') {
        if (Array.isArray(child)) child.forEach(check);
        else check(child);
      }
    }
  }
  check(schema);
  check(sectionRepairSchema([1, 4]));
  assert.deepEqual(schema.properties.topic_id.enum, ['context']);
});
test('five concurrent topic calls are serialized and all are delivered', async () => {
  let active = 0, maximum = 0, calls = 0;
  const c = client(async () => {
    calls++;
    active++;
    maximum = Math.max(active, maximum);
    await new Promise((r) => setTimeout(r, 1));
    active--;
    return Response.json({ ok: true });
  });
  await Promise.all(
    Array.from({ length: 5 }, () => c.request(options(c.models[0]))),
  );
  assert.equal(calls, 5);
  assert.equal(maximum, 1);
  assert.equal(c.budget.used, 5);
});
test('json_validate_failed does not disable a usable model for other topics or repairs', async () => {
  let calls = 0;
  const c = client(async () =>
    ++calls === 1
      ? Response.json({
        error: {
          code: 'json_validate_failed',
          failed_generation: "I'm sorry, but I can't comply with that request.",
        },
      }, { status: 400 })
      : Response.json({ ok: true })
  );
  await assert.rejects(c.request(options(c.models[0])), /HTTP 400/);
  assert.equal(c.models.length, 2);
  assert.equal((await c.request(options(c.models[0]))).status, 200);
});
test('transient 429 honors retry-after once without disabling a recovered model', async () => {
  let calls = 0;
  const c = client(async () =>
    ++calls === 1
      ? new Response('Rate limit', {
        status: 429,
        headers: { 'retry-after': '2' },
      })
      : Response.json({ ok: true })
  );
  await c.request(options(c.models[0]));
  assert.deepEqual(c.waits, [2250]);
  assert.equal(c.models.length, 2);
  assert.equal(c.budget.used, 2);
});
test('long 429 defers the remaining work and avoids repeated calls from queued topics', async () => {
  let calls = 0;
  const models = ['openai/gpt-oss-20b', 'openai/gpt-oss-120b'];
  const budget = { remaining: 20, used: 0 };
  const c = createLessonRequester({
    apiKey: 'fixture',
    models,
    budget,
    deadline: Date.now() + 120000,
    fetcher: async () => {
      calls++;
      return new Response('Rate limit reached', {
        status: 429,
        headers: { 'retry-after': '60' },
      });
    },
  });
  await Promise.allSettled(
    Array.from({ length: 5 }, () => c.request(options('openai/gpt-oss-20b'))),
  );
  assert.equal(calls, 1);
  assert.equal(budget.used, 1);
  assert.equal(c.retryAfterSeconds, 60);
  assert.deepEqual(models, ['openai/gpt-oss-120b']);
});
test('a daily quota does not advertise an automatic short retry', async () => {
  const c = createLessonRequester({
    apiKey: 'fixture',
    models: ['model'],
    budget: { remaining: 4, used: 0 },
    deadline: Date.now() + 120000,
    fetcher: async () =>
      new Response('Daily tokens per day (TPD) limit reached', { status: 429 }),
  });
  await assert.rejects(c.request(options('model')), /rate limit/);
  assert.equal(c.retryAfterSeconds, null);
});
test('empty request budget never invokes the provider', async () => {
  const c = client(
    async () => {
      throw Error('should not fetch');
    },
    ['model'],
    0,
  );
  await assert.rejects(c.request(options('model')), /request limit/);
});
