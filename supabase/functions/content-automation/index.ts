import { createClient } from 'npm:@supabase/supabase-js@2';
import { XMLParser } from 'npm:fast-xml-parser@4.5.3';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-automation-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const TOPICS = new Set([
  'prompt_clarity',
  'context',
  'specificity',
  'responsible_use',
  'verification',
]);

const UNIVERSAL_KEYWORDS = [
  'artificial intelligence',
  'generative ai',
  'ai ',
  'deepfake',
  'misinformation',
  'disinformation',
  'privacy',
  'personal data',
  'bias',
  'hallucination',
  'verification',
  'fact check',
  'citation',
  'source',
  'prompt',
  'academic integrity',
  'scam',
  'synthetic media',
];

const MAX_ARTICLE_TEXT = 9000;

const AI_ANCHOR_KEYWORDS = [
  'artificial intelligence',
  'generative ai',
  'ai system',
  'ai model',
  'ai-generated',
  'ai generated',
  'machine learning',
  'large language model',
  'llm',
  'chatgpt',
  'chatbot',
  'prompt engineering',
  'deepfake',
  'synthetic media',
];

type JsonRecord = Record<string, unknown>;

type SourceRow = {
  id: string;
  name: string;
  source_url: string;
  feed_url: string | null;
  source_type: 'rss' | 'page';
  trust_level: number;
  relevance_keywords: unknown;
};

type Candidate = {
  sourceId: string;
  sourceName: string;
  url: string;
  title: string;
  summary: string;
  publishedAt: string | null;
  relevanceScore: number;
  topicHint: string | null;
};

type GeneratedQuestion = {
  question_type: 'concept' | 'scenario' | 'best_response' | 'evaluation';
  stem: string;
  options: string[];
  correct_index: number;
  explanation: string;
  difficulty: number;
};

