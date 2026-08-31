export type JsonRecord = Record<string, unknown>;

export type DictionaryEntry = {
  word: string;
  phonetic: string;
  definitions: Array<{
    partOfSpeech: string;
    definition: string;
    example: string;
  }>;
  sourceUrls: string[];
};

export type ProviderFailureKind =
  | "timeout"
  | "network_failure"
  | "rate_limited"
  | "provider_unavailable"
  | "malformed_response";

export type ProviderResult =
  | {
    kind: "success";
    provider: string;
    entry: DictionaryEntry;
  }
  | {
    kind: "not_found";
    provider: string;
  }
  | {
    kind: "failure";
    provider: string;
    failure: ProviderFailureKind;
    status?: number;
  };

export type CachedDictionaryEntry = {
  entry: DictionaryEntry;
  provider: string;
  fetchedAtMs: number;
};

export type DictionaryLookupOutcome =
  | {
    kind: "success";
    entry: DictionaryEntry;
    provider: string;
    source: "fresh_cache" | "primary" | "fallback" | "stale_cache";
  }
  | { kind: "not_found" }
  | {
    kind: "failure";
    failure: ProviderFailureKind;
    providerResults: ProviderResult[];
  };

export const dictionaryCacheMaxAgeMs = 30 * 24 * 60 * 60 * 1000;

export function normalizeWord(value: unknown): string {
  return String(value ?? "").trim().replace(/\s+/g, " ").toLowerCase();
}

