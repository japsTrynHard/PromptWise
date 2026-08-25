import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const COMMONS_API = "https://commons.wikimedia.org/w/api.php";

const COMMONS_QUERY_CACHE_TTL_MS = 15 * 60 * 1000;

const THUMBNAIL_WIDTH = 720;

type JsonRecord = Record<string, unknown>;

type SupabaseAdmin = ReturnType<typeof createClient>;

type CommonsImage = {
  id: string;
  title: string;
  imageUrl: string;
  sourcePageUrl: string;
  creator: string;
  license: string;
  labeledAiGenerated: boolean;
};

const commonsQueryCache = new Map<
  string,
  {
    expiresAt: number;
    items: CommonsImage[];
  }
>();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return json(
      {
        message: "Method not allowed.",
      },
      405,
    );
  }

  try {
    const supabaseUrl = requireEnv("SUPABASE_URL");

    const serviceRole = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

    const client = createClient(supabaseUrl, serviceRole, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });

    const userId = await requireUser(req, client);

    let body: JsonRecord = {};

    try {
      body = (await req.json()) as JsonRecord;
    } catch {
      body = {};
    }

    const count = clampNumber(body.count, 3, 8, 5);

    const seenIds = new Set<string>(
      Array.isArray(body.seen_ids)
        ? body.seen_ids.map((value) => String(value)).slice(0, 80)
        : [],
    );

    /*
     * OLD:
     *
     * topic
     * ↓
     * AI Commons search
     * ↓
     * Photo Commons search
     * ↓
     * HEAD image check
     * ↓
     * repeat for several topics
     *
     * NEW:
     *
     * AI image pool ──────┐
     *                     ├─ parallel
     * photo image pool ───┘
     *        ↓
     * pair locally
     *        ↓
     * return rounds
     *
     * Much fewer network calls.
     */

    const offsetSeed = Math.floor(Math.random() * 180);

    const recentExposurePromise = loadRecentExposure(client, userId);

    const firstPoolsPromise = Promise.all([
      searchCommonsPool({
        aiExpected: true,
        offset: offsetSeed,
      }),

      searchCommonsPool({
        aiExpected: false,
        offset: offsetSeed,
      }),
    ]);

    const [recentExposure, firstPools] = await Promise.all([
      recentExposurePromise,
      firstPoolsPromise,
    ]);

    for (const id of recentExposure) {
      seenIds.add(id);
    }

    let aiImages = firstPools[0];

    let realImages = firstPools[1];

    let rounds = buildRounds({
      aiImages,
      realImages,
      count,
      seenIds,
    });

    /*
     * Only one extra fallback
     * pool is requested when the
     * first result does not contain
     * enough usable images.
     */
    if (rounds.length < count) {
      const initialBucket = Math.floor(offsetSeed / 30) * 30;

      const fallbackOffset = initialBucket === 0 ? 210 : 0;

      const [moreAi, moreReal] = await Promise.all([
        searchCommonsPool({
          aiExpected: true,
          offset: fallbackOffset,
        }),

        searchCommonsPool({
          aiExpected: false,
          offset: fallbackOffset,
        }),
      ]);

      aiImages = dedupeImages([...aiImages, ...moreAi]);

      realImages = dedupeImages([...realImages, ...moreReal]);

      rounds = buildRounds({
        aiImages,
        realImages,
        count,
        seenIds,
      });
    }

    if (rounds.length < 2) {
      return json(
        {
          message:
            "Fresh image examples could not be prepared right now. Please try again in a moment.",

          rounds,
        },
        503,
      );
    }

    await recordExposure(client, userId, rounds);

    return json({
      rounds,

      source: "Wikimedia Commons",

      strategy: "pooled_parallel_fetch",
    });
  } catch (error) {
    console.error(error);

    const status = error instanceof HttpError ? error.status : 500;

    return json(
      {
        message: errorMessage(error),
      },
      status,
    );
  }
});

async function requireUser(
  req: Request,
  client: SupabaseAdmin,
): Promise<string> {
  const authHeader = req.headers.get("authorization") ?? "";

  const token = authHeader.replace(/^Bearer\s+/i, "").trim();

  if (!token) {
    throw new HttpError(401, "Please sign in again to continue.");
  }

  const { data, error } = await client.auth.getUser(token);

  if (error || !data.user) {
    throw new HttpError(401, "Your session expired. Please sign in again.");
  }

  return data.user.id;
}

async function loadRecentExposure(
  client: SupabaseAdmin,
  userId: string,
): Promise<string[]> {
  try {
    const { data, error } = await client
      .from("verification_media_exposure")
      .select("media_id")
      .eq("user_id", userId)
      .order("last_seen_at", {
        ascending: false,
      })
      .limit(100);

    if (error) {
      console.warn(
        "Could not read verification media exposure:",
        error.message,
      );

      return [];
    }

    return (data ?? [])
      .map((row) => String(row.media_id ?? "").trim())
      .filter(Boolean);
  } catch (error) {
    console.warn("Could not read verification media exposure:", error);

    return [];
  }
}

