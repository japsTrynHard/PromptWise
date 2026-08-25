import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type JsonRecord = Record<string, unknown>;

type SourceDomain = {
  domain: string;
  name: string;
  region: 'Philippines' | 'Global';
  trust_level: number;
};

type DirectSource = {
  id: string;
  name: string;
  base_domain: string;
  source_url: string;
  source_type: 'html_listing' | 'rss';
  region: 'Philippines' | 'Global';
  trust_level: number;
  priority: number;
  relevance_keywords: string[];
};

type GdeltArticle = {
  url?: string;
  url_mobile?: string;
  title?: string;
  seendate?: string;
  socialimage?: string;
  domain?: string;
  language?: string;
  sourcecountry?: string;
};

type Candidate = {
  title: string;
  url: string;
  imageUrl: string | null;
  publishedAt: string | null;
  sourceDomain: string;
  sourceName: string;
  sourceCountry: string;
  region: 'Philippines' | 'Global';
  trustLevel: number;
  category: string;
  relevanceScore: number;
  aiRelevanceScore: number;
  provider: string;
  sourceExcerpt?: string;
};

type RefreshStats = {
  discovered: number;
  trustedMatched: number;
  usable: number;
  saved: number;
  philippines: number;
  global: number;
  activeCount: number;
  providerWarnings: string[];
};

const PH_QUERY =
  '(AI OR "artificial intelligence" OR "generative AI" OR deepfake OR "AI-generated" OR "AI generated" OR "AI-powered" OR "AI powered" OR "AI-driven" OR "voice cloning" OR "synthetic media" OR "AI scam" OR "AI fraud" OR "AI misinformation" OR "AI disinformation" OR ChatGPT OR Gemini OR Claude OR Grok) sourcecountry:philippines';
const PH_FALLBACK_QUERY =
  '(AI OR "artificial intelligence" OR "generative AI" OR deepfake OR "AI-generated" OR "AI powered" OR "voice cloning" OR "synthetic media" OR "AI scam" OR "AI misinformation" OR ChatGPT OR Gemini OR Claude OR Grok)';
const GLOBAL_QUERY =
  '(AI OR "artificial intelligence" OR "generative AI" OR deepfake OR "AI-generated" OR "AI-powered" OR "AI-driven" OR "voice cloning" OR "synthetic media" OR "AI scam" OR "AI fraud" OR "AI impersonation" OR "AI-generated misinformation" OR "AI-generated disinformation" OR ChatGPT OR Gemini OR Claude OR Grok)';


const BING_PH_QUERIES = [
  '"artificial intelligence" Philippines',
  '(deepfake OR "AI-generated" OR "voice cloning") Philippines',
  '("generative AI" OR ChatGPT OR Gemini OR OpenAI) Philippines',
  '("AI scam" OR "AI misinformation" OR "AI safety") Philippines',
];

const BING_GLOBAL_QUERIES = [
  '("artificial intelligence" OR "generative AI" OR ChatGPT OR OpenAI)',
  '(deepfake OR "AI-generated" OR "voice cloning" OR "synthetic media")',
];

// PNA exposes a public keyword-search page. Querying it directly gives the
// Philippine feed a dependable first-party discovery path instead of relying
// only on a generic headlines feed or third-party news indexes.
const PNA_AI_SEARCH_URLS = [
  'https://www.pna.gov.ph/articles/search?q=artificial%20intelligence',
  'https://www.pna.gov.ph/articles/search?q=deepfake',
  'https://www.pna.gov.ph/articles/search?q=generative%20AI',
  'https://www.pna.gov.ph/articles/search?q=ChatGPT',
  // PNA's technology search currently surfaces recent Philippine AI policy,
  // education, industry, and deepfake stories; the strict title filter below
  // discards the unrelated technology headlines.
  'https://www.pna.gov.ph/articles/search?q=technology',
];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed.' }, 405);
  }

  const supabaseUrl = requireEnv('SUPABASE_URL');
  const serviceRoleKey = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  const service = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: JsonRecord = {};
  try {
    body = (await req.json()) as JsonRecord;
  } catch {
    body = {};
  }

  const action = body.action?.toString() ?? 'refresh_if_stale';
  try {
    const scheduled = action === 'scheduled_refresh';
    let userId: string | null = null;
    if (scheduled) {
      await requireSchedulerSecret(req, service);
    } else {
      const user = await requireUser(req, service);
      userId = user.id;
      if (action === 'force_refresh') {
        await requireAdmin(user.id, service);
      }
    }

    const { data: settings, error: settingsError } = await service
      .from('awareness_feed_settings')
      .select('*')
      .eq('id', 1)
      .single();
    if (settingsError) throw settingsError;
    if (settings.enabled === false) {
      return jsonResponse({ message: 'Live awareness updates are disabled.' });
    }

    const refreshMinutes = Math.max(30, Number(settings.refresh_minutes ?? 120));
    const minActiveAiArticles = Math.max(
      4,
      Math.min(50, Number(settings.min_active_ai_articles ?? 12)),
    );
    const activeCount = await countActiveArticles(service);
    const successStamp = settings.last_success_at ?? settings.last_refresh_at;
    const lastSuccess = successStamp ? new Date(String(successStamp)) : null;
    const timeStale =
      !lastSuccess ||
      Number.isNaN(lastSuccess.getTime()) ||
      Date.now() - lastSuccess.getTime() >= refreshMinutes * 60_000;
    const inventoryLow = activeCount < minActiveAiArticles;

    // Time alone must not make a nearly-empty feed look healthy. When the
    // eligible AI inventory is below the configured floor, a normal stale
    // check is allowed to replenish it even if the last successful scan was
    // recent.
    const shouldRefresh = timeStale || inventoryLow || action === 'force_refresh';

    if (!shouldRefresh) {
      return jsonResponse({
        message: `AI Awareness is current with ${activeCount} active AI article${activeCount === 1 ? '' : 's'}.`,
        refreshed: false,
        success: true,
        activeCount,
        lastSuccessAt: successStamp,
      });
    }

    // Learner manual checks can replenish a low inventory, but repeated clicks
    // are globally throttled so one user cannot turn the button into a scraper.
    if (action === 'manual_check') {
      const cooldownMinutes = Math.max(
        1,
        Math.min(60, Number(settings.manual_check_cooldown_minutes ?? 10)),
      );
      const lastAttempt = settings.last_attempt_at
        ? new Date(String(settings.last_attempt_at))
        : null;
      if (
        lastAttempt &&
        !Number.isNaN(lastAttempt.getTime()) &&
        Date.now() - lastAttempt.getTime() < cooldownMinutes * 60_000
      ) {
        const remaining = Math.max(
          1,
          Math.ceil(
            (cooldownMinutes * 60_000 - (Date.now() - lastAttempt.getTime())) /
              60_000,
          ),
        );
        return jsonResponse({
          message: inventoryLow
            ? `A source check just ran. Try again in about ${remaining} minute${remaining === 1 ? '' : 's'} while PromptWise keeps the saved AI stories available.`
            : 'AI Awareness is already current.',
          refreshed: false,
          success: true,
          activeCount,
          lastSuccessAt: successStamp,
        });
      }
    }

    const attemptAt = new Date().toISOString();
    await service
      .from('awareness_feed_settings')
      .update({
        last_attempt_at: attemptAt,
        updated_at: attemptAt,
      })
      .eq('id', 1);

    const { data: runRow, error: runInsertError } = await service
      .from('awareness_refresh_runs')
      .insert({ status: 'running', started_at: attemptAt })
      .select('id')
      .single();
    if (runInsertError) throw runInsertError;
    const runId = String(runRow.id);

    try {
      const result = await refreshFeed({ service, settings });

      if (result.usable <= 0) {
        const message = result.providerWarnings.length > 0
          ? `Awareness discovery did not produce a usable trusted article. ${result.providerWarnings.join(' ')}`
          : 'Awareness discovery did not find a usable trusted article in the current search window.';

        await service
          .from('awareness_feed_settings')
          .update({
            last_error: message,
            updated_at: new Date().toISOString(),
          })
          .eq('id', 1);
        await finishRefreshRun(service, runId, 'failed', result, message);

        return jsonResponse({
          message,
          refreshed: false,
          success: false,
          ...result,
          warning: message,
        }, action === 'force_refresh' ? 503 : result.activeCount > 0 ? 200 : 503);
      }

      const completedAt = new Date().toISOString();
      await service
        .from('awareness_feed_settings')
        .update({
          last_refresh_at: completedAt,
          last_success_at: completedAt,
          last_success_count: result.usable,
          last_error: null,
          updated_at: completedAt,
        })
        .eq('id', 1);
      await finishRefreshRun(service, runId, 'completed', result, null);

      return jsonResponse({
        message:
          result.saved > 0
            ? `Awareness updated with ${result.saved} current article${result.saved === 1 ? '' : 's'}.`
            : 'Awareness check completed with current trusted articles.',
        refreshed: true,
        success: true,
        ...result,
      });
    } catch (refreshError) {
      const message = errorMessage(refreshError);
      const activeCount = await countActiveArticles(service);
      const failedStats: RefreshStats = {
        discovered: 0,
        trustedMatched: 0,
        usable: 0,
        saved: 0,
        philippines: 0,
        global: 0,
        activeCount,
        providerWarnings: [message],
      };
      await service
        .from('awareness_feed_settings')
        .update({
          last_error: message,
          updated_at: new Date().toISOString(),
        })
        .eq('id', 1);
      await finishRefreshRun(service, runId, 'failed', failedStats, message);
      throw refreshError;
    }
  } catch (error) {
    console.error('awareness-feed error', error);
    const message = errorMessage(error);

    // Learners may continue using cached rows, but an empty cache must never
    // hide a provider/configuration failure behind a normal empty-state message.
    if (
      action === 'refresh_if_stale' ||
      action === 'manual_check' ||
      action === 'scheduled_refresh'
    ) {
      let activeCount = 0;
      try {
        activeCount = await countActiveArticles(service);
      } catch {
        activeCount = 0;
      }
      if (activeCount > 0) {
        return jsonResponse({
          message: 'Using the most recently saved awareness updates.',
          refreshed: false,
          success: false,
          activeCount,
          warning: message,
        });
      }
      return jsonResponse({
        error: message,
        refreshed: false,
        success: false,
        activeCount: 0,
      }, 503);
    }
    return jsonResponse({ error: message, success: false }, 500);
  }
});

