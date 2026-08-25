const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

const jsonHeaders = {
  ...corsHeaders,
  'Content-Type': 'application/json; charset=utf-8',
};

const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

type JsonRecord = Record<string, unknown>;

const GROQ_API = 'https://api.groq.com/openai/v1';
const MAX_PROMPT_LENGTH = 1500;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim() ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')?.trim() ?? '';
  const groqKey = Deno.env.get('GROQ_API_KEY')?.trim() ?? '';
  const authorization = req.headers.get('Authorization')?.trim() ?? '';

  if (!supabaseUrl || !anonKey) {
    return response({ message: 'Prompt Coach backend is not configured.' }, 503);
  }
  if (!authorization.toLowerCase().startsWith('bearer ')) {
    return response({ message: 'Please sign in again to continue.' }, 401);
  }

  const userToken = authorization.slice(7).trim();
  const user = await authenticateUser({ supabaseUrl, anonKey, userToken });
  if (!user) {
    return response({ message: 'Please sign in again to continue.' }, 401);
  }

  try {
    const url = new URL(req.url);
    const method = url.searchParams.get('method') ?? '';

    if (req.method === 'GET' && method === 'coach-status') {
      const usage = await callUserRpc({
        supabaseUrl,
        anonKey,
        userToken,
        functionName: 'prompt_coach_ai_usage_status',
      });

      let available = false;
      if (groqKey) {
        try {
          const models = await resolveGroqModels(groqKey);
          available = models.length > 0;
        } catch (_) {
          available = false;
        }
      }

      return response({ available, usage });
    }

    if (req.method === 'POST' && method === 'coach') {
      if (!groqKey) {
        return response({ message: 'AI Coach is unavailable right now.' }, 503);
      }

      const body = await req.json().catch(() => ({})) as JsonRecord;
      const prompt = textValue(body.prompt).trim();
      if (prompt.length < 10 || prompt.length > MAX_PROMPT_LENGTH) {
        return response(
          { message: 'Enter a prompt between 10 and 1500 characters.' },
          400,
        );
      }

      const privacyIssue = serverPrivacyIssue(prompt);
      if (privacyIssue) {
        return response(
          {
            message:
              `Remove ${privacyIssue} before using AI Coach. Standard Coach can still review the prompt locally.`,
          },
          422,
        );
      }

      let reserved = false;
      let usage: unknown;
      try {
        usage = await callUserRpc({
          supabaseUrl,
          anonKey,
          userToken,
          functionName: 'reserve_prompt_coach_ai_use',
        });
        reserved = true;
      } catch (error) {
        const detail = errorMessage(error);
        if (detail.toLowerCase().includes('daily limit')) {
          return response(
            {
              message:
                'Your daily AI Coach limit is reached. Standard Coach remains unlimited.',
            },
            429,
          );
        }
        throw error;
      }

      try {
        const models = await resolveGroqModels(groqKey);
        const standardAnalysis = asRecord(body.standard_analysis);
        const masteryContext = asRecord(body.mastery_context);
        const learnerRank = textValue(body.learner_rank).trim();
        const guidance = await generateCoachGuidance({
          apiKey: groqKey,
          models,
          prompt,
          standardAnalysis,
          masteryContext,
          learnerRank,
        });

        return response({ guidance, usage });
      } catch (error) {
        if (reserved) {
          await callUserRpc({
            supabaseUrl,
            anonKey,
            userToken,
            functionName: 'refund_prompt_coach_ai_use',
          }).catch(() => null);
        }
        const detail = errorMessage(error);
        console.error('AI Coach generation failed:', detail);
        if (detail.toLowerCase().includes('rate') || detail.includes('429')) {
          return response(
            {
              message:
                'AI Coach is busy right now. Your use was not consumed; Standard Coach remains available.',
            },
            429,
          );
        }
        return response(
          {
            message:
              'AI Coach could not provide guidance. Your use was not consumed; Standard Coach remains available.',
          },
          502,
        );
      }
    }

    return response({ message: 'This action is unavailable.' }, 404);
  } catch (error) {
    console.error('PromptWise integration error:', errorMessage(error));
    return response(
      { message: 'Prompt Coach could not respond. Please try again.' },
      500,
    );
  }
});

