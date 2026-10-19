// Learning-only request coordination; Verification keeps its working client.
const STRICT_MODELS = new Set(['openai/gpt-oss-20b', 'openai/gpt-oss-120b']);
const object = (properties) => ({
  type: 'object',
  properties,
  required: Object.keys(properties),
  additionalProperties: false,
});
const string = { type: 'string' };
const strings = { type: 'array', items: string };
const level = { type: 'integer', enum: [1, 2, 3, 4, 5] };
const question = object({
  question_type: {
    type: 'string',
    enum: ['concept', 'scenario', 'best_response', 'evaluation'],
  },
  stem: string,
  options: strings,
  correct_index: { type: 'integer', enum: [0, 1, 2, 3] },
  explanation: string,
  difficulty: level,
});
const verification = object({
  title: string,
  summary: string,
  case_type: string,
  subskill: string,
  difficulty: level,
  scenario: string,
  claim_text: string,
  media_type: string,
  media_description: string,
  evidence: {
    type: 'array',
    items: object({
      code: string,
      label: string,
      detail: string,
      type: string,
      is_key: { type: 'boolean' },
    }),
  },
  actions: {
    type: 'array',
    items: object({
      code: string,
      label: string,
      description: string,
      useful: { type: 'boolean' },
      reveals_evidence_codes: strings,
    }),
  },
  source_options: strings,
  best_source_index: { type: 'integer' },
  correct_decision: string,
  expected_confidence: string,
  explanation: string,
  learning_point: string,
});

export function lessonSchema(topic) {
  return object({
    title: string,
    summary: string,
    topic_id: { type: 'string', enum: [topic] },
    target_level: level,
    objectives: {
      type: 'array',
      description: 'Exactly four learning objectives.',
      items: object({ title: string, description: string }),
    },
    lesson_sections: {
      ...strings,
      description:
        'Exactly six sections. Each has a heading, newline, and at least 120 instructional words; target 160 words.',
    },
    questions: {
      type: 'array',
      description: 'Exactly five questions.',
      items: question,
    },
    verification_case: { anyOf: [{ type: 'null' }, verification] },
  });
}

export function sectionRepairSchema(indices) {
  return object({
    sections: {
      type: 'array',
      items: object({
        index: { type: 'integer', enum: indices },
        section: string,
      }),
    },
  });
}

export function responseFormat(model, schema, name) {
  return STRICT_MODELS.has(model)
    ? { type: 'json_schema', json_schema: { name, strict: true, schema } }
    : { type: 'json_object' };
}

function retryDelay(response, detail) {
  const header = response.headers.get('retry-after');
  if (header && Number.isFinite(Number(header))) {
    return Math.max(0, Number(header) * 1000);
  }
  const message = detail.match(
    /try again in\s+([\d.]+)\s*(ms|s|seconds?|m|minutes?)/i,
  );
  if (!message) return null;
  return Number(message[1]) *
    (message[2] === 'ms' ? 1 : /^m/i.test(message[2]) ? 60000 : 1000);
}

// Queue AI requests, not the source checks. This prevents a five-topic batch
// from sending five initial requests plus five repairs at the same instant.
export function createLessonRequester(
  {
    apiKey,
    models,
    budget,
    deadline,
    fetcher = (...args) => fetch(...args),
    now = () => Date.now(),
    wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  },
) {
  let tail = Promise.resolve();
  let waited = 0;
  let retryAfterSeconds = null;
  const request = async (
    { model, messages, schema, name, maxTokens = 4096 },
  ) => {
    if (!models.includes(model)) {
      throw new Error(`${model}: unavailable for the rest of this run.`);
    }
    for (let attempt = 0; attempt < 2; attempt++) {
      const remaining = deadline - now() - 2500;
      if (remaining < 1000) {
        retryAfterSeconds = retryAfterSeconds ?? 1;
        throw new Error(
          'Learning generation time budget reached. Saved drafts are preserved.',
        );
      }
      if (budget.remaining <= 0) {
        throw new Error('Per-run AI request limit reached.');
      }
      budget.remaining--;
      budget.used++;
      const response = await fetcher(
        'https://api.groq.com/openai/v1/chat/completions',
        {
          method: 'POST',
          signal: AbortSignal.timeout(Math.min(25000, remaining)),
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model,
            temperature: 0.2,
            max_completion_tokens: maxTokens,
            ...(model.startsWith('openai/gpt-oss-')
              ? { reasoning_effort: 'low' }
              : {}),
            response_format: responseFormat(model, schema, name),
            messages,
          }),
        },
      );
      if (response.ok) return response;
      const detail = (await response.text()).slice(0, 1200);
      const delay = response.status === 429
        ? retryDelay(response, detail)
        : null;
      // Retry a transient rate limit once using the provider's actual delay.
      // Never wait beyond the shared Edge deadline or a 45-second wait budget.
      if (
        attempt === 0 && delay !== null && delay <= 30000 &&
        waited + delay + 250 <= 45000 &&
        deadline - now() > delay + 6000 && budget.remaining > 0
      ) {
        waited += delay + 250;
        await wait(delay + 250);
        continue;
      }
      // JSON validation/refusal is a response problem, not a missing model.
      const outputError = response.status === 400 &&
        /json_validate_failed|failed to generate json/i.test(detail);
      if (!outputError && [400, 401, 403, 404, 429].includes(response.status)) {
        const index = models.indexOf(model);
        if (index >= 0) models.splice(index, 1);
        if (response.status === 401 || response.status === 403) {
          models.splice(0);
        }
      }
      if (
        response.status === 429 &&
        !/per day|daily|\bTPD\b|\bRPD\b/i.test(detail) &&
        (delay === null || delay <= 90000)
      ) {
        retryAfterSeconds = Math.max(
          retryAfterSeconds ?? 0,
          Math.max(1, Math.ceil((delay ?? 60000) / 1000)),
        );
      }
      if (response.status === 429) {
        throw new Error(
          `${model}: AI provider rate limit${
            delay === null
              ? ''
              : `; retry after about ${Math.ceil(delay / 1000)} seconds`
          }. Saved drafts are preserved.`,
        );
      }
      throw new Error(
        `${model}: HTTP ${response.status}: ${detail.slice(0, 500)}`,
      );
    }
    throw new Error('Learning request could not complete.');
  };
  return {
    get retryAfterSeconds() {
      return retryAfterSeconds;
    },
    request: (options) => {
      const result = tail.then(() => request(options));
      tail = result.then(() => undefined, () => undefined);
      return result;
    },
  };
}
