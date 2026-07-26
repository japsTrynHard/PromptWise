class Quiz {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const Quiz({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}