type GeneratedDraftPayload = {
  title: string;
  summary: string;
  topic_id: string;
  target_level: number;
  objectives: Array<{ title: string; description: string }>;
  lesson_sections: string[];
  questions: GeneratedQuestion[];
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed.' }, 405);
  }

  const supabaseUrl = requireEnv('SUPABASE_URL');
  const serviceRoleKey = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  const groqApiKey = Deno.env.get('GROQ_API_KEY')?.trim() ?? '';

  if (!groqApiKey) {
    return jsonResponse(
      { error: 'GROQ_API_KEY is not configured for content automation.' },
      500,
    );
  }

  const service = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: JsonRecord = {};
  try {
    body = (await req.json()) as JsonRecord;
  } catch {
    body = {};
  }

  const mode = body.mode === 'scheduled' ? 'scheduled' : 'manual';

  try {
    if (mode === 'manual') {
      await requireAdmin(req, service);
    } else {
      await requireScheduledSecret(req, service);
    }

    const { data: settings, error: settingsError } = await service
      .from('automation_settings')
      .select('*')
      .eq('id', 1)
      .single();
    if (settingsError) throw settingsError;

    if (!settings.enabled) {
      return jsonResponse({ message: 'Content automation is disabled.' });
    }

    // Keep unattended queues bounded before every run. The same cleanup also
    // runs daily through pg_cron, so this is a second line of defense.
    const { error: cleanupError } = await service.rpc(
      'phase7_cleanup_content_queues',
    );
    if (cleanupError) {
      console.warn('Phase 7 queue cleanup could not run before automation.', cleanupError);
    }

    const [pendingDraftResult, pendingQuestionResult] = await Promise.all([
      service
        .from('generated_content_drafts')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'draft'),
      service
        .from('question_bank')
        .select('id', { count: 'exact', head: true })
        .eq('generated_by', 'content_automation')
        .eq('validation_status', 'needs_review')
        .neq('status', 'archived'),
    ]);

    if (pendingDraftResult.error) throw pendingDraftResult.error;
    if (pendingQuestionResult.error) throw pendingQuestionResult.error;

    const pendingDrafts = Number(pendingDraftResult.count ?? 0);
    const pendingQuestions = Number(pendingQuestionResult.count ?? 0);
    const maxPendingDrafts = Math.max(
      1,
      Number(settings.max_pending_drafts ?? 30),
    );
    const maxPendingQuestions = Math.max(
      1,
      Number(settings.max_pending_questions ?? 100),
    );

    if (pendingDrafts >= maxPendingDrafts || pendingQuestions >= maxPendingQuestions) {
      const queueMessage =
        `Content automation paused because the admin review queue is full. ` +
        `Lesson drafts: ${pendingDrafts}/${maxPendingDrafts}; ` +
        `questions: ${pendingQuestions}/${maxPendingQuestions}. ` +
        `Review or archive pending AI content before generating more.`;

      await service.from('automation_runs').insert({
        trigger_mode: mode,
        status: 'skipped',
        completed_at: new Date().toISOString(),
        error_message: queueMessage,
      });

      return jsonResponse({
        message: queueMessage,
        queuePaused: true,
        pendingDrafts,
        pendingQuestions,
      }, 202);
    }

    if (mode === 'manual' && settings.last_manual_run_at) {
      const last = new Date(settings.last_manual_run_at).getTime();
      const cooldownMs =
        Math.max(1, Number(settings.manual_cooldown_minutes ?? 30)) * 60000;
      const remainingMs = last + cooldownMs - Date.now();
      if (remainingMs > 0) {
        const minutes = Math.max(1, Math.ceil(remainingMs / 60000));
        return jsonResponse(
          {
            error: `Manual content checks have a cooldown. Try again in about ${minutes} minute${minutes === 1 ? '' : 's'}.`,
          },
          429,
        );
      }
    }

    const staleCutoff = new Date(Date.now() - 20 * 60 * 1000).toISOString();
    const { data: running } = await service
      .from('automation_runs')
      .select('id')
      .eq('status', 'running')
      .gte('started_at', staleCutoff)
      .limit(1);
    if ((running ?? []).length > 0) {
      return jsonResponse(
        { message: 'A content automation run is already in progress.' },
        202,
      );
    }

    const { data: run, error: runError } = await service
      .from('automation_runs')
      .insert({ trigger_mode: mode, status: 'running' })
      .select('id')
      .single();
    if (runError) throw runError;
    const runId = run.id as string;

    if (mode === 'manual') {
      await service
        .from('automation_settings')
        .update({
          last_manual_run_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', 1);
    }

    try {
      const todayStart = startOfUtcDay();
      const monthStart = startOfUtcMonth();
      const [{ count: todayCount }, { count: monthCount }] = await Promise.all([
        service
          .from('generated_content_drafts')
          .select('id', { count: 'exact', head: true })
          .gte('created_at', todayStart),
        service
          .from('generated_content_drafts')
          .select('id', { count: 'exact', head: true })
          .gte('created_at', monthStart),
      ]);

      const dailyRemaining = Math.max(
        0,
        Number(settings.max_drafts_per_day ?? 3) - Number(todayCount ?? 0),
      );
      const monthlyRemaining = Math.max(
        0,
        Number(settings.monthly_draft_cap ?? 100) - Number(monthCount ?? 0),
      );
      const queueDraftRemaining = Math.max(0, maxPendingDrafts - pendingDrafts);
      const draftBudget = Math.min(
        dailyRemaining,
        monthlyRemaining,
        queueDraftRemaining,
      );

      if (draftBudget <= 0) {
        await completeRun(service, runId, {
          status: 'skipped',
          sourcesChecked: 0,
          articlesDiscovered: 0,
          draftsCreated: 0,
        });
        return jsonResponse({
          message:
            queueDraftRemaining <= 0
              ? `Content automation is healthy, but the AI lesson draft queue is full (${pendingDrafts}/${maxPendingDrafts}). Review pending drafts before generating more.`
              : 'Content automation is healthy, but the current daily or monthly draft limit has already been reached.',
          draftsCreated: 0,
          pendingDrafts,
          pendingQuestions,
        });
      }

      const { data: sourceRows, error: sourceError } = await service
        .from('content_sources')
        .select(
          'id, name, source_url, feed_url, source_type, trust_level, relevance_keywords',
        )
        .eq('enabled', true)
        .order('trust_level', { ascending: false });
      if (sourceError) throw sourceError;

      const sources = (sourceRows ?? []) as SourceRow[];
      const candidates: Candidate[] = [];
      let sourcesChecked = 0;

      for (const source of sources) {
        try {
          const found = await discoverFromSource(source);
          candidates.push(...found);
          sourcesChecked += 1;
          await service
            .from('content_sources')
            .update({
              last_checked_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            })
            .eq('id', source.id);
        } catch (error) {
          console.error(`Source check failed: ${source.name}`, error);
          // One source must not abort the whole run.
        }
      }

      const dedupedCandidates = dedupeCandidates(candidates)
        .sort((a, b) => b.relevanceScore - a.relevanceScore)
        .slice(0, Math.max(1, Number(settings.max_articles_per_run ?? 3) * 3));

      let articlesDiscovered = 0;
      let draftsCreated = 0;
      let processingFailures = 0;
      const maxArticles = Math.max(1, Number(settings.max_articles_per_run ?? 3));
      const groqModels = await resolveGroqModels(groqApiKey);
      console.log('Groq models available to this project:', groqModels.join(', '));

      for (const candidate of dedupedCandidates) {
        if (articlesDiscovered >= maxArticles || draftsCreated >= draftBudget) {
          break;
        }

        const fingerprint = await sha256(
          `${normalizeUrl(candidate.url)}|${candidate.title.toLowerCase().trim()}`,
        );

        const { data: existingArticle } = await service
          .from('discovered_articles')
          .select('id, status')
          .or(`article_url.eq.${escapePostgrest(candidate.url)},fingerprint.eq.${fingerprint}`)
          .maybeSingle();

        let article: { id: string };
        if (existingArticle) {
          // Processed/ignored articles are intentionally deduplicated forever, but a
          // failed article must be retryable after a model/configuration fix.
          if (existingArticle.status !== 'failed') continue;
          article = { id: String(existingArticle.id) };
          await service
            .from('discovered_articles')
            .update({ status: 'new', processed_at: null })
            .eq('id', article.id);
        } else {
          const { data: insertedArticle, error: articleError } = await service
            .from('discovered_articles')
            .insert({
              source_id: candidate.sourceId,
              article_url: candidate.url,
              title: candidate.title,
              summary: candidate.summary,
              published_at: candidate.publishedAt,
              fingerprint,
              relevance_score: candidate.relevanceScore,
              topic_hint: candidate.topicHint,
              status: 'new',
            })
            .select('id')
            .single();
          if (articleError) {
            if ((articleError as { code?: string }).code === '23505') continue;
            throw articleError;
          }
          article = { id: String(insertedArticle.id) };
          articlesDiscovered += 1;
        }

        try {
          const articleText = await fetchArticleText(candidate.url);
          if (articleText.length < 300) {
            await markArticle(service, article.id, 'ignored');
            continue;
          }

          const draft = await generateDraft({
            apiKey: groqApiKey,
            models: groqModels,
            candidate,
            articleText,
          });
          validateDraft(draft);

          const { error: draftError } = await service
            .from('generated_content_drafts')
            .insert({
              article_id: article.id,
              title: draft.title,
              summary: draft.summary,
              topic_id: draft.topic_id,
              target_level: draft.target_level,
              source_name: candidate.sourceName,
              source_url: candidate.url,
              source_published_at: candidate.publishedAt,
              draft_payload: draft,
              status: 'draft',
            });
          if (draftError) throw draftError;

          await markArticle(service, article.id, 'processed');
          draftsCreated += 1;
        } catch (error) {
          processingFailures += 1;
          console.error('Article processing failed', candidate.url, error);
          await markArticle(service, article.id, 'failed');
        }
      }

      await completeRun(service, runId, {
        status: 'completed',
        sourcesChecked,
        articlesDiscovered,
        draftsCreated,
      });

      const message = draftsCreated > 0
        ? `Content check completed. ${draftsCreated} new review draft${draftsCreated === 1 ? '' : 's'} created from trusted sources.`
        : processingFailures > 0
          ? `Content check completed, but ${processingFailures} candidate article${processingFailures === 1 ? '' : 's'} could not be converted into a valid draft. Check the Edge Function logs.`
          : 'Content check completed. No new relevant, non-duplicate draft was needed.';

      return jsonResponse({
        message,
        sourcesChecked,
        articlesDiscovered,
        draftsCreated,
        processingFailures,
      });
    } catch (error) {
      await completeRun(service, runId, {
        status: 'failed',
        sourcesChecked: 0,
        articlesDiscovered: 0,
        draftsCreated: 0,
        errorMessage: errorMessage(error),
      });
      throw error;
    }
  } catch (error) {
    console.error(error);
    const status = error instanceof HttpError ? error.status : 500;
    return jsonResponse({ error: errorMessage(error) }, status);
  }
});

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new HttpError(500, `${name} is not configured.`);
  return value;
}