async function authenticateUser({
  supabaseUrl,
  anonKey,
  userToken,
}: {
  supabaseUrl: string;
  anonKey: string;
  userToken: string;
}): Promise<JsonRecord | null> {
  const upstream = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      Authorization: `Bearer ${userToken}`,
      apikey: anonKey,
      Accept: 'application/json',
    },
  });
  if (!upstream.ok) return null;
  const data = await upstream.json().catch(() => null);
  return data && typeof data === 'object' ? data as JsonRecord : null;
}

async function callUserRpc({
  supabaseUrl,
  anonKey,
  userToken,
  functionName,
}: {
  supabaseUrl: string;
  anonKey: string;
  userToken: string;
  functionName: string;
}): Promise<unknown> {
  const upstream = await fetch(`${supabaseUrl}/rest/v1/rpc/${functionName}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${userToken}`,
      apikey: anonKey,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: '{}',
  });
  const text = await upstream.text();
  if (!upstream.ok) {
    let message = text;
    try {
      const decoded = JSON.parse(text);
      message = textValue(decoded?.message) || text;
    } catch (_) {
      // Keep raw response text.
    }
    throw new Error(`${functionName} failed (${upstream.status}): ${message}`);
  }
  if (!text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

async function resolveGroqModels(apiKey: string): Promise<string[]> {
  const configured = Deno.env.get('GROQ_MODEL')?.trim();
  if (configured) return [configured];

  const upstream = await fetch(`${GROQ_API}/models`, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });
  if (!upstream.ok) {
    const detail = (await upstream.text()).slice(0, 800);
    throw new Error(`Could not list Groq models (${upstream.status}): ${detail}`);
  }

  const data = await upstream.json() as { data?: Array<{ id?: string }> };
  const ids = (data.data ?? [])
    .map((item) => item.id?.trim() ?? '')
    .filter(Boolean)
    .filter((id) => !/whisper|tts|speech|guard|safeguard|vision|image/i.test(id));

  const preferredOrder = [
    'llama-3.1-8b-instant',
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
    'llama-3.3-70b-versatile',
    'qwen/qwen3.6-27b',
    'groq/compound-mini',
    'groq/compound',
  ];

  const ordered: string[] = [];
  for (const model of preferredOrder) {
    if (ids.includes(model)) ordered.push(model);
  }
  for (const model of ids) {
    if (!ordered.includes(model)) ordered.push(model);
  }
  if (ordered.length === 0) {
    throw new Error('No usable Groq text model is available to this project.');
  }
  return ordered;
}