async function refreshFeed({
  service,
  settings,
}: {
  service: ReturnType<typeof createClient>;
  settings: JsonRecord;
}): Promise<RefreshStats> {
  const [{ data: sourceRows, error: sourceError }, { data: directRows, error: directError }] =
    await Promise.all([
      service
        .from('awareness_source_domains')
        .select('domain,name,region,trust_level')
        .eq('enabled', true),
      service
        .from('awareness_direct_sources')
        .select('id,name,base_domain,source_url,source_type,region,trust_level,priority,relevance_keywords')
        .eq('enabled', true)
        .order('priority', { ascending: false })
        .limit(Math.max(1, Math.min(20, Number(settings.direct_source_limit ?? 12)))),
    ]);
  if (sourceError) throw sourceError;
  if (directError) throw directError;

  const sources = (sourceRows ?? []).map((row) => ({
    domain: normalizeDomain(String(row.domain ?? '')),
    name: String(row.name ?? '').trim(),
    region: String(row.region ?? 'Global') === 'Philippines' ? 'Philippines' : 'Global',
    trust_level: Number(row.trust_level ?? 70),
  })) as SourceDomain[];

  const directSources = (directRows ?? []).map((row) => ({
    id: String(row.id ?? ''),
    name: String(row.name ?? '').trim(),
    base_domain: normalizeDomain(String(row.base_domain ?? '')),
    source_url: String(row.source_url ?? '').trim(),
    source_type: String(row.source_type ?? 'html_listing') === 'rss' ? 'rss' : 'html_listing',
    region: String(row.region ?? 'Global') === 'Philippines' ? 'Philippines' : 'Global',
    trust_level: Number(row.trust_level ?? 80),
    priority: Number(row.priority ?? 50),
    relevance_keywords: Array.isArray(row.relevance_keywords)
      ? row.relevance_keywords.map((item) => String(item).toLowerCase())
      : [],
  })) as DirectSource[];

  const maxPerRefresh = Math.max(8, Math.min(40, Number(settings.max_articles_per_refresh ?? 24)));
  const providerWarnings: string[] = [];

  // Direct trusted sources are the primary discovery path. They do not consume
  // Groq quota and avoid depending on one news-index provider.
  const directResults = await Promise.all(
    directSources.map((source) => fetchDirectSourceSafe(source)),
  );
  const directCandidates = directResults.flatMap((item) => item.candidates);
  providerWarnings.push(...directResults.flatMap((item) => item.warnings));


  // A dedicated PNA search pass gives us multiple recent Philippine AI stories
  // even when the latest-news RSS page has already pushed those stories out.
  const pnaSearch = await fetchPnaTargetedSearchSafe(sources);
  const pnaCandidates = pnaSearch.candidates;
  providerWarnings.push(...pnaSearch.warnings);

  if (directSources.length > 0) {
    // Persist source-check status in one database request instead of one write
    // per source. Omitted columns (such as enabled) are left unchanged.
    const now = new Date().toISOString();
    const sourceStatusRows = directSources.map((source, index) => ({
      id: source.id,
      name: source.name,
      base_domain: source.base_domain,
      source_url: source.source_url,
      source_type: source.source_type,
      region: source.region,
      trust_level: source.trust_level,
      priority: source.priority,
      relevance_keywords: source.relevance_keywords,
      last_checked_at: now,
      last_error: directResults[index].warnings.length > 0
        ? directResults[index].warnings.join(' ').slice(0, 900)
        : null,
      updated_at: now,
    }));
    const { error: sourceStatusError } = await service
      .from('awareness_direct_sources')
      .upsert(sourceStatusRows, { onConflict: 'id' });
    if (sourceStatusError) {
      providerWarnings.push(`Source status update failed: ${sourceStatusError.message}`);
    }
  }

  const minDirectBeforeFallback = Math.max(
    2,
    Math.min(20, Number(settings.min_direct_candidates_before_fallback ?? 8)),
  );
  const minPhDirectBeforeFallback = Math.max(
    1,
    Math.min(10, Number(settings.min_ph_direct_candidates_before_fallback ?? 3)),
  );

  // Generic publisher RSS feeds are useful but they only expose the newest
  // headlines. AI stories can easily fall off those feeds within hours. Use a
  // targeted, no-key news-search RSS layer to find AI-specific stories from
  // the same allowlisted publishers before falling back to GDELT.
  const initialCandidates = dedupeCandidates([...directCandidates, ...pnaCandidates]);
  const directPhilippinesCount = initialCandidates.filter(
    (candidate) => candidate.region === 'Philippines',
  ).length;
  const needsTargetedTotal = initialCandidates.length < minDirectBeforeFallback;
  const needsTargetedPhilippines = directPhilippinesCount < minPhDirectBeforeFallback;
  let bingCandidates: Candidate[] = [];

  if (needsTargetedTotal || needsTargetedPhilippines) {
    const [phBing, globalBing] = await Promise.all([
      fetchBingNewsRssSafe(BING_PH_QUERIES, sources, 'Philippines'),
      needsTargetedTotal
        ? fetchBingNewsRssSafe(BING_GLOBAL_QUERIES, sources, 'Global')
        : Promise.resolve({ candidates: [] as Candidate[], warnings: [] as string[] }),
    ]);
    providerWarnings.push(...phBing.warnings, ...globalBing.warnings);
    bingCandidates = dedupeCandidates([
      ...phBing.candidates,
      ...globalBing.candidates,
    ]);
  }

  const preGdeltCandidates = dedupeCandidates([
    ...directCandidates,
    ...pnaCandidates,
    ...bingCandidates,
  ]);
  const preGdeltPhilippinesCount = preGdeltCandidates.filter(
    (candidate) => candidate.region === 'Philippines',
  ).length;
  const needsTotalExpansion = preGdeltCandidates.length < minDirectBeforeFallback;
  const needsPhilippinesExpansion =
    preGdeltPhilippinesCount < minPhDirectBeforeFallback;
  let gdeltRows: GdeltArticle[] = [];

  // GDELT remains the final expander. It returns original publisher URLs, so
  // trusted-domain validation and Read Original still work even when the
  // direct feeds or search RSS provider are temporarily thin.
  if (needsTotalExpansion || needsPhilippinesExpansion) {
    const [phPrimary, globalPrimary] = await Promise.all([
      fetchGdeltSafe(PH_QUERY, 100, 'Philippines discovery fallback'),
      needsTotalExpansion
        ? fetchGdeltSafe(GLOBAL_QUERY, 70, 'Global discovery fallback')
        : Promise.resolve({ rows: [] as GdeltArticle[], warnings: [] as string[] }),
    ]);
    providerWarnings.push(...phPrimary.warnings, ...globalPrimary.warnings);

    const phPrimaryHasTrustedMatch = phPrimary.rows.some((row) => {
      const candidate = toCandidate(row, sources);
      return candidate?.region === 'Philippines';
    });
    const phFallback = !phPrimaryHasTrustedMatch
      ? await fetchGdeltSafe(PH_FALLBACK_QUERY, 100, 'Philippines trusted-domain fallback')
      : { rows: [] as GdeltArticle[], warnings: [] as string[] };
    providerWarnings.push(...phFallback.warnings);
    gdeltRows = [...phPrimary.rows, ...phFallback.rows, ...globalPrimary.rows];
  }

  const gdeltCandidates = gdeltRows
    .map((row) => toCandidate(row, sources))
    .filter((item): item is Candidate => item != null);

  const matched = [
    ...directCandidates,
    ...pnaCandidates,
    ...bingCandidates,
    ...gdeltCandidates,
  ];
  if (matched.length === 0 && providerWarnings.length > 0) {
    throw new Error(providerWarnings.join(' '));
  }

  const candidates = dedupeCandidates(matched)
    .sort((a, b) => b.relevanceScore - a.relevanceScore)
    .slice(0, maxPerRefresh);

  const existingSnapshots = new Map<string, JsonRecord>();
  if (candidates.length > 0) {
    const { data: snapshotRows, error: snapshotError } = await service
      .from('awareness_articles')
      .select(
        'source_url,summary,image_url,published_at,content_excerpt,content_fetch_status,content_fetched_at,content_hash,metadata',
      )
      .in('source_url', candidates.map((item) => item.url));
    if (snapshotError) throw snapshotError;
    for (const raw of snapshotRows ?? []) {
      const row = raw as JsonRecord;
      existingSnapshots.set(String(row.source_url ?? ''), row);
    }
  }

  const snapshotHours = Math.max(1, Math.min(168, Number(settings.article_snapshot_hours ?? 24)));
  const rows: JsonRecord[] = [];
  const batchSize = 4;
  for (let offset = 0; offset < candidates.length; offset += batchSize) {
    const batch = candidates.slice(offset, offset + batchSize);
    const built = await Promise.all(
      batch.map(async (candidate) => {
        const existing = existingSnapshots.get(candidate.url) ?? {};
        const previousFetchedAt = parseLooseDate(String(existing.content_fetched_at ?? ''));
        const previousExcerpt = String(existing.content_excerpt ?? '').trim();
        const snapshotFresh =
          previousExcerpt.length >= 250 &&
          previousFetchedAt != null &&
          Date.now() - previousFetchedAt.getTime() < snapshotHours * 3_600_000;

        const feedExcerpt = cleanText(candidate.sourceExcerpt ?? '').slice(0, 12_000);
        const feedImage = safeHttpUrl(candidate.imageUrl);
        // A sufficiently detailed RSS/search excerpt is already enough for
        // Awareness + grounded Verify generation. Do not refetch a whole news
        // page merely because its RSS item omitted an image; the UI has a safe
        // visual fallback and this saves many outbound requests.
        const feedSnapshotUsable =
          feedExcerpt.length >= 250 && candidate.publishedAt != null;
        const meta = snapshotFresh
          ? {
              description: String(existing.summary ?? ''),
              imageUrl: safeHttpUrl(String(existing.image_url ?? '')),
              language: null as string | null,
              articleText: previousExcerpt,
              publishedAt: parseLooseDate(String(existing.published_at ?? ''))?.toISOString() ?? null,
            }
          : feedSnapshotUsable
            ? {
                description: feedExcerpt.slice(0, 900),
                imageUrl: feedImage,
                language: null as string | null,
                articleText: feedExcerpt,
                publishedAt: candidate.publishedAt,
              }
            : await fetchArticleMeta(candidate.url);

        const imageUrl = feedImage ?? safeHttpUrl(meta.imageUrl);
        const summary =
          cleanSummary(meta.description) ||
          cleanSummary(feedExcerpt.slice(0, 900)) ||
          fallbackSummary(candidate);
        const pageText = meta.articleText.slice(0, 12_000);
        const freshlyFetched = pageText.length >= 250 ? pageText : feedExcerpt;
        const contentExcerpt =
          freshlyFetched.length >= 250
            ? freshlyFetched
            : previousExcerpt.length >= 250
              ? previousExcerpt
              : freshlyFetched;
        const contentStatus =
          contentExcerpt.length >= 250
            ? 'usable'
            : contentExcerpt.length > 0
              ? 'insufficient'
              : 'unavailable';
        const contentHash = contentExcerpt.length >= 250
          ? !snapshotFresh && freshlyFetched.length >= 250
            ? await sha256(contentExcerpt)
            : String(existing.content_hash ?? '').trim() || await sha256(contentExcerpt)
          : null;
        const contentFetchedAt = snapshotFresh
          ? String(existing.content_fetched_at ?? '')
          : new Date().toISOString();
        const publishedAt = candidate.publishedAt ?? meta.publishedAt;

        return {
          title: candidate.title.slice(0, 400),
          summary: summary.slice(0, 900),
          why_it_matters: whyItMatters(candidate.category),
          source_name: candidate.sourceName,
          source_domain: candidate.sourceDomain,
          source_url: candidate.url,
          image_url: imageUrl,
          published_at: publishedAt,
          discovered_at: new Date().toISOString(),
          category: candidate.category,
          region: candidate.region,
          source_country: candidate.sourceCountry,
          trust_level: candidate.trustLevel,
          relevance_score: candidate.relevanceScore,
          ai_relevance_score: candidate.aiRelevanceScore,
          is_active: candidate.aiRelevanceScore >= 4,
          last_seen_at: new Date().toISOString(),
          content_excerpt: contentExcerpt,
          content_fetch_status: contentStatus,
          content_fetched_at: contentFetchedAt,
          content_hash: contentHash,
          metadata: {
            provider: candidate.provider,
            article_language: meta.language,
            snapshot_reused: snapshotFresh,
            ai_relevance_score: candidate.aiRelevanceScore,
            ai_relevance_basis: 'title_and_feed_summary',
          },
          updated_at: new Date().toISOString(),
        } as JsonRecord;
      }),
    );
    rows.push(...built);
  }

  let saved = 0;
  if (rows.length > 0) {
    const { error: upsertError } = await service
      .from('awareness_articles')
      .upsert(rows, { onConflict: 'source_url' });
    if (upsertError) throw upsertError;
    saved = rows.length;
  }

  const staleDays = Math.max(14, Number(settings.archive_after_days ?? 45));
  const staleCutoff = new Date(Date.now() - staleDays * 86_400_000).toISOString();
  await service
    .from('awareness_articles')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .lt('published_at', staleCutoff)
    .eq('is_active', true);

  // Defense in depth: a historical/bad row can never remain learner-visible
  // merely because is_active was left true by an older deployment.
  await service
    .from('awareness_articles')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .lt('ai_relevance_score', 4)
    .eq('is_active', true);

  const maxActive = Math.max(50, Number(settings.max_active_articles ?? 200));
  const { data: overflowRows } = await service
    .from('awareness_articles')
    .select('id')
    .eq('is_active', true)
    .gte('ai_relevance_score', 4)
    .order('ai_relevance_score', { ascending: false })
    .order('relevance_score', { ascending: false })
    .order('published_at', { ascending: false })
    .range(maxActive, maxActive + 500);
  const overflowIds = (overflowRows ?? []).map((row) => String(row.id));
  if (overflowIds.length > 0) {
    await service
      .from('awareness_articles')
      .update({ is_active: false, updated_at: new Date().toISOString() })
      .in('id', overflowIds);
  }

  const activeCount = await countActiveArticles(service);

  return {
    discovered:
      directCandidates.length + pnaCandidates.length + bingCandidates.length + gdeltRows.length,
    trustedMatched: matched.length,
    usable: candidates.length,
    saved,
    philippines: candidates.filter((item) => item.region === 'Philippines').length,
    global: candidates.filter((item) => item.region === 'Global').length,
    activeCount,
    providerWarnings,
  };
}