async function requireAdmin(
  req: Request,
  service: ReturnType<typeof createClient>,
): Promise<void> {
  const authHeader = req.headers.get('authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) throw new HttpError(401, 'Sign in as an administrator first.');

  const { data: userData, error: userError } = await service.auth.getUser(token);
  if (userError || !userData.user) {
    throw new HttpError(401, 'The administrator session is invalid.');
  }

  const { data: profile, error: profileError } = await service
    .from('profiles')
    .select('role')
    .eq('id', userData.user.id)
    .single();
  if (profileError || profile?.role !== 'administrator') {
    throw new HttpError(403, 'Administrator access required.');
  }
}

async function requireScheduledSecret(
  req: Request,
  service: ReturnType<typeof createClient>,
): Promise<void> {
  const { data: scheduler, error } = await service
    .from('automation_scheduler_config')
    .select('scheduler_secret, enabled')
    .eq('id', 1)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, 'Automation scheduler configuration could not be read.');
  }
  if (!scheduler || scheduler.enabled !== true) {
    throw new HttpError(503, 'Automatic content scheduling is disabled.');
  }

  const expected = scheduler.scheduler_secret?.toString().trim() ?? '';
  const supplied = req.headers.get('x-automation-secret')?.trim() ?? '';
  if (!expected || !timingSafeEqual(supplied, expected)) {
    throw new HttpError(401, 'Invalid automation scheduler secret.');
  }
}

