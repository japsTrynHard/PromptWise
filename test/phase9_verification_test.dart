import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/models/image_comparison.dart';
import 'package:promptwise/data/models/learning_progression.dart';
import 'package:promptwise/data/models/verification.dart';

void main() {
  group('Phase 9 verification model', () {
    test('all six verification skills keep stable database IDs', () {
      expect(VerificationSubskill.values, hasLength(6));
      expect(VerificationSubskill.values.map((item) => item.id).toSet(), {
        'source_verification',
        'claim_verification',
        'media_provenance',
        'manipulation_detection',
        'citation_verification',
        'uncertainty_judgment',
      });
    });

    test('learner labels stay plain and user-friendly', () {
      expect(
        VerificationSubskill.sourceVerification.learnerLabel,
        'Check the source',
      );
      expect(
        VerificationSubskill.mediaProvenance.learnerLabel,
        'Where did it come from?',
      );
      expect(VerificationDecision.aiGenerated.label, 'AI-made');
      expect(
        VerificationDecision.insufficientEvidence.label,
        'Not enough information',
      );
    });

    test('verification decisions include safe uncertainty choices', () {
      expect(
        VerificationDecision.values,
        contains(VerificationDecision.insufficientEvidence),
      );
      expect(
        VerificationDecision.values,
        contains(VerificationDecision.unverified),
      );
      expect(
        VerificationDecision.values,
        contains(VerificationDecision.misleadingContext),
      );
    });

    test('Quick Check case parses all answer and feedback fields', () {
      final item = VerificationCase.fromMap({
        'case_id': 'case-1',
        'case_code': 'sample',
        'title': 'Real photo, wrong date',
        'scenario': 'The same photo appeared online two years ago.',
        'claim_text': 'This photo was taken today.',
        'case_type': 'image',
        'subskill': 'media_provenance',
        'difficulty': 1,
        'media_type': 'image',
        'media_description': 'A reposted flood photo.',
        'evidence': const [],
        'actions': const [],
        'source_options': const [],
        'correct_decision': 'misleading_context',
        'expected_confidence': 'high',
        'explanation': 'The photo is old, so the new caption is misleading.',
        'learning_point': 'A real image can still have a false caption.',
        'generated_by': 'curated',
        'sequence': 1,
      });

      expect(item.subskill, VerificationSubskill.mediaProvenance);
      expect(item.difficulty, QuestionDifficulty.foundation);
      expect(item.correctDecision, VerificationDecision.misleadingContext);
      expect(item.isValid, isTrue);
    });

    test('malformed case without answer key is rejected safely', () {
      expect(
        () => VerificationCase.fromMap({
          'case_id': 'case-2',
          'title': 'Incomplete case',
          'scenario': 'Missing the answer key.',
          'subskill': 'claim_verification',
          'difficulty': 1,
          'explanation': 'Incomplete.',
        }),
        throwsFormatException,
      );
    });

    test('simple verification feedback keeps deterministic 0/100 result', () {
      final feedback = VerificationCaseFeedback.fromMap({
        'case_id': 'case-1',
        'subskill': 'citation_verification',
        'evidence_score': 0,
        'method_score': 0,
        'decision_score': 25,
        'source_score': 0,
        'confidence_score': 0,
        'total_score': 100,
        'decision_correct': true,
        'counted_for_mastery': true,
        'correct_decision': 'unsupported_claim',
        'explanation': 'The reference does not support the claim.',
        'learning_point': 'Check that the reference really matches the claim.',
        'subskill_mastery_after': 82,
      });

      expect(feedback.totalScore, 100);
      expect(feedback.decisionCorrect, isTrue);
      expect(feedback.correctDecision, VerificationDecision.unsupportedClaim);
      expect(feedback.subskillMasteryAfter, 82);
    });
  });

  group('Phase 9 online image comparison model', () {
    test('unanswered challenge contains no answer or source feedback', () {
      final challenge = <String, dynamic>{
        'id': 'round-1',
        'topic': 'city',
        'question': 'Which image is listed as AI-made by its source?',
        'hint': 'Make your best guess first.',
        'image_a': {
          'id': 'round-1:A',
          'image_url':
              'https://project.supabase.co/functions/v1/verification-media?round_id=round-1&side=A',
        },
        'image_b': {
          'id': 'round-1:B',
          'image_url':
              'https://project.supabase.co/functions/v1/verification-media?round_id=round-1&side=B',
        },
      };

      final round = ImageComparisonRound.fromMap(challenge);

      expect(round.id, 'round-1');
      expect(challenge, isNot(contains('correct_side')));
      expect(challenge, isNot(contains('explanation')));
      for (final imageKey in ['image_a', 'image_b']) {
        expect(
          (challenge[imageKey] as Map).keys,
          unorderedEquals(['id', 'image_url']),
        );
        expect(
          (challenge[imageKey] as Map)['image_url'],
          isNot(contains('upload.wikimedia.org')),
        );
      }
    });

    test('answer and source feedback parse only after submission', () {
      final feedback = ImageComparisonAttemptResult.fromMap({
        'round_id': 'round-1',
        'selected_side': 'A',
        'correct_side': 'B',
        'is_correct': false,
        'explanation': 'The original source identifies image B as AI-made.',
        'correct_source': {
          'title': 'Source-labeled image',
          'source_page_url':
              'https://commons.wikimedia.org/wiki/File:example.jpg',
          'creator': 'Example creator',
          'license': 'CC BY-SA',
        },
        'counted_for_mastery': true,
        'subskill_mastery_after': 75,
        'duplicate': false,
      });

      expect(feedback.isCorrect, isFalse);
      expect(feedback.selectedSide, 'A');
      expect(feedback.correctSide, 'B');
      expect(feedback.correctSource.creator, 'Example creator');
    });

    test('Edge Function never returns its internal round objects directly', () {
      final source = File(
        'supabase/functions/verification-media/index.ts',
      ).readAsStringSync();
      final start = source.indexOf('function toChallengePayload(');
      final end = source.indexOf('function toFeedbackPayload(', start);

      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      expect(source, contains('rounds: challengeRounds'));
      expect(
        RegExp(r'return json\(\{\s*rounds,', multiLine: true).hasMatch(source),
        isFalse,
      );

      final challengeBuilder = source.substring(start, end);
      for (final forbidden in [
        'correct_side',
        'explanation',
        'labeled_ai_generated',
        'source_page_url',
        'creator',
        'license',
        'upload.wikimedia.org',
      ]) {
        expect(challengeBuilder, isNot(contains(forbidden)));
      }
    });
  });
}