async function fetchPnaTargetedSearchSafe(
  sources: SourceDomain[],
): Promise<{ candidates: Candidate[]; warnings: string[] }> {
  const pna = sources.find((source) => source.domain === 'pna.gov.ph');
  if (!pna) {
    return {
      candidates: [],
      warnings: ['PNA targeted search skipped because pna.gov.ph is not enabled in trusted domains.'],
    };
  }

  const results = await Promise.all(
    PNA_AI_SEARCH_URLS.map(async (url, index) => {
      const source: DirectSource = {
        id: `pna-ai-search-${index}`,
        name: 'Philippine News Agency - AI Search',
        base_domain: 'pna.gov.ph',
        source_url: url,
        source_type: 'html_listing',
        region: 'Philippines',
        trust_level: pna.trust_level,
        priority: 100,
        relevance_keywords: [],
      };
      try {
        return {
          candidates: await fetchHtmlListingSource(source),
          warning: null as string | null,
        };
      } catch (error) {
        return {
          candidates: [] as Candidate[],
          warning: `PNA AI search failed: ${errorMessage(error)}`,
        };
      }
    }),
  );

  return {
    candidates: dedupeCandidates(results.flatMap((item) => item.candidates)).slice(0, 24),
    warnings: results
      .map((item) => item.warning)
      .filter((item): item is string => item != null && item.length > 0),
  };
}

