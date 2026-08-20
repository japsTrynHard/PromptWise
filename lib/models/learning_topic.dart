enum LearningTopic {
  promptClarity,
  context,
  specificity,
  responsibleUse,
  verification,
}

extension LearningTopicX on LearningTopic {
  String get id => switch (this) {
    LearningTopic.promptClarity => 'prompt_clarity',
    LearningTopic.context => 'context',
    LearningTopic.specificity => 'specificity',
    LearningTopic.responsibleUse => 'responsible_use',
    LearningTopic.verification => 'verification',
  };

  String get label => switch (this) {
    LearningTopic.promptClarity => 'Prompt clarity',
    LearningTopic.context => 'Context',
    LearningTopic.specificity => 'Specificity',
    LearningTopic.responsibleUse => 'Responsible AI use',
    LearningTopic.verification => 'Verification',
  };

  String get shortDescription => switch (this) {
    LearningTopic.promptClarity =>
      'State the task clearly so the AI can understand the goal.',
    LearningTopic.context =>
      'Provide the background and audience needed for a useful response.',
    LearningTopic.specificity =>
      'Add useful constraints, details, and an expected output format.',
    LearningTopic.responsibleUse =>
      'Use AI safely, protect privacy, and recognize appropriate boundaries.',
    LearningTopic.verification =>
      'Check evidence, sources, uncertainty, and potentially manipulated content.',
  };

  static LearningTopic? fromId(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    for (final topic in LearningTopic.values) {
      if (topic.id == normalized) return topic;
    }
    return null;
  }
}

/// Returns a topic only when the supplied text contains a meaningful signal.
/// Generic AI content is deliberately left untagged rather than being
/// incorrectly treated as Prompt clarity.
LearningTopic? inferLearningTopic(Iterable<String> values) {
  final text = values.join(' ').toLowerCase();

  // Explicit prompt-writing labels are stronger than incidental words such as
  // "audience" or "format" that may also appear in the same content.
  if (_containsAny(text, const [
    'prompt-writing check',
    'prompt writing check',
    'writing clear prompts',
    'clear prompts',
  ])) {
    return LearningTopic.promptClarity;
  }

  if (_containsAny(text, const [
    'verify',
    'verified',
    'verification',
    'evaluate',
    'evaluation',
    'accuracy',
    'accurate',
    'reliable',
    'claim',
    'claims',
    'misinformation',
    'deepfake',
    'fake',
    'source',
    'evidence',
    'citation',
    'real or ai',
    'ai-generated image',
    'manipulated',
    'fact check',
    'fact-check',
  ])) {
    return LearningTopic.verification;
  }

  if (_containsAny(text, const [
    'privacy',
    'responsible',
    'ethical',
    'ethics',
    'safety',
    'personal data',
    'sensitive',
    'bias',
    'harm',
    'scam',
  ])) {
    return LearningTopic.responsibleUse;
  }

  if (_containsAny(text, const [
    'specific',
    'specificity',
    'constraint',
    'format',
    'length',
    'tone',
    'requirements',
    'criteria',
    'expected output',
    'output format',
  ])) {
    return LearningTopic.specificity;
  }

  if (_containsAny(text, const [
    'context',
    'background',
    'audience',
    'role',
    'situation',
    'purpose',
  ])) {
    return LearningTopic.context;
  }

  if (_containsAny(text, const [
    'prompt clarity',
    'clear prompt',
    'clear task',
    'clear instruction',
    'state the task',
    'prompt writing',
    'prompt-writing',
    'prompt engineering',
  ])) {
    return LearningTopic.promptClarity;
  }

  return null;
}

bool _containsAny(String text, List<String> terms) {
  for (final term in terms) {
    if (text.contains(term)) return true;
  }
  return false;
}
