import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

import {
  type CachedDictionaryEntry,
  type DictionaryEntry,
  dictionaryEntryFromCache,
  type DictionaryLookupOutcome,
  isValidDictionaryWord,
  isWiktionaryEnglishMissing,
  type JsonRecord,
  normalizeDictionaryApiEntry,
  normalizeWiktionaryEntry,
  normalizeWord,
  type ProviderFailureKind,
  type ProviderResult,
  requestDictionaryProvider,
  resolveDictionaryLookup,
} from "./dictionary_core.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const primaryProvider = "dictionaryapi.dev";
const fallbackProvider = "en.wiktionary.org";
const providerTimeoutMs = 4_000;
const providerHedgeDelayMs = 500;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json(
      { code: "method_not_allowed", message: "Method not allowed." },
      405,
    );
  }

  try {
    const lookupStartedAt = performance.now();
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRole = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const admin = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    await requireUser(request, admin);

    let body: JsonRecord = {};
    try {
      body = await request.json() as JsonRecord;
    } catch {
      return json(
        { code: "invalid_request", message: "A word is required." },
        400,
      );
    }

    const word = normalizeWord(body.word);
    if (!isValidDictionaryWord(word)) {
      return json(
        {
          code: "invalid_request",
          message: "Enter one short English word.",
        },
        400,
      );
    }

    const cached = await readCachedEntry(admin, word);
    console.info("Dictionary cache checked", {
      word,
      result: cached ? "present" : "miss",
    });
    const outcome = await resolveDictionaryLookup({
      cached,
      nowMs: Date.now(),
      primaryLookup: () => lookupPrimary(word),
      fallbackLookup: () => lookupFallback(word),
      hedgeDelayMs: providerHedgeDelayMs,
    });

    if (outcome.kind === "success") {
      if (outcome.source === "primary" || outcome.source === "fallback") {
        await saveCachedEntry(admin, word, outcome.entry, outcome.provider);
      }
      if (
        outcome.source === "fresh_cache" || outcome.source === "stale_cache"
      ) {
        console.info("Dictionary cache hit", {
          word,
          freshness: outcome.source === "fresh_cache" ? "fresh" : "stale",
        });
      } else {
        console.info("Dictionary winning provider", {
          word,
          provider: outcome.provider,
        });
      }
      console.info("Dictionary lookup completed", {
        word,
        result: "success",
        source: outcome.source,
        durationMs: elapsedMilliseconds(lookupStartedAt),
      });
      return json(
        {
          entry: outcome.entry,
          provider: outcome.provider,
          cache: outcome.source,
        },
        200,
      );
    }

    if (outcome.kind === "not_found") {
      console.info("Dictionary lookup completed", {
        word,
        result: "not_found",
        durationMs: elapsedMilliseconds(lookupStartedAt),
      });
      return json(
        {
          code: "not_found",
          message: "No definition was found. Try another word from the lesson.",
        },
        404,
      );
    }

    logProviderFailures(word, outcome);
    console.warn("Dictionary lookup completed", {
      word,
      result: outcome.failure,
      durationMs: elapsedMilliseconds(lookupStartedAt),
    });
    return failureResponse(outcome.failure);
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    if (status >= 500) {
      console.error("Dictionary function failed", safeError(error));
    }
    return json(
      {
        code: status === 401 ? "authentication_required" : "server_error",
        message: status === 401
          ? "Please sign in again to use the lesson dictionary."
          : "The dictionary encountered an unexpected error. Please try again.",
      },
      status,
    );
  }
});

async function lookupPrimary(word: string): Promise<ProviderResult> {
  const startedAt = performance.now();
  console.info("Dictionary provider started", {
    word,
    provider: primaryProvider,
  });
  const result = await requestDictionaryProvider({
    provider: primaryProvider,
    url: `https://api.dictionaryapi.dev/api/v2/entries/en/${
      encodeURIComponent(word)
    }`,
    word,
    timeoutMs: providerTimeoutMs,
    normalize: normalizeDictionaryApiEntry,
  });
  logProviderResult(word, result, startedAt);
  return result;
}