async function fetchDirectSourceSafe(
  source: DirectSource,
): Promise<{ candidates: Candidate[]; warnings: string[] }> {
  try {
    const candidates = source.source_type === 'rss'
      ? await fetchRssSource(source)
      : await fetchHtmlListingSource(source);
    return { candidates, warnings: [] };
  } catch (error) {
    const message = `${source.name} failed: ${errorMessage(error)}`;
    console.warn(message);
    return { candidates: [], warnings: [message] };
  }
}

async function fetchHtmlListingSource(source: DirectSource): Promise<Candidate[]> {
  const response = await fetchWithTimeout(source.source_url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; PromptWise-Awareness/1.1)',
      Accept: 'text/html,application/xhtml+xml',
    },
  }, 10_000);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  const html = (await response.text()).slice(0, 1_500_000);
  const candidates: Candidate[] = [];
  const anchorPattern = /<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let match: RegExpExecArray | null;
  while ((match = anchorPattern.exec(html)) != null) {
    const title = cleanText(match[2]);
    if (title.length < 18 || title.length > 320) continue;
    const url = resolveHttpUrl(match[1], source.source_url);
    if (!url) continue;
    const domain = normalizeDomain(new URL(url).hostname);
    if (!(domain === source.base_domain || domain.endsWith(`.${source.base_domain}`))) continue;
    if (!looksLikeArticleUrl(url, source.base_domain)) continue;
    if (!aiTopicEvidence(title, '').eligible) continue;
    candidates.push(candidateFromDirect({ source, title, url, publishedAt: null }));
    if (candidates.length >= 30) break;
  }
  return dedupeCandidates(candidates).slice(0, 20);
}

