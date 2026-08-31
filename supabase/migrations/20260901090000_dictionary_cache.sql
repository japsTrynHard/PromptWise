-- Persistent, server-only cache for normalized lesson dictionary results.
--
-- The dictionary Edge Function owns this table through the service role.
-- Learner clients never read or write cached provider payloads directly.

create table public.dictionary_cache (
  word text primary key,
  result jsonb not null,
  provider text not null,
  fetched_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint dictionary_cache_word_check
    check (
      word = lower(btrim(word))
      and char_length(word) between 1 and 50
      and word ~ '^[a-z][a-z ''-]*$'
    ),
  constraint dictionary_cache_result_check
    check (jsonb_typeof(result) = 'object'),
  constraint dictionary_cache_provider_check
    check (char_length(btrim(provider)) between 1 and 120)
);

create index dictionary_cache_fetched_at_idx
  on public.dictionary_cache (fetched_at desc);

alter table public.dictionary_cache enable row level security;

revoke all on table public.dictionary_cache
  from public, anon, authenticated;
grant select, insert, update on table public.dictionary_cache
  to service_role;

comment on table public.dictionary_cache is
  'Server-only normalized dictionary results used by dictionary-lookup.';
comment on column public.dictionary_cache.result is
  'Provider-independent PromptWise DictionaryEntry JSON.';
