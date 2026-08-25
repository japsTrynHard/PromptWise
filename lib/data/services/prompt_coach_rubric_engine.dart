import '../models/prompt_coach.dart';

class PromptCoachRubricEngine {
  const PromptCoachRubricEngine._();

  static PromptCoachAnalysis analyze(String prompt) {
    final cleaned = prompt.trim();
    final lower = cleaned.toLowerCase();
    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final wordCount = words.length;

    final privacyFindings = inspectPrivacy(cleaned);
    final blocksAi = privacyFindings.any((finding) => finding.blocksAi);

    final hasTaskVerb = _containsAny(lower, const [
      'analyze',
      'create',
      'define',
      'describe',
      'design',
      'evaluate',
      'explain',
      'identify',
      'list',
      'make',
      'outline',
      'review',
      'summarize',
      'compare',
      'write',
      'classify',
      'recommend',
      'generate',
      'revise',
      'critique',
      'gumawa',
      'ipaliwanag',
      'ihambing',
      'ibuod',
      'suriin',
      'ilarawan',
      'magbigay',
    ]);

    final hasAudience = _containsAny(lower, const [
      'audience',
      'beginner',
      'student',
      'teacher',
      'reader',
      'customer',
      'manager',
      'developer',
      'for children',
      'for adults',
      'para sa',
      'estudyante',
      'guro',
      'mambabasa',
      'target user',
    ]);

    final hasPurpose = _containsAny(lower, const [
      'purpose',
      'goal',
      'objective',
      'so that',
      'because',
      'dahil',
      'layunin',
      'gamitin para',
    ]);

    final hasBackground = _containsAny(lower, const [
      'background',
      'context',
      'given that',
      'based on',
      'scenario',
      'situation',
      'konteksto',
      'batay sa',
      'sitwasyon',
    ]);

    final hasConcreteSubject = wordCount >= 8 &&
        (_containsAny(lower, const [
              'about',
              'regarding',
              'for',
              'using',
              'based on',
              'tungkol',
              'gamit',
            ]) ||
            cleaned.contains(':'));

    final hasStepsOrSequence = RegExp(
          r'(^|\s)(first|second|then|next|finally|step\s*\d|1\.|2\.|3\.)',
          caseSensitive: false,
        ).hasMatch(cleaned) ||
        _containsAny(lower, const [
          'include',
          'cover',
          'address',
          'explain then',
          'first',
          'then',
          'finally',
          'isama',
          'una',
          'sunod',
        ]);

    final hasOutputFormat = _containsAny(lower, const [
      'paragraph',
      'sentence',
      'bullet',
      'table',
      'json',
      'outline',
      'report',
      'email',
      'presentation',
      'code',
      'format',
      'structure',
      'talata',
      'pangungusap',
      'pormat',
      'listahan',
    ]);

    final hasLengthOrCount = RegExp(r'\b\d+\b').hasMatch(lower) ||
        _containsAny(lower, const [
          'short',
          'concise',
          'detailed',
          'brief',
          'words',
          'characters',
          'minutes',
          'maikli',
          'detalyado',
        ]);

    final hasToneOrStyle = _containsAny(lower, const [
      'tone',
      'formal',
      'casual',
      'professional',
      'simple language',
      'technical',
      'friendly',
      'academic',
      'style',
      'tono',
      'simple words',
    ]);

    final hasConstraintLanguage = _containsAny(lower, const [
      'must',
      'should',
      'only',
      'do not',
      "don't",
      'avoid',
      'limit',
      'maximum',
      'minimum',
      'without',
      'at least',
      'no more than',
      'required',
      'constraint',
      'bawal',
      'iwasan',
      'limitahan',
      'dapat',
    ]);

    final asksForVerification = _containsAny(lower, const [
      'verify',
      'verification',
      'source',
      'citation',
      'evidence',
      'uncertainty',
      'limitations',
      'check accuracy',
      'fact check',
      'cross-check',
      'human review',
      'beripikahin',
      'sanggunian',
      'pinagmulan',
      'katumpakan',
    ]);

    final mentionsResponsibleBoundary = _containsAny(lower, const [
      'privacy',
      'personal data',
      'sensitive',
      'bias',
      'fairness',
      'ethical',
      'responsible',
      'do not fabricate',
      'do not invent',
      'acknowledge uncertainty',
      'confidential',
      'pribado',
      'responsable',
    ]);

    double clarity = 0.28;
    if (hasTaskVerb) clarity += 0.42;
    if (wordCount >= 8) clarity += 0.16;
    if (wordCount >= 18) clarity += 0.08;
    if (_containsAny(lower, const ['something', 'anything', 'stuff', 'etc.'])) {
      clarity -= 0.08;
    }

    double context = 0.2;
    if (hasAudience) context += 0.28;
    if (hasPurpose) context += 0.25;
    if (hasBackground) context += 0.25;
    if (wordCount >= 25) context += 0.06;

    double specificity = 0.25;
    if (hasConcreteSubject) specificity += 0.22;
    if (hasLengthOrCount) specificity += 0.18;
    if (hasOutputFormat) specificity += 0.18;
    if (hasToneOrStyle) specificity += 0.12;
    if (hasConstraintLanguage) specificity += 0.1;

    double instructions = 0.28;
    if (hasTaskVerb) instructions += 0.28;
    if (hasStepsOrSequence) instructions += 0.3;
    if (hasConstraintLanguage) instructions += 0.12;
    if (wordCount >= 20) instructions += 0.06;

    double expectedOutput = 0.24;
    if (hasOutputFormat) expectedOutput += 0.36;
    if (hasLengthOrCount) expectedOutput += 0.2;
    if (hasToneOrStyle) expectedOutput += 0.16;
    if (_containsAny(lower, const ['example', 'examples', 'halimbawa'])) {
      expectedOutput += 0.08;
    }

    double constraints = 0.22;
    if (hasConstraintLanguage) constraints += 0.42;
    if (hasLengthOrCount) constraints += 0.16;
    if (asksForVerification) constraints += 0.12;
    if (_containsAny(lower, const ['criteria', 'requirement', 'requirements'])) {
      constraints += 0.08;
    }

    final privacySafety = blocksAi ? 0.2 : 1.0;

    double responsibleUse = 0.55;
    if (asksForVerification) responsibleUse += 0.25;
    if (mentionsResponsibleBoundary) responsibleUse += 0.18;
    if (blocksAi) responsibleUse -= 0.28;

    final scores = PromptRubricScore({
      PromptRubricDimension.clarity: clarity,
      PromptRubricDimension.context: context,
      PromptRubricDimension.specificity: specificity,
      PromptRubricDimension.instructions: instructions,
      PromptRubricDimension.expectedOutput: expectedOutput,
      PromptRubricDimension.constraints: constraints,
      PromptRubricDimension.privacySafety: privacySafety,
      PromptRubricDimension.responsibleUse: responsibleUse,
    });

    final strengths = <String>[];
    final suggestions = <String>[];
    final questions = <String>[];

    void evaluate({
      required PromptRubricDimension dimension,
      required String strong,
      required String improve,
      required String question,
    }) {
      final score = scores.valueFor(dimension);
      if (score >= 0.78) {
        strengths.add(strong);
      } else if (score < 0.68) {
        suggestions.add(improve);
        if (questions.length < 4) questions.add(question);
      }
    }

    evaluate(
      dimension: PromptRubricDimension.clarity,
      strong: 'The main task is easy to identify.',
      improve: 'State the main task with a precise action verb.',
      question: 'What exactly should the AI help you do?',
    );
    evaluate(
      dimension: PromptRubricDimension.context,
      strong: 'The prompt gives useful context for the task.',
      improve: 'Add the audience, purpose, or background that changes the answer.',
      question: 'What context would prevent the request from being misunderstood?',
    );
    evaluate(
      dimension: PromptRubricDimension.specificity,
      strong: 'The request contains concrete details rather than a vague goal.',
      improve: 'Add the specific details that define a successful response.',
      question: 'Which details are required, and which are optional?',
    );
    evaluate(
      dimension: PromptRubricDimension.instructions,
      strong: 'The instructions explain how the task should be approached.',
      improve: 'Break complex work into clear instructions or decision criteria.',
      question: 'What should the AI do first, and what should it avoid doing?',
    );
    evaluate(
      dimension: PromptRubricDimension.expectedOutput,
      strong: 'The expected output is described clearly.',
      improve: 'Specify the format, length, structure, or tone of the output.',
      question: 'What should the final response look like?',
    );
    evaluate(
      dimension: PromptRubricDimension.constraints,
      strong: 'Useful constraints narrow the range of acceptable answers.',
      improve: 'Add limits or requirements only where they improve the result.',
      question: 'What boundaries must the response follow?',
    );
    evaluate(
      dimension: PromptRubricDimension.responsibleUse,
      strong: 'The prompt includes responsible-use or verification guidance.',
      improve: 'For factual or high-impact tasks, add verification or uncertainty guidance.',
      question: 'Which claims should the learner verify independently?',
    );

    if (privacyFindings.isNotEmpty) {
      suggestions.insert(
        0,
        'Remove sensitive or identifying information before using any online AI service.',
      );
    } else {
      strengths.add('No obvious high-risk private information was detected.');
    }

    final overall = scores.overallPercent;
    final summary = switch (overall) {
      >= 85 =>
        'Strong prompt structure. Refine only the feedback that improves the task without adding unnecessary detail.',
      >= 70 =>
        'Good foundation. A focused revision can make the task more precise and easier to evaluate.',
      >= 50 =>
        'The intent is visible, but several important prompt components still need clarification.',
      _ =>
        'Start by clarifying the task, context, and expected output before adding more constraints.',
    };

    return PromptCoachAnalysis(
      scores: scores,
      strengths: strengths.take(5).toList(growable: false),
      suggestions: suggestions.take(6).toList(growable: false),
      guidingQuestions: questions.take(4).toList(growable: false),
      privacyFindings: privacyFindings,
      summary: summary,
    );
  }