async function fetchRssSource(source: DirectSource): Promise<Candidate[]> {
  const response = await fetchWithTimeout(source.source_url, {
    headers: {
      'User-Agent': 'PromptWise-Awareness/1.1',
      Accept: 'application/rss+xml,application/atom+xml,application/xml,text/xml',
    },
  }, 10_000);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  const xml = (await response.text()).slice(0, 2_000_000);
  const chunks = xml.match(/<item\b[\s\S]*?<\/item>/gi) ?? xml.match(/<entry\b[\s\S]*?<\/entry>/gi) ?? [];
  const candidates: Candidate[] = [];
  for (const chunk of chunks.slice(0, 60)) {
    const title = cleanText(xmlTag(chunk, 'title'));
    if (!title) continue;
    const rawLink = xmlTag(chunk, 'link') || xmlLinkHref(chunk);
    const url = resolveHttpUrl(rawLink, source.source_url);
    if (!url) continue;
    const publishedAt = parseLooseDate(
      xmlTag(chunk, 'pubDate') || xmlTag(chunk, 'published') || xmlTag(chunk, 'updated'),
    )?.toISOString() ?? null;
    const sourceExcerpt = cleanText(
      xmlTag(chunk, 'content:encoded') ||
        xmlTag(chunk, 'description') ||
        xmlTag(chunk, 'summary'),
    ).slice(0, 12_000);
    const imageUrl = rssImageUrl(chunk, source.source_url);
    if (!aiTopicEvidence(title, sourceExcerpt).eligible) {
      continue;
    }
    candidates.push(
      candidateFromDirect({ source, title, url, publishedAt, sourceExcerpt, imageUrl }),
    );
  }
  return dedupeCandidates(candidates).slice(0, 20);
}

function candidateFromDirect({
  source,
  title,
  url,
  publishedAt,
  sourceExcerpt = '',
  imageUrl = null,
}: {
  source: DirectSource;
  title: string;
  url: string;
  publishedAt: string | null;
  sourceExcerpt?: string;
  imageUrl?: string | null;
}): Candidate {
  const category = classify(`${title} ${sourceExcerpt} ${url}`);
  const ageHours = publishedAt
    ? Math.max(0, (Date.now() - new Date(publishedAt).getTime()) / 3_600_000)
    : 48;
  const freshness = Math.max(0, Math.round(28 - Math.min(28, ageHours / 6)));
  const regionBoost = source.region === 'Philippines' ? 24 : 4;
  const priorityBoost = Math.round(source.priority * 0.08);
  const aiEvidence = aiTopicEvidence(title, sourceExcerpt);
  const aiScore = aiEvidence.score;
  const relevanceScore = Math.min(
    100,
    Math.round(
      source.trust_level * 0.38 +
        freshness +
        regionBoost +
        priorityBoost +
        Math.min(18, aiScore * 1.5) +
        urgencyScore(title),
    ),
  );
  return {
    title,
    url,
    imageUrl: safeHttpUrl(imageUrl),
    publishedAt,
    sourceDomain: source.base_domain,
    sourceName: source.name.replace(
      /\s+-\s+(National|Latest|RSS|Science and Technology|SciTech|Money|AI Search)$/i,
      '',
    ),
    sourceCountry: source.region === 'Philippines' ? 'Philippines' : '',
    region: source.region,
    trustLevel: source.trust_level,
    category,
    relevanceScore,
    aiRelevanceScore: aiScore,
    provider: source.source_type === 'rss' ? 'Direct RSS' : 'Direct trusted page',
    sourceExcerpt,
  };
}

function aiAwarenessRelevanceScore(input: string): number {
  const text = cleanText(input).toLowerCase();
  if (!text) return 0;

  let score = 0;

  // Strong AI anchors. Generic scam/fake-news/cybersecurity words do not
  // qualify on their own anymore. This keeps AI Awareness genuinely about AI.
  if (/\bartificial intelligence\b/.test(text)) score += 6;
  if (/\bgenerative ai\b|\bgenai\b/.test(text)) score += 6;
  if (/\bdeep[ -]?fake(s)?\b/.test(text)) score += 7;
  if (/\bsynthetic media\b/.test(text)) score += 7;
  if (/\bvoice clon(e|ed|ing)?\b|\bcloned voice\b/.test(text)) score += 7;
  if (/\bai[- ]generated\b|\bai[- ]made\b|\bai[- ]created\b/.test(text)) score += 6;
  if (/\bai[- ]powered\b|\bai[- ]driven\b|\bai[- ]assisted\b/.test(text)) score += 5;
  if (/(^|[^a-z0-9])ai([^a-z0-9]|$)/.test(text)) score += 4;

  // Named mainstream AI systems are useful anchors even when the headline
  // omits the words "artificial intelligence".
  if (/\bchatgpt\b|\bopenai\b|\bgoogle gemini\b|\bgemini ai\b|\bgoogle ai\b|\bclaude ai\b|\banthropic\b|\bcopilot\b|\bgrok\b|\bmeta ai\b|\bllm(s)?\b|\blarge language model(s)?\b/.test(text)) {
    score += 4;
  }

  const hasAiAnchor = score >= 4;
  if (!hasAiAnchor) return 0;

  // Risk/verification context raises priority, but never makes a non-AI story
  // eligible by itself.
  if (/misinformation|disinformation|fake news|false claim|fact.?check|misleading/.test(text)) score += 3;
  if (/scam|fraud|phish|impersonat|social engineering|investment scheme/.test(text)) score += 3;
  if (/privacy|personal data|identity|biometric|face|consent/.test(text)) score += 2;
  if (/cyber|malware|ransomware|hack|security|abuse|misuse|safety/.test(text)) score += 2;
  if (/regulat|policy|law|ban|governance|copyright|election/.test(text)) score += 1;

  return Math.min(20, score);
}

