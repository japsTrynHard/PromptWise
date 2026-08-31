import {
  type CachedDictionaryEntry,
  dictionaryCacheMaxAgeMs,
  type DictionaryEntry,
  normalizeWiktionaryEntry,
  normalizeWord,
  type ProviderFailureKind,
  type ProviderResult,
  requestDictionaryProvider,
  resolveDictionaryLookup,
} from "./dictionary_core.ts";

const requestedWords = [
  "prompt",
  "instruction",
  "algorithm",
  "education",
  "evidence",
  "responsibility",
  "technology",
  "verification",
];

Deno.test("normalizes required terms into the shared dictionary model", () => {
  for (const word of requestedWords) {
    const result = normalizeWiktionaryEntry(wiktionaryPayload(word), word);
    assert(result !== null, `${word} should produce an entry`);
    assertEquals(result.word, word);
    assertEquals(result.definitions[0].partOfSpeech, "Noun");
    assertIncludes(result.definitions[0].definition, word);
    assertIncludes(result.sourceUrls[0], encodeURIComponent(word));
  }
});

Deno.test("normalizes uppercase input and surrounding whitespace", () => {
  assertEquals(normalizeWord("  PROMPT  "), "prompt");
  assertEquals(normalizeWord("CONTEXT"), "context");
  assertEquals(normalizeWord("  instruction  "), "instruction");
  assertEquals(normalizeWord("  Data   Privacy  "), "data privacy");
});

Deno.test("fresh cache returns without starting either provider", async () => {
  let providerCalls = 0;
  const now = Date.now();
  const outcome = await resolveDictionaryLookup({
    cached: {
      entry: entry("privacy"),
      provider: "dictionaryapi.dev",
      fetchedAtMs: now - 1_000,
    },
    nowMs: now,
    primaryLookup: async () => {
      providerCalls++;
      return failure("timeout");
    },
    fallbackLookup: async () => {
      providerCalls++;
      return failure("timeout", "en.wiktionary.org");
    },
  });

  assertEquals(providerCalls, 0);
  assertEquals(outcome.kind, "success");
  if (outcome.kind === "success") assertEquals(outcome.source, "fresh_cache");
});

Deno.test("hedge waits before starting Wiktionary", async () => {
  const primary = new Deferred<ProviderResult>();
  const hedge = new Deferred<void>();
  let fallbackCalls = 0;
  const lookup = resolveDictionaryLookup({
    cached: null,
    nowMs: Date.now(),
    primaryLookup: () => primary.promise,
    fallbackLookup: async () => {
      fallbackCalls++;
      return success("en.wiktionary.org", entry("prompt"));
    },
    sleep: () => hedge.promise,
  });

  await flushMicrotasks();
  assertEquals(fallbackCalls, 0);
  hedge.complete();
  const outcome = await lookup;
  assertEquals(fallbackCalls, 1);
  assertSuccess(outcome, "fallback", "en.wiktionary.org");
  primary.complete(failure("timeout"));
});

Deno.test("Dictionary API can win after the hedge starts", async () => {
  const primary = new Deferred<ProviderResult>();
  const fallback = new Deferred<ProviderResult>();
  const lookup = resolveDictionaryLookup({
    cached: null,
    nowMs: Date.now(),
    primaryLookup: () => primary.promise,
    fallbackLookup: () => fallback.promise,
    sleep: async () => {},
  });

  await flushMicrotasks();
  primary.complete(success("dictionaryapi.dev", entry("algorithm")));
  const outcome = await lookup;
  assertSuccess(outcome, "primary", "dictionaryapi.dev");
  fallback.complete(success("en.wiktionary.org", entry("wrong-result")));
  await flushMicrotasks();
  if (outcome.kind === "success") assertEquals(outcome.entry.word, "algorithm");
});

Deno.test("Wiktionary can win the hedged race", async () => {
  const primary = new Deferred<ProviderResult>();
  const fallback = new Deferred<ProviderResult>();
  const lookup = resolveDictionaryLookup({
    cached: null,
    nowMs: Date.now(),
    primaryLookup: () => primary.promise,
    fallbackLookup: () => fallback.promise,
    sleep: async () => {},
  });

  await flushMicrotasks();
  fallback.complete(success("en.wiktionary.org", entry("education")));
  const outcome = await lookup;
  assertSuccess(outcome, "fallback", "en.wiktionary.org");
  primary.complete(success("dictionaryapi.dev", entry("late-result")));
  await flushMicrotasks();
  if (outcome.kind === "success") assertEquals(outcome.entry.word, "education");
});

Deno.test("primary can hang while fallback succeeds quickly", async () => {
  const outcome = await resolveDictionaryLookup({
    cached: null,
    nowMs: Date.now(),
    primaryLookup: () => new Promise<ProviderResult>(() => {}),
    fallbackLookup: async () => success("en.wiktionary.org", entry("evidence")),
    sleep: async () => {},
  });

  assertSuccess(outcome, "fallback", "en.wiktionary.org");
});

Deno.test("primary HTTP 500 starts fallback without a retry", async () => {
  let primaryCalls = 0;
  let fallbackCalls = 0;
  const outcome = await resolveDictionaryLookup({
    cached: null,
    nowMs: Date.now(),
    primaryLookup: async () => {
      primaryCalls++;
      return failure("provider_unavailable", "dictionaryapi.dev", 500);
    },
    fallbackLookup: async () => {
      fallbackCalls++;
      return success("en.wiktionary.org", entry("responsibility"));
    },
    sleep: () => new Promise<void>(() => {}),
  });

  assertEquals(primaryCalls, 1);
  assertEquals(fallbackCalls, 1);
  assertSuccess(outcome, "fallback", "en.wiktionary.org");
});

