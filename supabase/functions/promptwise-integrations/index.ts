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

const friendlyUpstreamMessage = (status: number) => {
  if (status === 401 || status === 403) {
    return 'AI Coach is unavailable right now.';
  }
  if (status === 429) {
    return 'AI Coach is busy right now. Please wait a moment and try again.';
  }
  if (status >= 500) {
    return 'AI Coach is temporarily unavailable. Please try again.';
  }
  return 'AI Coach could not respond. Please try again.';
};

const extractJsonObject = (value: string) => {
  const trimmed = value.trim();
  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch (_) {
    // Try to recover a JSON object from surrounding text.
  }

  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start >= 0 && end > start) {
    const parsed = JSON.parse(trimmed.slice(start, end + 1));
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  }
  throw new Error('Invalid structured response');
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const method = url.searchParams.get('method') ?? '';

    if (req.method === 'GET' && method === 'coach-status') {
      const groqKey = Deno.env.get('GROQ_API_KEY')?.trim();
      const model =
        Deno.env.get('GROQ_MODEL')?.trim() || 'llama-3.3-70b-versatile';
      if (!groqKey) {
        return response({ available: false }, 503);
      }

      const upstream = await fetch('https://api.groq.com/openai/v1/models', {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${groqKey}`,
          Accept: 'application/json',
        },
      });
      if (!upstream.ok) {
        return response(
          {
            available: false,
            message: friendlyUpstreamMessage(upstream.status),
          },
          upstream.status === 429 ? 429 : 502,
        );
      }
      const data = await upstream.json();
      const models = Array.isArray(data?.data) ? data.data : [];
      const available = models.some((item: any) => item?.id === model);
      return response({ available });
    }

    if (req.method === 'POST' && method === 'coach') {
      const groqKey = Deno.env.get('GROQ_API_KEY')?.trim();
      const model =
        Deno.env.get('GROQ_MODEL')?.trim() || 'llama-3.3-70b-versatile';
      if (!groqKey) {
        return response({ message: 'AI Coach is unavailable right now.' }, 503);
      }

      const body = await req.json().catch(() => ({}));
      const prompt = typeof body?.prompt === 'string' ? body.prompt.trim() : '';
      if (prompt.length < 10 || prompt.length > 1500) {
        return response(
          { message: 'Enter a prompt between 10 and 1500 characters.' },
          400,
        );
      }

      const systemPrompt = `You are PromptWise AI Coach, an educational coach for AI literacy.
Your ONLY job is to evaluate the learner's prompt and guide revision.
Do NOT perform the task in the learner's prompt.
Do NOT rewrite the prompt for them.
Do NOT provide a final answer to the task.
Use simple learner-friendly English.
Return only one valid JSON object with exactly these fields:
{
  "clarity": number from 0 to 1,
  "context": number from 0 to 1,
  "specificity": number from 0 to 1,
  "responsibility": number from 0 to 1,
  "overall": number from 0 to 1,
  "strengths": array of 1 to 4 short strings,
  "suggestions": array of 1 to 4 short strings,
  "guidingQuestions": array of 1 to 3 short questions,
  "safetyReminder": one short string,
  "summary": one or two short sentences
}
The overall score should reflect the four category scores. Encourage the learner to verify factual claims independently. Warn against sharing private or sensitive information.`;

      const upstream = await fetch(
        'https://api.groq.com/openai/v1/chat/completions',
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${groqKey}`,
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
          body: JSON.stringify({
            model,
            temperature: 0.2,
            max_completion_tokens: 700,
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: prompt },
            ],
          }),
        },
      );

      if (!upstream.ok) {
        return response(
          { message: friendlyUpstreamMessage(upstream.status) },
          upstream.status === 429 ? 429 : 502,
        );
      }

      const data = await upstream.json();
      const content = data?.choices?.[0]?.message?.content;
      if (typeof content !== 'string' || content.trim().length === 0) {
        return response(
          { message: 'AI Coach did not return usable feedback.' },
          502,
        );
      }

      let feedback: Record<string, unknown>;
      try {
        feedback = extractJsonObject(content);
      } catch (_) {
        return response(
          { message: 'AI Coach returned an unreadable response. Please try again.' },
          502,
        );
      }

      return response({ feedback });
    }

    return response({ message: 'This action is unavailable.' }, 404);
  } catch (_) {
    return response(
      { message: 'AI Coach could not respond. Please try again.' },
      500,
    );
  }
});