function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const aa = encoder.encode(a);
  const bb = encoder.encode(b);
  if (aa.length !== bb.length) return false;
  let result = 0;
  for (let i = 0; i < aa.length; i += 1) result |= aa[i] ^ bb[i];
  return result === 0;
}

async function discoverFromSource(source: SourceRow): Promise<Candidate[]> {
  const keywords = stringArray(source.relevance_keywords);
  if (source.source_type === 'rss' && source.feed_url) {
    return discoverRss(source, keywords);
  }
  return discoverPage(source, keywords);
}

async function discoverRss(
  source: SourceRow,
  keywords: string[],
): Promise<Candidate[]> {
  const xml = await fetchText(source.feed_url ?? source.source_url);
  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: '@_',
    textNodeName: '#text',
  });
  const doc = parser.parse(xml) as JsonRecord;

  const rssItems = asArray(
    ((doc.rss as JsonRecord | undefined)?.channel as JsonRecord | undefined)
      ?.item,
  );
  const atomEntries = asArray((doc.feed as JsonRecord | undefined)?.entry);
  const items = rssItems.length > 0 ? rssItems : atomEntries;

  const candidates: Candidate[] = [];
  for (const raw of items.slice(0, 30)) {
    const item = asRecord(raw);
    const title = textValue(item.title);
    const summary = stripHtml(
      textValue(item.description) || textValue(item.summary) || textValue(item.content),
    );
    const url = extractFeedLink(item, source.source_url);
    if (!title || !url) continue;
    const scoreInfo = relevanceFor(`${title} ${summary} ${url}`, keywords);
    if (scoreInfo.score < 1) continue;
    candidates.push({
      sourceId: source.id,
      sourceName: source.name,
      url,
      title: title.slice(0, 300),
      summary: summary.slice(0, 1200),
      publishedAt: parseDate(
        textValue(item.pubDate) ||
          textValue(item.published) ||
          textValue(item.updated),
      ),
      relevanceScore: scoreInfo.score,
      topicHint: scoreInfo.topic,
    });
  }
  return candidates;
}