async function generateCoachGuidance({
  apiKey,
  models,
  prompt,
  standardAnalysis,
  masteryContext,
  learnerRank,
}: {
  apiKey: string;
  models: string[];
  prompt: string;
  standardAnalysis: JsonRecord;
  masteryContext: JsonRecord;
  learnerRank: string;
}): Promise<JsonRecord> {
  const rubricScores = asRecord(standardAnalysis.scores);
  const suggestions = asArray(standardAnalysis.suggestions)
    .map(textValue)
    .filter(Boolean)
    .slice(0, 6);

  const systemPrompt = `You are PromptWise AI Coach, an educational coach for AI literacy and prompt-writing skill.

NON-NEGOTIABLE RULES:
- Coach the learner; do NOT complete the task written in the learner's prompt.
- Do NOT rewrite, improve, or provide a finished replacement prompt.
- Do NOT output a sample "better prompt" or a copyable final prompt.
- Do NOT change or override PromptWise numeric scores. The scores come from a deterministic local rubric.
- Ask questions and explain trade-offs so the learner makes the revision.
- Keep advice appropriate to the learner's stated rank and mastery context.
- If the learner is already strong, increase reasoning complexity instead of adding artificial verbosity.
- Mention privacy, verification, uncertainty, or responsible-use concerns only when relevant.
- Return strict JSON only.

Return exactly this shape:
{
  "summary": "2-3 concise sentences",
  "focus_areas": ["1-3 short skill names"],
  "guiding_questions": ["2-4 questions the learner should answer while revising"],
  "reasoning_notes": ["2-4 short explanations of why a change matters"],
  "next_challenge": "one short revision challenge appropriate to the learner level",
  "responsible_use_reminder": "one short reminder, or an empty string when not needed"
}`;

  const userPrompt = `LEARNER RANK: ${learnerRank || 'Foundation I'}
MASTERY CONTEXT (0-100): ${JSON.stringify(masteryContext)}
PROMPTWISE DETERMINISTIC RUBRIC: ${JSON.stringify(rubricScores)}
PROMPTWISE CURRENT SUGGESTIONS: ${JSON.stringify(suggestions)}

LEARNER PROMPT TO COACH (do not perform its task):
${prompt}`;

  const failures: string[] = [];
  for (const model of models) {
    const upstream = await fetch(`${GROQ_API}/chat/completions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.25,
        max_completion_tokens: 900,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
      }),
    });

    if (!upstream.ok) {
      const detail = (await upstream.text()).slice(0, 800);
      failures.push(`${model} -> HTTP ${upstream.status}: ${detail}`);
      if (upstream.status === 401) break;
      if (upstream.status === 429) {
        await sleep(900);
      }
      continue;
    }

    try {
      const data = await upstream.json() as JsonRecord;
      const choices = asArray(data.choices);
      const first = asRecord(choices[0]);
      const message = asRecord(first.message);
      const raw = textValue(message.content).trim();
      if (!raw) throw new Error('Groq returned empty guidance.');
      const guidance = extractJsonObject(raw);
      validateGuidance(guidance);
      console.log(`PromptWise AI Coach succeeded with model: ${model}`);
      return guidance;
    } catch (error) {
      failures.push(`${model} -> invalid guidance: ${errorMessage(error)}`);
      continue;
    }
  }

  throw new Error(
    `AI Coach failed for all available models: ${failures.join(' | ')}`,
  );
}

function validateGuidance(value: JsonRecord): void {
  if (!textValue(value.summary).trim()) {
    throw new Error('Guidance summary is missing.');
  }
  const focus = asArray(value.focus_areas).map(textValue).filter(Boolean);
  const questions = asArray(value.guiding_questions).map(textValue).filter(Boolean);
  const notes = asArray(value.reasoning_notes).map(textValue).filter(Boolean);
  if (focus.length < 1 || focus.length > 3) {
    throw new Error('AI Coach focus areas are invalid.');
  }
  if (questions.length < 2 || questions.length > 4) {
    throw new Error('AI Coach guiding questions are invalid.');
  }
  if (notes.length < 2 || notes.length > 4) {
    throw new Error('AI Coach reasoning notes are invalid.');
  }
  if (!textValue(value.next_challenge).trim()) {
    throw new Error('AI Coach next challenge is missing.');
  }

  const flattened = JSON.stringify(value).toLowerCase();
  if (
    flattened.includes('rewritten prompt') ||
    flattened.includes('better prompt:') ||
    flattened.includes('improved prompt:')
  ) {
    throw new Error('AI Coach attempted to rewrite the learner prompt.');
  }
}

function serverPrivacyIssue(prompt: string): string | null {
  const lower = prompt.toLowerCase();
  if (/[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}/.test(prompt)) return 'email addresses';
  if (/\b(?:\+?63|0)?9\d{9}\b/.test(prompt)) return 'phone numbers';
  if (
    [
      'password:',
      'password is',
      'api key:',
      'apikey:',
      'secret key:',
      'access token:',
      'bearer ',
      'private key',
    ].some((term) => lower.includes(term))
  ) {
    return 'credential-like information';
  }
  if (/\b(?:\d[ -]*?){13,19}\b/.test(prompt) && /card|visa|mastercard|credit|debit/.test(lower)) {
    return 'payment information';
  }
  if (/\b\d{8,14}\b/.test(prompt) && /student id|student number|account number|government id|passport/.test(lower)) {
    return 'sensitive identifiers';
  }
  return null;
}

function extractJsonObject(value: string): JsonRecord {
  const cleaned = value
    .trim()
    .replace(/^```json\s*/i, '')
    .replace(/^```\s*/i, '')
    .replace(/```\s*$/i, '')
    .trim();
  try {
    const parsed = JSON.parse(cleaned);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as JsonRecord;
    }
  } catch (_) {
    // Try extracting the first JSON object from surrounding text.
  }
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  if (start >= 0 && end > start) {
    const parsed = JSON.parse(cleaned.slice(start, end + 1));
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as JsonRecord;
    }
  }
  throw new Error('Invalid JSON guidance.');
}

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function textValue(value: unknown): string {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
