import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonRecord = Record<string, unknown>;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ code: "method_not_allowed", message: "Method not allowed." }, 405);
  }

  try {
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
      return json({ code: "invalid_request", message: "A word is required." }, 400);
    }

    const word = String(body.word ?? "").trim().toLowerCase();
    if (!word || word.length > 50 || !/^[a-z][a-z '-]*$/i.test(word)) {
      return json(
        { code: "invalid_request", message: "Enter one short English word." },
        400,
      );
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10_000);
    let response: Response;
    try {
      response = await fetch(
        `https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`,
        {
          headers: { Accept: "application/json" },
          signal: controller.signal,
        },
      );
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        return json(
          { code: "timeout", message: "The dictionary lookup took too long. Please try again." },
          504,
        );
      }
      console.error("Dictionary upstream request failed", safeError(error));
      return json(
        { code: "upstream_unavailable", message: "The dictionary is temporarily unavailable. Please try again." },
        503,
      );
    } finally {
      clearTimeout(timer);
    }

    if (response.status === 404) {
      return json(
        { code: "not_found", message: "No definition was found. Try another word from the lesson." },
        404,
      );
    }
    if (response.status === 429) {
      return json(
        { code: "rate_limited", message: "The dictionary is busy right now. Wait a moment, then try again." },
        429,
      );
    }
    if (!response.ok) {
      console.warn("Dictionary upstream status", response.status);
      return json(
        { code: "upstream_unavailable", message: "The dictionary is temporarily unavailable. Please try again." },
        503,
      );
    }

    let decoded: unknown;
    try {
      decoded = await response.json();
    } catch (error) {
      console.error("Dictionary upstream JSON failed", safeError(error));
      return json(
        { code: "invalid_response", message: "The dictionary returned an unreadable response. Please try again." },
        502,
      );
    }

    const entry = normalizeEntry(decoded);
    if (!entry) {
      return json(
        { code: "invalid_response", message: "No readable definition was returned for this word." },
        502,
      );
    }
    return json({ entry }, 200);
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    if (status >= 500) console.error("Dictionary function failed", safeError(error));
    return json(
      {
        code: status === 401 ? "authentication_required" : "server_error",
        message: status === 401
          ? "Please sign in again to use the lesson dictionary."
          : "The dictionary is temporarily unavailable. Please try again.",
      },
      status,
    );
  }
});

function normalizeEntry(decoded: unknown): JsonRecord | null {
  if (!Array.isArray(decoded) || decoded.length === 0) return null;
  const raw = asRecord(decoded[0]);
  const definitions: JsonRecord[] = [];
  const meanings = Array.isArray(raw.meanings) ? raw.meanings : [];
  for (const rawMeaning of meanings) {
    const meaning = asRecord(rawMeaning);
    const partOfSpeech = String(meaning.partOfSpeech ?? "").trim();
    const rawDefinitions = Array.isArray(meaning.definitions)
      ? meaning.definitions
      : [];
    for (const item of rawDefinitions.slice(0, 3)) {
      const definition = asRecord(item);
      const text = String(definition.definition ?? "").trim();
      if (!text) continue;
      definitions.push({
        partOfSpeech,
        definition: text,
        example: String(definition.example ?? "").trim(),
      });
      if (definitions.length >= 5) break;
    }
    if (definitions.length >= 5) break;
  }
  if (definitions.length === 0) return null;

  const sourceUrls = Array.isArray(raw.sourceUrls)
    ? raw.sourceUrls.map((value) => String(value).trim()).filter(Boolean)
    : [];
  return {
    word: String(raw.word ?? "").trim(),
    phonetic: String(raw.phonetic ?? "").trim(),
    definitions,
    sourceUrls,
  };
}

async function requireUser(
  request: Request,
  admin: ReturnType<typeof createClient>,
): Promise<string> {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError(401);
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401);
  return data.user.id;
}

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function safeError(error: unknown): string {
  return error instanceof Error ? `${error.name}: ${error.message}` : "Unknown error";
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