async function discoverPage(
  source: SourceRow,
  keywords: string[],
): Promise<Candidate[]> {
  const html = await fetchText(source.source_url);
  const anchorRegex = /<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  const candidates: Candidate[] = [];
  const seen = new Set<string>();
  let match: RegExpExecArray | null;
  while ((match = anchorRegex.exec(html)) != null && candidates.length < 25) {
    const href = decodeHtml(match[1] ?? '').trim();
    const label = stripHtml(match[2] ?? '').replace(/\s+/g, ' ').trim();
    if (label.length < 12) continue;
    let url: string;
    try {
      url = new URL(href, source.source_url).toString();
    } catch {
      continue;
    }
    if (!/^https?:/i.test(url) || seen.has(url)) continue;
    const sourceHost = new URL(source.source_url).hostname.replace(/^www\./, '');
    const host = new URL(url).hostname.replace(/^www\./, '');
    if (host !== sourceHost && !host.endsWith(`.${sourceHost}`)) continue;
    seen.add(url);

    const scoreInfo = relevanceFor(`${label} ${url}`, keywords);
    if (scoreInfo.score < 1) continue;
    candidates.push({
      sourceId: source.id,
      sourceName: source.name,
      url,
      title: label.slice(0, 300),
      summary: '',
      publishedAt: null,
      relevanceScore: scoreInfo.score,
      topicHint: scoreInfo.topic,
    });
  }
  return candidates;
}

function relevanceFor(
  input: string,
  sourceKeywords: string[],
): { score: number; topic: string | null } {
  const text = input.toLowerCase();

  // Phase 7 automation is specifically for AI-literacy updates. Generic
  // privacy/scam/source articles must not pass unless the title/summary also
  // contains a clear AI-related anchor.
  const hasAiAnchor = AI_ANCHOR_KEYWORDS.some((keyword) =>
    text.includes(keyword),
  );
  if (!hasAiAnchor) return { score: 0, topic: null };

  let hits = 0;
  for (const keyword of [...UNIVERSAL_KEYWORDS, ...sourceKeywords]) {
    const normalized = keyword.trim().toLowerCase();
    if (normalized && text.includes(normalized)) hits += 1;
  }

  const topicScores: Record<string, number> = {
    prompt_clarity: hitsFor(text, ['prompt', 'instruction', 'clarity', 'ambiguity']),
    context: hitsFor(text, ['context', 'background', 'audience', 'assumption']),
    specificity: hitsFor(text, ['constraint', 'specific', 'criteria', 'requirement', 'format']),
    responsible_use: hitsFor(text, [
      'privacy',
      'personal data',
      'bias',
      'fairness',
      'academic integrity',
      'safety',
      'responsible',
      'governance',
      'accountability',
    ]),
    verification: hitsFor(text, [
      'deepfake',
      'misinformation',
      'verification',
      'fact check',
      'citation',
      'source',
      'hallucination',
      'synthetic media',
      'evidence',
    ]),
  };
  const sorted = Object.entries(topicScores).sort((a, b) => b[1] - a[1]);
  const topic = sorted[0]?.[1] > 0 ? sorted[0][0] : null;
  return { score: Math.min(100, hits * 12.5), topic };
}

function hitsFor(text: string, words: string[]): number {
  return words.reduce((sum, word) => sum + (text.includes(word) ? 1 : 0), 0);
}

async function fetchArticleText(url: string): Promise<string> {
  const html = await fetchText(url);
  const withoutNoise = html
    .replace(/<script\b[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[\s\S]*?<\/style>/gi, ' ')
    .replace(/<nav\b[\s\S]*?<\/nav>/gi, ' ')
    .replace(/<footer\b[\s\S]*?<\/footer>/gi, ' ');
  return stripHtml(withoutNoise)
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, MAX_ARTICLE_TEXT);
}