  static List<PromptPrivacyFinding> inspectPrivacy(String prompt) {
    final findings = <PromptPrivacyFinding>[];
    final lower = prompt.toLowerCase();

    void add(String code, String label, String message, {bool blocksAi = true}) {
      if (findings.any((item) => item.code == code)) return;
      findings.add(
        PromptPrivacyFinding(
          code: code,
          label: label,
          message: message,
          blocksAi: blocksAi,
        ),
      );
    }

    if (RegExp(r'[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}').hasMatch(prompt)) {
      add(
        'email',
        'Email address detected',
        'Remove personal email addresses before sending the prompt to AI Coach.',
      );
    }

    if (RegExp(
      r'\b(?:\+?63|0)?9\d{9}\b|\b\+?\d[\d\s-]{8,14}\d\b',
    ).hasMatch(prompt)) {
      add(
        'phone',
        'Phone number detected',
        'Remove phone numbers unless they are clearly fictional examples.',
      );
    }

    if (_containsAny(lower, const [
      'password:',
      'password is',
      'api key:',
      'apikey:',
      'secret key:',
      'access token:',
      'bearer ',
      'private key',
    ])) {
      add(
        'credential',
        'Credential-like information detected',
        'Never send passwords, API keys, tokens, or private keys to an AI service.',
      );
    }

    if (RegExp(r'\b(?:\d[ -]*?){13,19}\b').hasMatch(prompt) &&
        _containsAny(lower, const ['card', 'visa', 'mastercard', 'credit', 'debit'])) {
      add(
        'payment',
        'Payment information detected',
        'Remove card or payment information before using AI Coach.',
      );
    }

    if (RegExp(r'\b\d{8,14}\b').hasMatch(prompt) &&
        _containsAny(lower, const [
          'student id',
          'student number',
          'account number',
          'government id',
          'passport',
          'license number',
        ])) {
      add(
        'identifier',
        'Sensitive identifier detected',
        'Replace real account, student, or government identifiers with placeholders.',
      );
    }

    if (_containsAny(lower, const [
      'confidential:',
      'private medical record',
      'patient record',
      'salary record',
      'disciplinary record',
    ])) {
      add(
        'confidential',
        'Confidential information detected',
        'Use a fictional or anonymized example instead of confidential records.',
      );
    }

    return List.unmodifiable(findings);
  }

  static bool _containsAny(String value, List<String> terms) {
    return terms.any(value.contains);
  }
}