async function lookupFallback(word: string): Promise<ProviderResult> {
  const startedAt = performance.now();
  console.info("Dictionary provider started", {
    word,
    provider: fallbackProvider,
  });
  const result = await requestDictionaryProvider({
    provider: fallbackProvider,
    url: `https://en.wiktionary.org/api/rest_v1/page/definition/${
      encodeURIComponent(word)
    }`,
    word,
    timeoutMs: providerTimeoutMs,
    normalize: normalizeWiktionaryEntry,
    isNotFoundPayload: isWiktionaryEnglishMissing,
  });
  logProviderResult(word, result, startedAt);
  return result;
}

async function readCachedEntry(
  admin: SupabaseClient,
  word: string,
): Promise<CachedDictionaryEntry | null> {
  const { data, error } = await admin
    .from("dictionary_cache")
    .select("result, provider, fetched_at")
    .eq("word", word)
    .maybeSingle();
  if (error) {
    console.error("Dictionary cache read failed", safeDatabaseError(error));
    return null;
  }
  if (!data) return null;

  const entry = dictionaryEntryFromCache(data.result);
  const fetchedAtMs = Date.parse(String(data.fetched_at ?? ""));
  const provider = String(data.provider ?? "").trim();
  if (!entry || !Number.isFinite(fetchedAtMs) || !provider) {
    console.warn("Dictionary cache row was invalid", { word });
    return null;
  }
  return { entry, provider, fetchedAtMs };
}

async function saveCachedEntry(
  admin: SupabaseClient,
  word: string,
  entry: DictionaryEntry,
  provider: string,
): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await admin.from("dictionary_cache").upsert(
    {
      word,
      result: entry,
      provider,
      fetched_at: now,
      updated_at: now,
    },
    { onConflict: "word" },
  );
  if (error) {
    console.error("Dictionary cache write failed", safeDatabaseError(error));
  }
}

async function requireUser(
  request: Request,
  admin: SupabaseClient,
): Promise<string> {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError(401);
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401);
  return data.user.id;
}

function failureResponse(failure: ProviderFailureKind): Response {
  switch (failure) {
    case "timeout":
      return json(
        {
          code: "timeout",
          message: "The dictionary providers took too long. Please try again.",
        },
        504,
      );
    case "network_failure":
      return json(
        {
          code: "network_failure",
          message:
            "The dictionary providers could not be reached. Please try again.",
        },
        503,
      );
    case "rate_limited":
      return json(
        {
          code: "rate_limited",
          message:
            "The dictionary is busy right now. Wait a moment, then try again.",
        },
        429,
      );
    case "malformed_response":
      return json(
        {
          code: "malformed_response",
          message:
            "The dictionary providers returned unreadable results. Please try again.",
        },
        502,
      );
    case "provider_unavailable":
      return json(
        {
          code: "provider_unavailable",
          message:
            "The dictionary providers are temporarily unavailable. Please try again.",
        },
        503,
      );
  }
}

function logProviderFailures(
  word: string,
  outcome: Extract<DictionaryLookupOutcome, { kind: "failure" }>,
): void {
  console.warn("Dictionary providers failed", {
    word,
    failure: outcome.failure,
    providers: outcome.providerResults.map((result) =>
      result.kind === "failure"
        ? {
          provider: result.provider,
          failure: result.failure,
          status: result.status,
        }
        : { provider: result.provider, result: result.kind }
    ),
  });
}

function logProviderResult(
  word: string,
  result: ProviderResult,
  startedAt: number,
): void {
  const details = result.kind === "failure"
    ? {
      word,
      provider: result.provider,
      result: result.failure,
      status: result.status,
      durationMs: elapsedMilliseconds(startedAt),
    }
    : {
      word,
      provider: result.provider,
      result: result.kind,
      durationMs: elapsedMilliseconds(startedAt),
    };
  if (result.kind === "success") {
    console.info("Dictionary provider completed", details);
  } else {
    console.warn("Dictionary provider completed", details);
  }
}

function elapsedMilliseconds(startedAt: number): number {
  return Math.round(performance.now() - startedAt);
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function safeError(error: unknown): string {
  return error instanceof Error
    ? `${error.name}: ${error.message}`
    : "Unknown error";
}

function safeDatabaseError(error: unknown): JsonRecord {
  const value = error && typeof error === "object"
    ? error as Record<string, unknown>
    : {};
  return {
    code: String(value.code ?? "unknown"),
    message: String(value.message ?? "Database operation failed"),
  };
}

function json(body: JsonRecord, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

class HttpError extends Error {
  constructor(readonly status: number) {
    super(`HTTP ${status}`);
  }
}
