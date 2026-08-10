class PromptCoachFeedback {
  final double clarity;
  final double context;
  final double specificity;
  final double responsibility;
  final double overall;
  final List<String> strengths;
  final List<String> suggestions;
  final List<String> guidingQuestions;
  final String safetyReminder;
  final String summary;

  const PromptCoachFeedback({
    required this.clarity,
    required this.context,
    required this.specificity,
    required this.responsibility,
    required this.overall,
    required this.strengths,
    required this.suggestions,
    required this.guidingQuestions,
    required this.safetyReminder,
    required this.summary,
  });

  factory PromptCoachFeedback.fromMap(Map<String, dynamic> map) {
    double score(String key) {
      final value = map[key];
      if (value is num) return value.toDouble().clamp(0, 1).toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      return parsed == null ? 0 : parsed.clamp(0, 1).toDouble();
    }

    List<String> list(String key) {
      final value = map[key];
      if (value is! List) return const [];
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    final clarity = score('clarity');
    final context = score('context');
    final specificity = score('specificity');
    final responsibility = score('responsibility');
    final suppliedOverall = score('overall');

    return PromptCoachFeedback(
      clarity: clarity,
      context: context,
      specificity: specificity,
      responsibility: responsibility,
      overall: suppliedOverall > 0
          ? suppliedOverall
          : (clarity + context + specificity + responsibility) / 4,
      strengths: list('strengths'),
      suggestions: list('suggestions'),
      guidingQuestions: list('guidingQuestions'),
      safetyReminder: map['safetyReminder']?.toString().trim() ?? '',
      summary: map['summary']?.toString().trim() ?? '',
    );
  }
}