function aiTopicEvidence(title: string, excerpt: string): {
  eligible: boolean;
  score: number;
  titleScore: number;
  excerptScore: number;
} {
  const titleScore = aiAwarenessRelevanceScore(title);
  // Only the beginning of an RSS/search description is considered for topic
  // eligibility. Full article bodies can contain navigation, related-story
  // links, or generic site text mentioning AI and must not make an unrelated
  // story eligible.
  const excerptScore = aiAwarenessRelevanceScore(cleanText(excerpt).slice(0, 700));
  const eligible = titleScore >= 4 || (titleScore === 0 && excerptScore >= 7);
  const score = eligible
    ? Math.min(20, Math.max(titleScore, excerptScore) + Math.min(6, titleScore))
    : 0;
  return { eligible, score, titleScore, excerptScore };
}

function isAiAwarenessRelevant(input: string): boolean {
  return aiAwarenessRelevanceScore(input) >= 4;
}

function looksLikeArticleUrl(url: string, domain: string): boolean {
  const path = new URL(url).pathname.toLowerCase();
  if (domain === 'pna.gov.ph') return /\/articles\/\d+/.test(path);
  if (domain === 'gmanetwork.com') return /\/news\/.+\/story\//.test(path);
  if (domain === 'consumer.ftc.gov') return /\/consumer-alerts\//.test(path);
  return path.split('/').filter(Boolean).length >= 2;
}

function resolveHttpUrl(value: string, base: string): string | null {
  const cleaned = decodeHtml(value).trim();
  if (!cleaned || cleaned.startsWith('#') || cleaned.startsWith('javascript:')) return null;
  try {
    const url = new URL(cleaned, base);
    return url.protocol === 'http:' || url.protocol === 'https:' ? normalizeUrl(url.toString()) : null;
  } catch {
    return null;
  }
}

function xmlTag(chunk: string, tag: string): string {
  const escaped = tag.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`<${escaped}\\b[^>]*>([\\s\\S]*?)<\\/${escaped}>`, 'i').exec(chunk);
  return decodeHtml((match?.[1] ?? '').replace(/^<!\[CDATA\[|\]\]>$/g, ''));
}

function xmlLinkHref(chunk: string): string {
  return /<link\b[^>]*href=["']([^"']+)["']/i.exec(chunk)?.[1] ?? '';
}

function rssImageUrl(chunk: string, base: string): string | null {
  const patterns = [
    /<media:content\b[^>]*\burl=["']([^"']+)["']/i,
    /<media:thumbnail\b[^>]*\burl=["']([^"']+)["']/i,
    /<enclosure\b[^>]*\burl=["']([^"']+)["'][^>]*(?:type=["']image\/[^"']+["'])?/i,
  ];
  for (const pattern of patterns) {
    const value = pattern.exec(chunk)?.[1];
    if (!value) continue;
    const resolved = resolveHttpUrl(value, base);
    if (resolved) return resolved;
  }
  return null;
}

async function fetchBingNewsRssSafe(
  queries: string[],
  sources: SourceDomain[],
  preferredRegion: 'Philippines' | 'Global',
): Promise<{ candidates: Candidate[]; warnings: string[] }> {
  const results = await Promise.all(
    queries.slice(0, 4).map(async (query) => {
      try {
        return {
          candidates: await fetchBingNewsRss(query, sources, preferredRegion),
          warning: null as string | null,
        };
      } catch (error) {
        return {
          candidates: [] as Candidate[],
          warning: `Targeted news search failed for ${query}: ${errorMessage(error)}`,
        };
      }
    }),
  );
  return {
    candidates: dedupeCandidates(results.flatMap((item) => item.candidates)),
    warnings: results
      .map((item) => item.warning)
      .filter((item): item is string => item != null && item.length > 0),
  };
}

async function fetchBingNewsRss(
  query: string,
  sources: SourceDomain[],
  preferredRegion: 'Philippines' | 'Global',
): Promise<Candidate[]> {
  const params = new URLSearchParams({
    q: query,
    format: 'rss',
    mkt: 'en-PH',
  });
  const response = await fetchWithTimeout(
    `https://www.bing.com/news/search?${params.toString()}`,
    {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; PromptWise-Awareness/1.2)',
        Accept: 'application/rss+xml,application/xml,text/xml',
      },
    },
    12_000,
  );
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  const xml = (await response.text()).slice(0, 2_000_000);
  const chunks = xml.match(/<item\b[\s\S]*?<\/item>/gi) ?? [];
  const candidates: Candidate[] = [];

  for (const chunk of chunks.slice(0, 25)) {
    const title = cleanText(xmlTag(chunk, 'title'));
    const description = cleanText(xmlTag(chunk, 'description')).slice(0, 3000);
    if (!title || !aiTopicEvidence(title, description).eligible) continue;

    const rawLink = xmlTag(chunk, 'link') || xmlLinkHref(chunk);
    const url = extractBingOriginalUrl(rawLink);
    if (!url) continue;

    const domain = normalizeDomain(new URL(url).hostname);
    const source = findSource(domain, sources);
    if (!source) continue;
    if (preferredRegion === 'Philippines' && source.region !== 'Philippines') {
      continue;
    }

    const publishedAt = parseLooseDate(
      xmlTag(chunk, 'pubDate') || xmlTag(chunk, 'published') || xmlTag(chunk, 'updated'),
    )?.toISOString() ?? null;
    const evidence = aiTopicEvidence(title, description);
    const ageHours = publishedAt
      ? Math.max(0, (Date.now() - new Date(publishedAt).getTime()) / 3_600_000)
      : 72;
    const freshness = Math.max(0, Math.round(28 - Math.min(28, ageHours / 6)));
    const regionBoost = source.region === 'Philippines' ? 24 : 4;
    const relevanceScore = Math.min(
      100,
      Math.round(
        source.trust_level * 0.38 +
          freshness +
          regionBoost +
          Math.min(18, evidence.score * 1.5) +
          urgencyScore(title),
      ),
    );

    candidates.push({
      title,
      url,
      imageUrl: rssImageUrl(chunk, 'https://www.bing.com/'),
      publishedAt,
      sourceDomain: source.domain,
      sourceName: source.name || source.domain,
      sourceCountry: source.region === 'Philippines' ? 'Philippines' : '',
      region: source.region,
      trustLevel: source.trust_level,
      category: classify(`${title} ${description}`),
      relevanceScore,
      aiRelevanceScore: evidence.score,
      provider: 'Bing News RSS discovery',
      sourceExcerpt: description,
    });
  }

  return dedupeCandidates(candidates).slice(0, 30);
}

function extractBingOriginalUrl(rawLink: string): string | null {
  const direct = safeHttpUrl(decodeHtml(rawLink));
  if (!direct) return null;
  try {
    const parsed = new URL(direct);
    const host = normalizeDomain(parsed.hostname);
    if (host === 'bing.com' || host.endsWith('.bing.com')) {
      const embedded = parsed.searchParams.get('url');
      if (embedded) {
        return safeHttpUrl(embedded);
      }
    }
    return direct;
  } catch {
    return null;
  }
}