async function fetchText(url: string): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        'User-Agent': 'PromptWise-Learning-Content-Checker/1.0',
        Accept: 'text/html,application/rss+xml,application/xml,text/xml,*/*',
      },
    });
    if (!response.ok) {
      throw new Error(`Source returned HTTP ${response.status}.`);
    }
    const text = await response.text();
    if (text.length > 2_000_000) {
      return text.slice(0, 2_000_000);
    }
    return text;
  } finally {
    clearTimeout(timeout);
  }
}

async function resolveGroqModels(apiKey: string): Promise<string[]> {
  const configured = Deno.env.get('GROQ_MODEL')?.trim();
  if (configured) return [configured];

  const response = await fetch('https://api.groq.com/openai/v1/models', {
    headers: { Authorization: `Bearer ${apiKey}` },
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 800);
    throw new Error(`Could not list Groq models (${response.status}): ${detail}`);
  }

  const data = (await response.json()) as { data?: Array<{ id?: string }> };
  const ids = (data.data ?? [])
    .map((item) => item.id?.trim() ?? '')
    .filter(Boolean)
    .filter((id) => !/whisper|tts|speech|guard|safeguard|vision|image/i.test(id));

  // Prefer production text models that support structured/JSON output while
  // still honoring the exact models exposed to this Groq project/key.
  const preferredOrder = [
    // Prefer the lighter production model first for automated curriculum
    // drafting. Larger models remain fallbacks when available.
    'llama-3.1-8b-instant',
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
    'llama-3.3-70b-versatile',
    'qwen/qwen3.6-27b',
    'groq/compound-mini',
    'groq/compound',
  ];

  const ordered: string[] = [];
  for (const preferred of preferredOrder) {
    if (ids.includes(preferred)) ordered.push(preferred);
  }
  for (const id of ids) {
    if (!ordered.includes(id)) ordered.push(id);
  }

  if (ordered.length == 0) {
    throw new Error('No usable Groq text model is available to this project.');
  }
  return ordered;
}

