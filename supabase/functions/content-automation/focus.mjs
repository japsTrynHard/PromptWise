// Shared, side-effect-free focus-area contract for the Edge Function and Node tests.
// No AI output or client-supplied topic is trusted without server-side validation.
export const FOCUS_TOPICS = Object.freeze([
  'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification',
]);
const VALID_TOPICS = new Set(FOCUS_TOPICS);

export function validateFocusTopics(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > FOCUS_TOPICS.length ||
      value.some((topic) => typeof topic !== 'string' || !VALID_TOPICS.has(topic)) ||
      new Set(value).size !== value.length) {
    throw new Error('Select one or more distinct valid focus areas before generating content.');
  }
  return [...value];
}

// The schedule ALWAYS uses the saved database setting; a schedule request cannot
// override the administrator's selections. Verify-only generation is separate.
export function resolveFocusTopics({ mode, target, savedTopics, requestedTopics }) {
  if (target === 'verification') return null;
  if (mode === 'scheduled') {
    if (Array.isArray(savedTopics) && savedTopics.length === 0) return [];
    return validateFocusTopics(savedTopics);
  }
  return validateFocusTopics(requestedTopics);
}

// Conservative signal checks: an AI-related article still needs a meaningful
// reference to the selected curricular skill, not just generic AI keywords.
const SIGNALS = Object.freeze({
  prompt_clarity: [/\bprompts?\b/i, /\bprompt engineering\b/i, /\bclear instructions?\b/i,
    /\bambiguous instructions?\b/i],
  context: [/\bcontext\b/i, /\bbackground information\b/i, /\baudience\b/i,
    /\bcontextual (?:information|details|prompt)\b/i],
  specificity: [/\bspecificity\b/i, /\bspecific (?:instructions?|prompts?|requirements?)\b/i,
    /\bconstraints?\b/i, /\boutput formats?\b/i, /\bprecise instructions?\b/i],
  responsible_use: [/\bprivacy\b/i, /\bpersonal data\b/i, /\bbias\b/i,
    /\bfairness\b/i, /\bacademic integrity\b/i, /\bresponsible (?:ai|use)\b/i,
    /\bai safety\b/i, /\bethical (?:ai|use)\b/i],
  verification: [/\bverif(?:y|ication|ying)\b/i, /\bfact[ -]?check(?:ing)?\b/i,
    /\bdeepfakes?\b/i, /\bmisinformation\b/i, /\bcitations?\b/i,
    /\bhallucinations?\b/i, /\bsource (?:credibility|verification)\b/i,
    /\bevidence (?:quality|checking)\b/i],
});

export function textSupportsFocus(text, focusTopic) {
  if (typeof text !== 'string' || !VALID_TOPICS.has(focusTopic)) return false;
  return SIGNALS[focusTopic].some((pattern) => pattern.test(text));
}

// Only metadata-matched candidates are fetched. Full article content is checked
// again before sending anything to Groq; the chosen topic is enforced afterward.
export function selectCandidateFocus(candidate, focusTopics) {
  if (!candidate || typeof candidate !== 'object' || !Array.isArray(focusTopics)) return null;
  const metadata = `${candidate.title ?? ''} ${candidate.summary ?? ''}`;
  return focusTopics.find((topic) => textSupportsFocus(metadata, topic)) ?? null;
}

export function enforceDraftFocus(draft, focusTopic) {
  if (!draft || draft.topic_id !== focusTopic) {
    throw new Error(`Generated draft does not match the administrator-selected focus area: ${focusTopic}.`);
  }
  const overview = [draft.title, draft.summary,
    ...(Array.isArray(draft.objectives)
      ? draft.objectives.flatMap((objective) => [objective?.title, objective?.description])
      : []),
  ].join(' ');
  const instruction = Array.isArray(draft.lesson_sections)
    ? draft.lesson_sections.join(' ') : '';
  if (!textSupportsFocus(overview, focusTopic) ||
      !textSupportsFocus(instruction, focusTopic)) {
    throw new Error(`Generated lesson lacks substantive signals for the selected focus area: ${focusTopic}.`);
  }
}
