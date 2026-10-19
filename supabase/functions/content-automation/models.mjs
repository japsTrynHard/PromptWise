// Groq's model inventory also contains speech, safety and transcription models.
// These must never be sent curriculum JSON chat-completion requests.
export function isTextGenerationModel(id) {
  return typeof id === 'string' && id.length > 0 &&
    !/whisper|tts|speech|audio|voice|orpheus|playai|kokoro|bark|guard|safeguard|vision|image|embed/i.test(id);
}

export function orderTextModels(ids, configured = '') {
  const available = ids.filter(isTextGenerationModel);
  const preferred = ['llama-3.1-8b-instant','llama-3.3-70b-versatile',
    'openai/gpt-oss-20b','qwen/qwen3-32b','openai/gpt-oss-120b'];
  return [...new Set([...preferred.filter(id => available.includes(id)),
    ...(isTextGenerationModel(configured) && available.includes(configured) ? [configured] : []), ...available])];
}

export function disableUnavailableModel(models, model, status) {
  // Do not pay for repeated attempts on a rate-limited/unsupported model for
  // each article in the same run. A new run refreshes availability normally.
  if (![400,401,403,404,429].includes(status)) return;
  const index = models.indexOf(model);
  if (index >= 0) models.splice(index,1);
  if (status === 401 || status === 403) models.splice(0);
}