async function recordExposure(
  client: SupabaseAdmin,
  userId: string,
  rounds: JsonRecord[],
): Promise<void> {
  const mediaIds = new Set<string>();

  for (const round of rounds) {
    const imageA = asRecord(round.image_a);

    const imageB = asRecord(round.image_b);

    const roundId = String(round.id ?? "").trim();

    const imageAId = String(imageA.id ?? "").trim();

    const imageBId = String(imageB.id ?? "").trim();

    if (roundId) {
      mediaIds.add(roundId);
    }

    if (imageAId) {
      mediaIds.add(imageAId);
    }

    if (imageBId) {
      mediaIds.add(imageBId);
    }
  }

  if (mediaIds.size === 0) {
    return;
  }

  try {
    const now = new Date().toISOString();

    const payload = [...mediaIds].map((mediaId) => ({
      user_id: userId,
      media_id: mediaId,
      last_seen_at: now,
    }));

    const { error } = await client
      .from("verification_media_exposure")
      .upsert(payload, {
        onConflict: "user_id,media_id",
      });

    if (error) {
      console.warn(
        "Could not save verification media exposure:",
        error.message,
      );
    }
  } catch (error) {
    console.warn("Could not save verification media exposure:", error);
  }
}

async function searchCommonsPool({
  aiExpected,
  offset,
}: {
  aiExpected: boolean;
  offset: number;
}): Promise<CommonsImage[]> {
  const bucket = Math.floor(Math.max(0, offset) / 30) * 30;

  const cacheKey = `${aiExpected ? "ai" : "photo"}:${bucket}`;

  const cached = commonsQueryCache.get(cacheKey);

  if (cached && cached.expiresAt > Date.now()) {
    return shuffled(cached.items);
  }

  const query = aiExpected
    ? 'deepcategory:"AI-generated images"'
    : 'photograph -deepcategory:"AI-generated images"';

  const items = await searchCommonsQuery({
    query,
    aiExpected,
    offset: bucket,
  });

  commonsQueryCache.set(cacheKey, {
    expiresAt: Date.now() + COMMONS_QUERY_CACHE_TTL_MS,

    items,
  });

  return shuffled(items);
}

async function searchCommonsQuery({
  query,
  aiExpected,
  offset,
}: {
  query: string;
  aiExpected: boolean;
  offset: number;
}): Promise<CommonsImage[]> {
  const url = new URL(COMMONS_API);

  url.searchParams.set("action", "query");

  url.searchParams.set("generator", "search");

  url.searchParams.set("gsrsearch", query);

  url.searchParams.set("gsrnamespace", "6");

  url.searchParams.set("gsrlimit", "50");

  url.searchParams.set("gsroffset", String(Math.max(0, offset)));

  url.searchParams.set("prop", "imageinfo|categories");

  url.searchParams.set("iiprop", "url|mime|extmetadata");

  url.searchParams.set("iiurlwidth", String(THUMBNAIL_WIDTH));

  url.searchParams.set("cllimit", "max");

  url.searchParams.set("format", "json");

  url.searchParams.set("formatversion", "2");

  url.searchParams.set("origin", "*");

  const response = await fetch(url, {
    headers: {
      "User-Agent":
        "PromptWise/1.0 educational verification activity (Wikimedia Commons API)",

      Accept: "application/json",
    },

    signal: AbortSignal.timeout(8_000),
  });

  if (!response.ok) {
    throw new Error(`Wikimedia Commons returned ${response.status}.`);
  }

  const body = (await response.json()) as JsonRecord;

  const queryData = asRecord(body.query);

  const pages = Array.isArray(queryData.pages) ? queryData.pages : [];

  const result: CommonsImage[] = [];

  for (const raw of pages) {
    const page = asRecord(raw);

    const infoList = Array.isArray(page.imageinfo) ? page.imageinfo : [];

    const info = asRecord(infoList[0]);

    const mime = String(info.mime ?? "");

    if (!/^image\/(jpeg|png|webp)$/i.test(mime)) {
      continue;
    }

    const categories = Array.isArray(page.categories)
      ? page.categories.map((item) => String(asRecord(item).title ?? ""))
      : [];

    const categoryText = categories.join(" ").toLowerCase();

    const directlyLabeledAi =
      /ai-generated|synthetic media|deepfake|stable diffusion|midjourney|dall-e|dall·e/.test(
        categoryText,
      );

    if (!aiExpected && directlyLabeledAi) {
      continue;
    }

    const imageUrl = String(info.thumburl ?? info.url ?? "").trim();

    const sourcePageUrl = String(info.descriptionurl ?? "").trim();

    if (!imageUrl || !sourcePageUrl) {
      continue;
    }

    const metadata = asRecord(info.extmetadata);

    result.push({
      id: String(page.pageid ?? page.title ?? imageUrl),

      title: String(page.title ?? "Untitled image"),

      imageUrl,

      sourcePageUrl,

      creator: stripHtml(metadataValue(metadata.Artist)),

      license:
        stripHtml(metadataValue(metadata.LicenseShortName)) ||
        stripHtml(metadataValue(metadata.UsageTerms)),

      labeledAiGenerated: aiExpected || directlyLabeledAi,
    });
  }

  return dedupeImages(result);
}