async function fetchGdeltSafe(
  query: string,
  maxRecords: number,
  label: string,
): Promise<{ rows: GdeltArticle[]; warnings: string[] }> {
  try {
    return { rows: await fetchGdelt(query, maxRecords), warnings: [] };
  } catch (error) {
    const message = `${label} failed: ${errorMessage(error)}`;
    console.warn(message);
    return { rows: [], warnings: [message] };
  }
}

async function fetchGdelt(query: string, maxRecords: number): Promise<GdeltArticle[]> {
  const params = new URLSearchParams({
    query,
    mode: 'artlist',
    format: 'json',
    maxrecords: String(Math.min(250, Math.max(10, maxRecords))),
    timespan: '30d',
    sort: 'hybridrel',
  });
  const url = `https://api.gdeltproject.org/api/v2/doc/doc?${params.toString()}`;
  const response = await fetchWithTimeout(url, {
    headers: {
      'User-Agent': 'PromptWise-Awareness/1.0',
      Accept: 'application/json',
    },
  }, 15_000);
  if (!response.ok) {
    throw new Error(`News discovery returned HTTP ${response.status}.`);
  }
  const data = (await response.json()) as JsonRecord;
  const rows = Array.isArray(data.articles)
    ? data.articles
    : Array.isArray(data.results)
      ? data.results
      : [];
  return rows.filter((row): row is GdeltArticle => typeof row === 'object' && row != null);
}

function toCandidate(row: GdeltArticle, sources: SourceDomain[]): Candidate | null {
  const title = cleanText(row.title ?? '');
  const url = safeHttpUrl(row.url ?? row.url_mobile ?? '');
  const sourceDomain = normalizeDomain(row.domain ?? (url ? new URL(url).hostname : ''));
  if (!title || !url || !sourceDomain) return null;

  const source = findSource(sourceDomain, sources);
  if (!source) return null;

  const aiScore = aiAwarenessRelevanceScore(title);
  if (aiScore < 4) return null;

  const category = classify(`${title} ${url}`);
  const sourceCountry = cleanText(row.sourcecountry ?? '');
  const region: 'Philippines' | 'Global' =
    source.region === 'Philippines' || /philipp/i.test(sourceCountry)
      ? 'Philippines'
      : 'Global';
  const publishedAt = parseGdeltDate(row.seendate ?? '');
  const ageHours = publishedAt
    ? Math.max(0, (Date.now() - new Date(publishedAt).getTime()) / 3_600_000)
    : 168;
  const freshness = Math.max(0, Math.round(28 - Math.min(28, ageHours / 6)));
  const regionBoost = region === 'Philippines' ? 22 : 4;
  const imageBoost = safeHttpUrl(row.socialimage ?? '') ? 5 : 0;
  const urgency = urgencyScore(title);
  const relevanceScore = Math.min(
    100,
    Math.round(
      source.trust_level * 0.38 +
        freshness +
        regionBoost +
        imageBoost +
        Math.min(18, aiScore * 1.5) +
        urgency,
    ),
  );

  return {
    title,
    url,
    imageUrl: safeHttpUrl(row.socialimage ?? ''),
    publishedAt,
    sourceDomain,
    sourceName: source.name || sourceDomain,
    sourceCountry,
    region,
    trustLevel: source.trust_level,
    category,
    relevanceScore,
    aiRelevanceScore: aiScore,
    provider: 'GDELT DOC 2.0',
  };
}

function findSource(domain: string, sources: SourceDomain[]): SourceDomain | null {
  for (const source of sources) {
    if (domain === source.domain || domain.endsWith(`.${source.domain}`)) {
      return source;
    }
  }
  return null;
}

function dedupeCandidates(items: Candidate[]): Candidate[] {
  const byUrl = new Map<string, Candidate>();
  const titleKeys = new Set<string>();
  for (const item of items) {
    const urlKey = normalizeUrl(item.url);
    const titleKey = item.title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim()
      .split(' ')
      .filter((word) => word.length > 3)
      .slice(0, 8)
      .join(' ');
    if (byUrl.has(urlKey) || (titleKey && titleKeys.has(titleKey))) continue;
    byUrl.set(urlKey, item);
    if (titleKey) titleKeys.add(titleKey);
  }
  return [...byUrl.values()];
}

async function fetchArticleMeta(url: string): Promise<{
  description: string;
  imageUrl: string | null;
  language: string | null;
  articleText: string;
  publishedAt: string | null;
}> {
  try {
    const response = await fetchWithTimeout(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; PromptWise-Awareness/1.1)',
        Accept: 'text/html,application/xhtml+xml',
      },
    }, 7_000);
    if (!response.ok) {
      return { description: '', imageUrl: null, language: null, articleText: '', publishedAt: null };
    }
    const html = (await response.text()).slice(0, 1_200_000);
    return {
      description: decodeHtml(
        metaContent(html, 'property', 'og:description') ||
          metaContent(html, 'name', 'description') ||
          metaContent(html, 'name', 'twitter:description'),
      ),
      imageUrl: safeHttpUrl(
        decodeHtml(
          metaContent(html, 'property', 'og:image') ||
            metaContent(html, 'name', 'twitter:image'),
        ),
      ),
      language: html.match(/<html[^>]+lang=["']([^"']+)["']/i)?.[1] ?? null,
      articleText: extractArticleText(html),
      publishedAt: extractPublishedAt(html),
    };
  } catch {
    return { description: '', imageUrl: null, language: null, articleText: '', publishedAt: null };
  }
}

