import { validateLessonDraft } from './quality.mjs';

// Repair only depth failures; malformed shapes still fail the normal validator.
export function shortLessonSections(draft) {
  if (!Array.isArray(draft?.lesson_sections) || draft.lesson_sections.length !== 6) return [];
  const sections = draft.lesson_sections;
  if (sections.some(section => typeof section !== 'string' || section.indexOf('\n') <= 0)) return [];
  return sections.flatMap((section, index) => {
    const words = section.slice(section.indexOf('\n') + 1).trim().match(/\S+/gu)?.length ?? 0;
    return words < 120 ? [{ index, section, words }] : [];
  });
}

export function applySectionRepairs(draft, requested, payload) {
  const replacements = payload?.sections;
  const expected = new Set(requested.map(item => item.index));
  if (!Array.isArray(replacements) || replacements.length !== expected.size) {
    throw new Error('Section repair must return every requested section exactly once.');
  }
  const sections = [...draft.lesson_sections];
  for (const replacement of replacements) {
    if (!Number.isInteger(replacement?.index) || !expected.delete(replacement.index) ||
        typeof replacement.section !== 'string') {
      throw new Error('Section repair returned an invalid or duplicate section index.');
    }
    sections[replacement.index] = replacement.section;
  }
  const repaired = { ...draft, lesson_sections: sections };
  validateLessonDraft(repaired);
  return repaired;
}