function buildRounds({
  aiImages,
  realImages,
  count,
  seenIds,
}: {
  aiImages: CommonsImage[];
  realImages: CommonsImage[];
  count: number;
  seenIds: Set<string>;
}): JsonRecord[] {
  const aiPreferred = prioritizeUnseen(aiImages, seenIds);

  const realPreferred = prioritizeUnseen(realImages, seenIds);

  const usedIds = new Set<string>();

  const rounds: JsonRecord[] = [];

  let aiIndex = 0;
  let realIndex = 0;

  while (
    rounds.length < count &&
    aiIndex < aiPreferred.length &&
    realIndex < realPreferred.length
  ) {
    const ai = nextUnused(aiPreferred, usedIds, aiIndex);

    if (!ai.image) {
      break;
    }

    aiIndex = ai.nextIndex;

    const real = nextUnused(realPreferred, usedIds, realIndex);

    if (!real.image) {
      break;
    }

    realIndex = real.nextIndex;

    usedIds.add(ai.image.id);

    usedIds.add(real.image.id);

    const id = `${ai.image.id}:${real.image.id}`;

    if (rounds.some((item) => String(item.id ?? "") === id)) {
      continue;
    }

    const aiOnA = Math.random() < 0.5;

    const imageA = aiOnA ? ai.image : real.image;

    const imageB = aiOnA ? real.image : ai.image;

    rounds.push({
      id,

      topic: "online image",

      question: "Which image does its source identify as AI-made?",

      hint: "Make your best guess first. After you answer, PromptWise will show the source information.",

      correct_side: aiOnA ? "A" : "B",

      explanation:
        `“${cleanTitle(ai.image.title)}” was returned from Wikimedia Commons under its AI-generated media category tree. ` +
        `“${cleanTitle(real.image.title)}” came from a photograph search that excludes that AI category tree. ` +
        "The useful habit is to guess first, then verify with the source instead of trusting appearance alone.",

      image_a: toPayload(imageA),

      image_b: toPayload(imageB),
    });
  }

  return rounds;
}

function prioritizeUnseen(
  source: CommonsImage[],
  seenIds: Set<string>,
): CommonsImage[] {
  const shuffledItems = shuffled(dedupeImages(source));

  const unseen: CommonsImage[] = [];

  const seen: CommonsImage[] = [];

  for (const item of shuffledItems) {
    if (seenIds.has(item.id)) {
      seen.push(item);
    } else {
      unseen.push(item);
    }
  }

  return [...unseen, ...seen];
}

function nextUnused(
  items: CommonsImage[],
  usedIds: Set<string>,
  startIndex: number,
): {
  image: CommonsImage | null;
  nextIndex: number;
} {
  for (let i = startIndex; i < items.length; i += 1) {
    if (usedIds.has(items[i].id)) {
      continue;
    }

    return {
      image: items[i],

      nextIndex: i + 1,
    };
  }

  return {
    image: null,

    nextIndex: items.length,
  };
}

function dedupeImages(images: CommonsImage[]): CommonsImage[] {
  const seen = new Set<string>();

  return images.filter((image) => {
    if (!image.id || seen.has(image.id)) {
      return false;
    }

    seen.add(image.id);

    return true;
  });
}

function toPayload(image: CommonsImage): JsonRecord {
  return {
    id: image.id,

    title: cleanTitle(image.title),

    image_url: image.imageUrl,

    source_page_url: image.sourcePageUrl,

    creator: image.creator,

    license: image.license,

    labeled_ai_generated: image.labeledAiGenerated,
  };
}

function cleanTitle(value: string): string {
  return value
    .replace(/^File:/i, "")
    .replace(/\.[a-z0-9]{2,5}$/i, "")
    .trim();
}

function metadataValue(value: unknown): string {
  if (value && typeof value === "object" && "value" in value) {
    return String(
      (
        value as {
          value?: unknown;
        }
      ).value ?? "",
    );
  }

  return "";
}

function stripHtml(value: string): string {
  return value
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function shuffled<T>(source: readonly T[]): T[] {
  const copy = [...source];

  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));

    [copy[i], copy[j]] = [copy[j], copy[i]];
  }

  return copy;
}

function clampNumber(
  value: unknown,
  min: number,
  max: number,
  fallback: number,
): number {
  const parsed = Number(value);

  if (!Number.isFinite(parsed)) {
    return fallback;
  }

  return Math.max(min, Math.min(max, Math.trunc(parsed)));
}

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as JsonRecord)
    : {};
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();

  if (!value) {
    throw new HttpError(500, `${name} is not configured.`);
  }

  return value;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim()) {
    return error.message;
  }

  return "Fresh image examples are temporarily unavailable.";
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,

    headers: {
      ...corsHeaders,

      "Content-Type": "application/json",
    },
  });
}

class HttpError extends Error {
  constructor(
    public status: number,

    message: string,
  ) {
    super(message);
  }
}