async function generateDraft({
  apiKey,
  models,
  candidate,
  articleText,
}: {
  apiKey: string;
  models: string[];
  candidate: Candidate;
  articleText: string;
}): Promise<GeneratedDraftPayload> {
  const basePrompt = `You are the curriculum drafting engine for PromptWise, an AI-literacy learning system.

SOURCE RULES:
- Use ONLY the supplied trusted-source material for time-sensitive factual claims.
- Do not invent statistics, dates, policies, quotations, or events.
- The source is input for a DRAFT only; a human administrator must review it.
- Build durable AI-literacy instruction around the source instead of merely summarizing news.

LEARNING DESIGN RULES:
- Valid topic_id values: prompt_clarity, context, specificity, responsible_use, verification.
- target_level is 1 Foundation, 2 Developing, 3 Proficient, 4 Advanced, 5 Expert.
- Prefer scenario/application/evaluation work over elementary obvious questions.
- Questions must have exactly four distinct options and exactly one defensible best answer.
- Difficulty must match the reasoning complexity, not just vocabulary.
- Never use trick wording.
- Create exactly 4 meaningful learning objectives, exactly 6 lesson sections, and exactly 5 questions.
- Every lesson section must begin with a short heading on the first line, followed by at least 120 words of substantive instruction.
- The six sections should cover: core concept, second concept, applied example, common mistake/trade-off, guided analysis, and key takeaways/transfer.
- Higher levels should require analysis, trade-offs, evidence quality, or multi-constraint reasoning.

Return STRICT JSON only with this exact shape:
{
  "title": "...",
  "summary": "...",
  "topic_id": "verification",
  "target_level": 3,
  "objectives": [
    {"title":"...", "description":"..."}
  ],
  "lesson_sections": ["Section heading\\nDetailed instructional content..."],
  "questions": [
    {
      "question_type":"scenario",
      "stem":"...",
      "options":["...","...","...","..."],
      "correct_index":0,
      "explanation":"Explain why the keyed answer is best and what principle it demonstrates.",
      "difficulty":3
    }
  ]
}

Trusted source: ${candidate.sourceName}
Source URL: ${candidate.url}
Source title: ${candidate.title}
Possible topic hint: ${candidate.topicHint ?? 'none'}

SOURCE MATERIAL:
${articleText}`;

  const failures: string[] = [];

  for (const model of models) {
    const prompt = failures.length === 0
      ? basePrompt
      : `${basePrompt}

IMPORTANT VALIDATION NOTE:
A previous generation attempt failed PromptWise validation. Make this response fully satisfy every exact count, section-depth, answer-choice, and difficulty requirement above.`;

    const response = await fetch(
      'https://api.groq.com/openai/v1/chat/completions',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          temperature: 0.2,
          response_format: { type: 'json_object' },
          messages: [
            {
              role: 'system',
              content:
                'Produce rigorous, source-grounded AI-literacy curriculum drafts as valid JSON. Follow exact array counts and depth requirements. Never auto-publish or claim human review occurred.',
            },
            { role: 'user', content: prompt },
          ],
        }),
      },
    );

    if (!response.ok) {
      const detail = (await response.text()).slice(0, 800);
      failures.push(`${model} -> HTTP ${response.status}: ${detail}`);
      console.warn(`Groq model failed: ${model}`, detail);

      // 401 means the key itself is invalid. 429 is often model-specific on
      // Groq, so continue to another available model instead of aborting the
      // entire article.
      if (response.status === 401) break;
      if (response.status === 429) {
        await sleep(1200);
        continue;
      }
      continue;
    }

    try {
      const data = (await response.json()) as JsonRecord;
      const choices = asArray(data.choices);
      const first = asRecord(choices[0]);
      const message = asRecord(first.message);
      const content = textValue(message.content).trim();
      if (!content) throw new Error('Groq returned an empty draft.');

      const cleaned = content
        .replace(/^```json\s*/i, '')
        .replace(/^```\s*/i, '')
        .replace(/```\s*$/i, '')
        .trim();

      const draft = JSON.parse(cleaned) as GeneratedDraftPayload;
      validateDraft(draft);
      console.log(`Groq draft generation succeeded with model: ${model}`);
      return draft;
    } catch (error) {
      const detail = errorMessage(error);
      failures.push(`${model} -> invalid draft: ${detail}`);
      console.warn(`Groq draft failed PromptWise validation: ${model}`, detail);
      await sleep(800);
      continue;
    }
  }

  throw new Error(
    `Groq draft generation failed for all available models: ${failures.join(' | ')}`,
  );
}

function validateDraft(draft: GeneratedDraftPayload): void {
  if (!draft || typeof draft !== 'object') throw new Error('Invalid draft payload.');
  if (!nonEmpty(draft.title) || !nonEmpty(draft.summary)) {
    throw new Error('Generated draft is missing a title or summary.');
  }
  if (!TOPICS.has(draft.topic_id)) throw new Error('Generated topic is invalid.');
  if (!Number.isInteger(draft.target_level) || draft.target_level < 1 || draft.target_level > 5) {
    throw new Error('Generated target level is invalid.');
  }
  if (!Array.isArray(draft.objectives) || draft.objectives.length < 3) {
    throw new Error('Generated draft needs at least three learning objectives.');
  }
  for (const objective of draft.objectives) {
    if (!nonEmpty(objective?.title) || !nonEmpty(objective?.description)) {
      throw new Error('Generated learning objective is incomplete.');
    }
  }
  if (!Array.isArray(draft.lesson_sections) || draft.lesson_sections.length < 5) {
    throw new Error('Generated lesson is not deep enough.');
  }
  if (draft.lesson_sections.some((section) => !nonEmpty(section) || section.length < 80)) {
    throw new Error('Generated lesson contains an underdeveloped section.');
  }
  if (!Array.isArray(draft.questions) || draft.questions.length < 5) {
    throw new Error('Generated draft needs at least five questions.');
  }

  for (const question of draft.questions) {
    if (!['concept', 'scenario', 'best_response', 'evaluation'].includes(question.question_type)) {
      throw new Error('Generated question type is invalid.');
    }
    if (!nonEmpty(question.stem) || !nonEmpty(question.explanation)) {
      throw new Error('Generated question is incomplete.');
    }
    if (!Array.isArray(question.options) || question.options.length !== 4) {
      throw new Error('Every generated question must have four options.');
    }
    const normalizedOptions = question.options.map((option) => option.trim().toLowerCase());
    if (normalizedOptions.some((option) => !option) || new Set(normalizedOptions).size !== 4) {
      throw new Error('Generated question options must be non-empty and distinct.');
    }
    if (!Number.isInteger(question.correct_index) || question.correct_index < 0 || question.correct_index > 3) {
      throw new Error('Generated correct answer index is invalid.');
    }
    if (!Number.isInteger(question.difficulty) || question.difficulty < 1 || question.difficulty > 5) {
      throw new Error('Generated question difficulty is invalid.');
    }
  }
}

async function markArticle(
  service: ReturnType<typeof createClient>,
  articleId: string,
  status: 'processed' | 'ignored' | 'failed',
): Promise<void> {
  await service
    .from('discovered_articles')
    .update({ status, processed_at: new Date().toISOString() })
    .eq('id', articleId);
}

async function completeRun(
  service: ReturnType<typeof createClient>,
  runId: string,
  values: {
    status: 'completed' | 'failed' | 'skipped';
    sourcesChecked: number;
    articlesDiscovered: number;
    draftsCreated: number;
    errorMessage?: string;
  },
): Promise<void> {
  await service
    .from('automation_runs')
    .update({
      status: values.status,
      completed_at: new Date().toISOString(),
      sources_checked: values.sourcesChecked,
      articles_discovered: values.articlesDiscovered,
      drafts_created: values.draftsCreated,
      error_message: values.errorMessage ?? null,
    })
    .eq('id', runId);
}

function extractFeedLink(item: JsonRecord, baseUrl: string): string {
  const link = item.link;
  if (typeof link === 'string') return resolveUrl(link, baseUrl);
  if (Array.isArray(link)) {
    for (const raw of link) {
      const row = asRecord(raw);
      const href = textValue(row['@_href']);
      const rel = textValue(row['@_rel']);
      if (href && (!rel || rel === 'alternate')) return resolveUrl(href, baseUrl);
    }
  }
  const row = asRecord(link);
  const href = textValue(row['@_href']) || textValue(row['#text']);
  return href ? resolveUrl(href, baseUrl) : '';
}

function resolveUrl(value: string, baseUrl: string): string {
  try {
    return new URL(decodeHtml(value.trim()), baseUrl).toString();
  } catch {
    return '';
  }
}

function dedupeCandidates(candidates: Candidate[]): Candidate[] {
  const map = new Map<string, Candidate>();
  for (const candidate of candidates) {
    const key = normalizeUrl(candidate.url);
    const current = map.get(key);
    if (!current || candidate.relevanceScore > current.relevanceScore) {
      map.set(key, candidate);
    }
  }
  return [...map.values()];
}

function normalizeUrl(value: string): string {
  try {
    const url = new URL(value);
    url.hash = '';
    ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content'].forEach(
      (key) => url.searchParams.delete(key),
    );
    return url.toString().replace(/\/$/, '');
  } catch {
    return value.trim();
  }
}

function escapePostgrest(value: string): string {
  // Values containing punctuation are quoted for PostgREST logical filters.
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

async function sha256(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function stripHtml(value: string): string {
  return decodeHtml(
    value
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      .replace(/<[^>]+>/g, ' '),
  )
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ');
}

function textValue(value: unknown): string {
  if (value == null) return '';
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (typeof value === 'object') {
    const row = value as JsonRecord;
    return textValue(row['#text']) || textValue(row._);
  }
  return '';
}

function asRecord(value: unknown): JsonRecord {
  return value != null && typeof value === 'object' && !Array.isArray(value)
    ? (value as JsonRecord)
    : {};
}

function asArray(value: unknown): unknown[] {
  if (value == null) return [];
  return Array.isArray(value) ? value : [value];
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item)).filter((item) => item.trim().length > 0);
}

function parseDate(value: string): string | null {
  if (!value.trim()) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function nonEmpty(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function startOfUtcDay(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())).toISOString();
}

function startOfUtcMonth(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  try {
    return JSON.stringify(error);
  } catch {
    return 'Unknown error.';
  }
}

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
