-- An official curriculum source for prompt clarity, context and specificity.
-- Existing administrator choices are preserved if this URL/name already exists.
INSERT INTO public.content_sources
  (name, source_url, source_type, trust_level, enabled, relevance_keywords)
VALUES (
  'Google AI - Prompt design strategies',
  'https://ai.google.dev/gemini-api/docs/prompting-strategies',
  'page', 5, true,
  '["AI", "prompt", "context", "specific instructions", "constraints", "response format"]'::jsonb
)
ON CONFLICT DO NOTHING;