Deno.test("primary not-found still allows fallback definition", async () => {
  const outcome = await resolveDictionaryLookup({
    cached: null,
    nowMs: Date.now(),
    primaryLookup: async () => notFound("dictionaryapi.dev"),
    fallbackLookup: async () =>
      success("en.wiktionary.org", entry("technology")),
    sleep: () => new Promise<void>(() => {}),
  });

  assertSuccess(outcome, "fallback", "en.wiktionary.org");
});

Deno.test("both providers can confirm word not found", async () => {
  const outcome = await resolveDictionaryLookup({
    cached: null,
    nowMs: Date.now(),
    primaryLookup: async () => notFound("dictionaryapi.dev"),
    fallbackLookup: async () => notFound("en.wiktionary.org"),
    sleep: () => new Promise<void>(() => {}),
  });

  assertEquals(outcome.kind, "not_found");
});

Deno.test("both providers failing returns stale cache", async () => {
  const outcome = await resolveDictionaryLookup({
    cached: staleCache("instruction"),
    nowMs: Date.now(),
    primaryLookup: async () => failure("timeout"),
    fallbackLookup: async () => failure("network_failure", "en.wiktionary.org"),
    sleep: () => new Promise<void>(() => {}),
  });

  assertSuccess(outcome, "stale_cache", "dictionaryapi.dev");
  if (outcome.kind === "success") {
    assertEquals(outcome.entry.word, "instruction");
  }
});

Deno.test("both providers failing without cache returns typed failure", async () => {
  let primaryCalls = 0;
  let fallbackCalls = 0;
  const outcome = await resolveDictionaryLookup({
    cached: null,
    nowMs: Date.now(),
    primaryLookup: async () => {
      primaryCalls++;
      return failure("timeout");
    },
    fallbackLookup: async () => {
      fallbackCalls++;
      return failure("network_failure", "en.wiktionary.org");
    },
    sleep: () => new Promise<void>(() => {}),
  });

  assertEquals(primaryCalls, 1);
  assertEquals(fallbackCalls, 1);
  assertEquals(outcome.kind, "failure");
  if (outcome.kind === "failure") {
    assertEquals(outcome.failure, "provider_unavailable");
  }
});

Deno.test("matching provider failures preserve their classification", async () => {
  const kinds: ProviderFailureKind[] = [
    "timeout",
    "network_failure",
    "rate_limited",
    "provider_unavailable",
    "malformed_response",
  ];
  for (const kind of kinds) {
    const outcome = await resolveDictionaryLookup({
      cached: null,
      nowMs: Date.now(),
      primaryLookup: async () => failure(kind),
      fallbackLookup: async () => failure(kind, "en.wiktionary.org"),
      sleep: () => new Promise<void>(() => {}),
    });
    assertEquals(outcome.kind, "failure");
    if (outcome.kind === "failure") assertEquals(outcome.failure, kind);
  }
});

Deno.test("provider HTTP 500 is classified without internal retry", async () => {
  let calls = 0;
  const result = await requestDictionaryProvider({
    provider: "dictionaryapi.dev",
    url: "https://provider.invalid/prompt",
    word: "prompt",
    timeoutMs: 50,
    normalize: () => null,
    fetchImpl: (() => {
      calls++;
      return Promise.resolve(new Response("upstream failed", { status: 500 }));
    }) as typeof fetch,
  });

  assertEquals(calls, 1);
  assertEquals(result.kind, "failure");
  if (result.kind === "failure") {
    assertEquals(result.failure, "provider_unavailable");
    assertEquals(result.status, 500);
  }
});

function wiktionaryPayload(word: string): Record<string, unknown> {
  return {
    en: [
      {
        partOfSpeech: "Noun",
        definitions: [
          { definition: "" },
          {
            definition:
              `A <a href="/wiki/term">${word}</a> definition &amp; explanation.`,
            examples: [`An example using <b>${word}</b>.`],
          },
        ],
      },
    ],
  };
}

function entry(word: string): DictionaryEntry {
  return {
    word,
    phonetic: "",
    definitions: [
      {
        partOfSpeech: "noun",
        definition: `A definition for ${word}.`,
        example: "",
      },
    ],
    sourceUrls: [],
  };
}

function success(provider: string, value: DictionaryEntry): ProviderResult {
  return { kind: "success", provider, entry: value };
}

function failure(
  kind: ProviderFailureKind = "provider_unavailable",
  provider = "dictionaryapi.dev",
  status?: number,
): ProviderResult {
  return { kind: "failure", provider, failure: kind, status };
}

function notFound(provider: string): ProviderResult {
  return { kind: "not_found", provider };
}

function staleCache(word: string): CachedDictionaryEntry {
  return {
    entry: entry(word),
    provider: "dictionaryapi.dev",
    fetchedAtMs: Date.now() - dictionaryCacheMaxAgeMs - 1,
  };
}

function assertSuccess(
  outcome: Awaited<ReturnType<typeof resolveDictionaryLookup>>,
  source: "primary" | "fallback" | "fresh_cache" | "stale_cache",
  provider: string,
): void {
  assertEquals(outcome.kind, "success");
  if (outcome.kind === "success") {
    assertEquals(outcome.source, source);
    assertEquals(outcome.provider, provider);
  }
}

async function flushMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

class Deferred<T> {
  readonly promise: Promise<T>;
  private resolve!: (value: T) => void;

  constructor() {
    this.promise = new Promise<T>((resolve) => {
      this.resolve = resolve;
    });
  }

  complete(value?: T): void {
    this.resolve(value as T);
  }
}

function assert(
  condition: boolean,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (actual !== expected) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertIncludes(actual: string, expected: string): void {
  if (!actual.includes(expected)) {
    throw new Error(
      `${JSON.stringify(actual)} does not include ${JSON.stringify(expected)}`,
    );
  }
}
