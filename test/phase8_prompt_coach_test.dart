import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/models/prompt_coach.dart';
import 'package:promptwise/data/services/prompt_coach_rubric_engine.dart';

void main() {
  group('Phase 8 Standard Coach rubric', () {
    test('detailed prompt scores higher than a vague prompt', () {
      final vague = PromptCoachRubricEngine.analyze('Make a report about AI.');
      final detailed = PromptCoachRubricEngine.analyze(
        'Write a 500-word report about generative AI for first-year college students. '
        'Use three sections, define two key limitations, avoid invented statistics, '
        'and clearly identify claims that should be verified using trusted sources.',
      );

      expect(detailed.scores.overall, greaterThan(vague.scores.overall));
      expect(
        detailed.scores.valueFor(PromptRubricDimension.expectedOutput),
        greaterThan(vague.scores.valueFor(PromptRubricDimension.expectedOutput)),
      );
      expect(
        detailed.scores.valueFor(PromptRubricDimension.constraints),
        greaterThan(vague.scores.valueFor(PromptRubricDimension.constraints)),
      );
    });

    test('email address blocks AI Coach', () {
      final analysis = PromptCoachRubricEngine.analyze(
        'Summarize this message for me. My email is student@example.com.',
      );

      expect(analysis.blocksAi, isTrue);
      expect(
        analysis.privacyFindings.any((finding) => finding.code == 'email'),
        isTrue,
      );
    });

    test('credential-like text blocks AI Coach', () {
      final analysis = PromptCoachRubricEngine.analyze(
        'Explain this API error. API key: abc123-secret-value',
      );

      expect(analysis.blocksAi, isTrue);
      expect(
        analysis.privacyFindings.any((finding) => finding.code == 'credential'),
        isTrue,
      );
    });

    test('normal learning prompt does not trigger a privacy block', () {
      final analysis = PromptCoachRubricEngine.analyze(
        'Explain prompt specificity for college students using two examples and a short comparison table.',
      );

      expect(analysis.blocksAi, isFalse);
      expect(
        analysis.scores.valueFor(PromptRubricDimension.privacySafety),
        1.0,
      );
    });
  });
}