export function isValidDictionaryWord(word: string): boolean {
  return word.length >= 1 && word.length <= 50 &&
    /^[a-z][a-z '-]*$/i.test(word);
}

export function normalizeDictionaryApiEntry(
  decoded: unknown,
  requestedWord: string,
): DictionaryEntry | null {
  if (!Array.isArray(decoded) || decoded.length === 0) return null;
  const raw = asRecord(decoded[0]);
  const definitions: DictionaryEntry["definitions"] = [];
  const meanings = Array.isArray(raw.meanings) ? raw.meanings : [];
  for (const rawMeaning of meanings) {
    const meaning = asRecord(rawMeaning);
    const partOfSpeech = cleanText(meaning.partOfSpeech);
    const rawDefinitions = Array.isArray(meaning.definitions)
      ? meaning.definitions
      : [];
    for (const item of rawDefinitions.slice(0, 3)) {
      const definition = asRecord(item);
      const text = cleanText(definition.definition);
      if (!text) continue;
      definitions.push({
        partOfSpeech,
        definition: text,
        example: cleanText(definition.example),
      });
      if (definitions.length >= 5) break;
    }
    if (definitions.length >= 5) break;
  }
  if (definitions.length === 0) return null;

  const phonetics = Array.isArray(raw.phonetics) ? raw.phonetics : [];
  const firstPhonetic = phonetics
    .map((value) => cleanText(asRecord(value).text))
    .find(Boolean) ?? "";
  const sourceUrls = Array.isArray(raw.sourceUrls)
    ? raw.sourceUrls.map(cleanText).filter(Boolean)
    : [];

  return {
    word: cleanText(raw.word) || requestedWord,
    phonetic: cleanText(raw.phonetic) || firstPhonetic,
    definitions,
    sourceUrls,
  };
}

export function normalizeWiktionaryEntry(
  decoded: unknown,
  requestedWord: string,
): DictionaryEntry | null {
  const root = asRecord(decoded);
  if (!Array.isArray(root.en)) return null;

  const definitions: DictionaryEntry["definitions"] = [];
  for (const rawEntry of root.en) {
    const entry = asRecord(rawEntry);
    const partOfSpeech = plainText(entry.partOfSpeech);
    const rawDefinitions = Array.isArray(entry.definitions)
      ? entry.definitions
      : [];
    for (const rawDefinition of rawDefinitions) {
      const definition = asRecord(rawDefinition);
      const text = plainText(definition.definition);
      if (!text) continue;
      definitions.push({
        partOfSpeech,
        definition: text,
        example: firstWiktionaryExample(definition),
      });
      if (definitions.length >= 5) break;
    }
    if (definitions.length >= 5) break;
  }
  if (definitions.length === 0) return null;

  return {
    word: requestedWord,
    phonetic: "",
    definitions,
    sourceUrls: [
      `https://en.wiktionary.org/wiki/${encodeURIComponent(requestedWord)}`,
    ],
  };
}

export function dictionaryEntryFromCache(
  value: unknown,
): DictionaryEntry | null {
  const raw = asRecord(value);
  const definitions: DictionaryEntry["definitions"] = [];
  if (Array.isArray(raw.definitions)) {
    for (const item of raw.definitions) {
      const definition = asRecord(item);
      const text = cleanText(definition.definition);
      if (!text) continue;
      definitions.push({
        partOfSpeech: cleanText(definition.partOfSpeech),
        definition: text,
        example: cleanText(definition.example),
      });
      if (definitions.length >= 5) break;
    }
  }
  const word = normalizeWord(raw.word);
  if (!isValidDictionaryWord(word) || definitions.length === 0) return null;

  return {
    word,
    phonetic: cleanText(raw.phonetic),
    definitions,
    sourceUrls: Array.isArray(raw.sourceUrls)
      ? raw.sourceUrls.map(cleanText).filter(Boolean)
      : [],
  };
}

export async function requestDictionaryProvider(options: {
  provider: string;
  url: string;
  word: string;
  timeoutMs: number;
  normalize: (decoded: unknown, word: string) => DictionaryEntry | null;
  isNotFoundPayload?: (decoded: unknown) => boolean;
  fetchImpl?: typeof fetch;
}): Promise<ProviderResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), options.timeoutMs);
  let response: Response;
  try {
    response = await (options.fetchImpl ?? fetch)(options.url, {
      headers: {
        Accept: "application/json",
        "User-Agent": "PromptWise/1.0 (dictionary lookup)",
      },
      signal: controller.signal,
    });
  } catch (error) {
    clearTimeout(timer);
    const isTimeout = controller.signal.aborted ||
      (error instanceof Error && error.name === "AbortError");
    return {
      kind: "failure",
      provider: options.provider,
      failure: isTimeout ? "timeout" : "network_failure",
    };
  }
  try {
    if (response.status === 404) {
      return { kind: "not_found", provider: options.provider };
    }
    if (response.status === 429) {
      return {
        kind: "failure",
        provider: options.provider,
        failure: "rate_limited",
        status: response.status,
      };
    }
    if (response.status >= 500) {
      return {
        kind: "failure",
        provider: options.provider,
        failure: "provider_unavailable",
        status: response.status,
      };
    }
    if (!response.ok) {
      return {
        kind: "failure",
        provider: options.provider,
        failure: "provider_unavailable",
        status: response.status,
      };
    }

    const decoded = await response.json();
    const entry = options.normalize(decoded, options.word);
    if (entry) {
      return { kind: "success", provider: options.provider, entry };
    }
    if (options.isNotFoundPayload?.(decoded)) {
      return { kind: "not_found", provider: options.provider };
    }
    return {
      kind: "failure",
      provider: options.provider,
      failure: "malformed_response",
    };
  } catch (error) {
    const isTimeout = controller.signal.aborted ||
      (error instanceof Error && error.name === "AbortError");
    return {
      kind: "failure",
      provider: options.provider,
      failure: isTimeout ? "timeout" : "malformed_response",
    };
  } finally {
    clearTimeout(timer);
  }
}