function extractPublishedAt(html: string): string | null {
  const candidates = [
    metaContent(html, 'property', 'article:published_time'),
    metaContent(html, 'name', 'date'),
    metaContent(html, 'name', 'pubdate'),
    /["']datePublished["']\s*:\s*["']([^"']+)["']/i.exec(html)?.[1] ?? '',
  ];
  for (const value of candidates) {
    const parsed = parseLooseDate(value);
    if (parsed) return parsed.toISOString();
  }
  return null;
}

function parseLooseDate(value: string): Date | null {
  const cleaned = cleanText(value);
  if (!cleaned) return null;
  const compact = cleaned.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$/);
  const parsed = compact
    ? new Date(`${compact[1]}-${compact[2]}-${compact[3]}T${compact[4]}:${compact[5]}:${compact[6]}Z`)
    : new Date(cleaned);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function extractArticleText(html: string): string {
  return decodeHtml(
    html
      .replace(/<script\b[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style\b[\s\S]*?<\/style>/gi, ' ')
      .replace(/<nav\b[\s\S]*?<\/nav>/gi, ' ')
      .replace(/<footer\b[\s\S]*?<\/footer>/gi, ' ')
      .replace(/<aside\b[\s\S]*?<\/aside>/gi, ' ')
      .replace(/<[^>]+>/g, ' '),
  )
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 12_000);
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

async function countActiveArticles(
  service: ReturnType<typeof createClient>,
): Promise<number> {
  const { count, error } = await service
    .from('awareness_articles')
    .select('id', { count: 'exact', head: true })
    .eq('is_active', true)
    .gte('ai_relevance_score', 4);
  if (error) throw error;
  return Number(count ?? 0);
}

async function finishRefreshRun(
  service: ReturnType<typeof createClient>,
  runId: string,
  status: 'completed' | 'failed',
  stats: RefreshStats,
  error: string | null,
): Promise<void> {
  const { error: updateError } = await service
    .from('awareness_refresh_runs')
    .update({
      status,
      articles_discovered: stats.discovered,
      trusted_matched: stats.trustedMatched,
      articles_usable: stats.usable,
      articles_saved: stats.saved,
      active_articles: stats.activeCount,
      provider_warnings: stats.providerWarnings,
      error_message: error,
      completed_at: new Date().toISOString(),
    })
    .eq('id', runId);
  if (updateError) {
    console.warn('Could not finalize Awareness refresh run:', updateError.message);
  }
}

function metaContent(html: string, key: string, value: string): string {
  const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern1 = new RegExp(
    `<meta\\b[^>]*${key}=["']${escaped}["'][^>]*content=["']([^"']*)["'][^>]*>`,
    'i',
  );
  const pattern2 = new RegExp(
    `<meta\\b[^>]*content=["']([^"']*)["'][^>]*${key}=["']${escaped}["'][^>]*>`,
    'i',
  );
  return pattern1.exec(html)?.[1] ?? pattern2.exec(html)?.[1] ?? '';
}

function classify(input: string): string {
  const text = input.toLowerCase();
  if (/deep[ -]?fake|voice clon|synthetic media|ai[- ]generated (image|video|audio)|ai generated (image|video|audio)/.test(text)) {
    return 'deepfakes';
  }
  if (/scam|fraud|phish|impersonat|investment scheme|fake account|fake page|social engineering/.test(text)) {
    return 'scams';
  }
  if (/misinformation|disinformation|fake news|false claim|misleading|fabricated/.test(text)) {
    return /fact.?check|verify|verification/.test(text) ? 'fact_checking' : 'fake_news';
  }
  if (/fact.?check|verify|verification|provenance|authenticity|detect/.test(text)) {
    return 'fact_checking';
  }
  if (/privacy|personal data|identity theft|biometric|consent|data leak/.test(text)) {
    return 'privacy';
  }
  if (/cybersecurity|cyberattack|malware|ransomware|hack|security vulnerab/.test(text)) {
    return 'cybersecurity';
  }
  return 'ai_misuse';
}

function whyItMatters(category: string): string {
  switch (category) {
    case 'scams':
      return 'AI can make fake identities, messages, images, and voices much more convincing. Verify the person or organization through an official channel before acting.';
    case 'deepfakes':
      return 'AI-generated or manipulated media can imitate real people. A realistic image, video, or voice is not proof that an event actually happened.';
    case 'fake_news':
      return 'Generative AI can create persuasive false claims and media quickly. Check the original source, date, and independent evidence before sharing.';
    case 'privacy':
      return 'AI systems can reuse faces, voices, and personal data in ways users may not expect. Be careful about what personal information you upload or share.';
    case 'fact_checking':
      return 'AI-generated content is easier to verify when you trace the original source, inspect context, and compare it with independent reliable evidence.';
    case 'cybersecurity':
      return 'AI can strengthen phishing, impersonation, and other cyber threats. Treat realistic-looking messages and media as claims that still need verification.';
    case 'ai_misuse':
    default:
      return 'AI can create useful content as well as convincing mistakes or abuse. Check the source, purpose, and evidence before trusting or sharing it.';
  }
}

function fallbackSummary(candidate: Candidate): string {
  return `A current AI-related ${labelCategory(candidate.category).toLowerCase()} update from ${candidate.sourceName}. Open the original article for the full report and source details.`;
}

function labelCategory(category: string): string {
  return category.replaceAll('_', ' ');
}

function urgencyScore(title: string): number {
  const text = title.toLowerCase();
  let score = 0;
  for (const word of ['warn', 'warning', 'advisory', 'scam', 'fraud', 'deepfake', 'phishing', 'fake', 'impersonat']) {
    if (text.includes(word)) score += 2;
  }
  return Math.min(12, score);
}

async function requireUser(
  req: Request,
  service: ReturnType<typeof createClient>,
): Promise<{ id: string }> {
  const auth = req.headers.get('authorization') ?? '';
  const token = auth.replace(/^Bearer\s+/i, '').trim();
  if (!token) throw new Error('Authentication required.');
  const { data, error } = await service.auth.getUser(token);
  if (error || !data.user) throw new Error('Authentication required.');
  return { id: data.user.id };
}

async function requireSchedulerSecret(
  req: Request,
  service: ReturnType<typeof createClient>,
): Promise<void> {
  const provided = (req.headers.get('x-automation-secret') ?? '').trim();
  if (!provided) throw new Error('Automation authentication required.');

  const { data, error } = await service
    .from('automation_scheduler_config')
    .select('scheduler_secret,enabled')
    .eq('id', 1)
    .single();
  if (error || data?.enabled !== true) {
    throw new Error('Awareness scheduler is not configured.');
  }
  const expected = String(data.scheduler_secret ?? '').trim();
  if (!expected || provided !== expected) {
    throw new Error('Automation authentication required.');
  }
}

async function requireAdmin(
  userId: string,
  service: ReturnType<typeof createClient>,
): Promise<void> {
  const { data, error } = await service
    .from('profiles')
    .select('role')
    .eq('id', userId)
    .single();
  if (error || data?.role !== 'administrator') {
    throw new Error('Administrator access required.');
  }
}

function parseGdeltDate(value: string): string | null {
  const cleaned = value.trim();
  if (!cleaned) return null;
  const compact = cleaned.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$/);
  if (compact) {
    return `${compact[1]}-${compact[2]}-${compact[3]}T${compact[4]}:${compact[5]}:${compact[6]}Z`;
  }
  const parsed = new Date(cleaned);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function cleanSummary(value: string): string {
  const text = cleanText(value);
  if (text.length < 35) return '';
  return text;
}

function cleanText(value: string): string {
  return decodeHtml(value)
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeHtml(value: string): string {
  return value
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)));
}

function normalizeDomain(value: string): string {
  return value.trim().toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').split('/')[0];
}

function normalizeUrl(value: string): string {
  try {
    const url = new URL(value);
    url.hash = '';
    for (const key of [...url.searchParams.keys()]) {
      if (/^utm_|fbclid|gclid/i.test(key)) url.searchParams.delete(key);
    }
    return url.toString();
  } catch {
    return value;
  }
}

function safeHttpUrl(value: string | null | undefined): string | null {
  const text = value?.trim() ?? '';
  if (!text) return null;
  try {
    const url = new URL(text);
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