export async function resolveDictionaryLookup(options: {
  cached: CachedDictionaryEntry | null;
  nowMs: number;
  primaryLookup: () => Promise<ProviderResult>;
  fallbackLookup: () => Promise<ProviderResult>;
  cacheMaxAgeMs?: number;
  hedgeDelayMs?: number;
  sleep?: (milliseconds: number) => Promise<void>;
}): Promise<DictionaryLookupOutcome> {
  const maxAge = options.cacheMaxAgeMs ?? dictionaryCacheMaxAgeMs;
  if (
    options.cached &&
    options.nowMs - options.cached.fetchedAtMs >= 0 &&
    options.nowMs - options.cached.fetchedAtMs <= maxAge
  ) {
    return {
      kind: "success",
      entry: options.cached.entry,
      provider: options.cached.provider,
      source: "fresh_cache",
    };
  }

  const hedgeDelayMs = options.hedgeDelayMs ?? 500;
  const sleep = options.sleep ?? delay;
  let finished = false;
  let fallbackPromise: Promise<ProviderResult> | null = null;
  const startFallback = (): Promise<ProviderResult> => {
    fallbackPromise ??= options.fallbackLookup();
    return fallbackPromise;
  };

  const primaryOutcome = options.primaryLookup().then((result) => ({
    provider: "primary" as const,
    result,
  }));
  const hedgedFallbackOutcome = (async () => {
    await sleep(hedgeDelayMs);
    if (finished) return null;
    return {
      provider: "fallback" as const,
      result: await startFallback(),
    };
  })();

  const first = await Promise.race([primaryOutcome, hedgedFallbackOutcome]);
  if (first === null) {
    throw new Error("Dictionary hedge completed without a provider result.");
  }
  if (first.result.kind === "success") {
    finished = true;
    return {
      ...first.result,
      source: first.provider,
    };
  }

  if (first.provider === "primary") {
    const fallback = await startFallback();
    if (fallback.kind === "success") {
      finished = true;
      return { ...fallback, source: "fallback" };
    }
    finished = true;
    return failedProviderOutcome(first.result, fallback, options.cached);
  }

  const primary = (await primaryOutcome).result;
  if (primary.kind === "success") {
    finished = true;
    return { ...primary, source: "primary" };
  }
  finished = true;
  return failedProviderOutcome(primary, first.result, options.cached);
}

function failedProviderOutcome(
  primary: ProviderResult,
  fallback: ProviderResult,
  cached: CachedDictionaryEntry | null,
): DictionaryLookupOutcome {
  if (cached) {
    return {
      kind: "success",
      entry: cached.entry,
      provider: cached.provider,
      source: "stale_cache",
    };
  }
  if (primary.kind === "not_found" || fallback.kind === "not_found") {
    return { kind: "not_found" };
  }

  const providerResults = [primary, fallback];
  return {
    kind: "failure",
    failure: combinedFailureKind(providerResults),
    providerResults,
  };
}

export function isWiktionaryEnglishMissing(decoded: unknown): boolean {
  const root = asRecord(decoded);
  return !Object.prototype.hasOwnProperty.call(root, "en");
}

function combinedFailureKind(results: ProviderResult[]): ProviderFailureKind {
  const failures = results
    .filter((result) => result.kind === "failure")
    .map((result) => result.failure);
  if (failures.length === 0) return "provider_unavailable";
  if (failures.every((failure) => failure === failures[0])) return failures[0];
  return "provider_unavailable";
}

function firstWiktionaryExample(definition: JsonRecord): string {
  const examples = Array.isArray(definition.examples)
    ? definition.examples
    : [];
  for (const example of examples) {
    const text = plainText(example);
    if (text) return text;
  }
  const parsedExamples = Array.isArray(definition.parsedExamples)
    ? definition.parsedExamples
    : [];
  for (const example of parsedExamples) {
    const text = plainText(asRecord(example).example);
    if (text) return text;
  }
  return "";
}

function plainText(value: unknown): string {
  const withoutTags = String(value ?? "").replace(/<[^>]*>/g, " ");
  return decodeHtmlEntities(withoutTags).replace(/\s+/g, " ").trim();
}

function decodeHtmlEntities(value: string): string {
  const named: Record<string, string> = {
    amp: "&",
    apos: "'",
    gt: ">",
    lt: "<",
    nbsp: " ",
    quot: '"',
  };
  return value.replace(
    /&(#x[0-9a-f]+|#\d+|amp|apos|gt|lt|nbsp|quot);/gi,
    (match, entity: string) => {
      if (entity.startsWith("#x")) {
        return String.fromCodePoint(Number.parseInt(entity.slice(2), 16));
      }
      if (entity.startsWith("#")) {
        return String.fromCodePoint(Number.parseInt(entity.slice(1), 10));
      }
      return named[entity.toLowerCase()] ?? match;
    },
  );
}

function cleanText(value: unknown): string {
  return String(value ?? "").trim();
}

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
