import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/models/image_comparison.dart';
import 'package:promptwise/data/services/verification_media_service.dart';
import 'package:promptwise/presentation/controllers/image_comparison_controller.dart';

void main() {
  test(
    'fresh-set request loads immediately and preserves old rounds on failure',
    () async {
      final service = _FakeMediaGateway();
      final controller = ImageComparisonController(service: service);
      await controller.bindAuthenticatedUser('user-a');

      final initial = controller.ensureRounds(count: 3);
      expect(controller.isLoading, isTrue);
      service.completeFetch([_round('first'), _round('second')]);
      expect(await initial, isTrue);
      final oldRounds = controller.rounds;

      final refresh = controller.loadFreshRounds(count: 3);
      expect(controller.isLoading, isTrue);
      expect(controller.rounds, oldRounds);
      expect(service.fetchCalls, 2);
      service.failFetch(StateError('upstream failed'));
      expect(await refresh, isFalse);

      expect(controller.rounds, oldRounds);
      expect(controller.errorMessage, contains('upstream failed'));
      expect(controller.isLoading, isFalse);
    },
  );

  test('User A fetch cannot update User B', () async {
    final service = _FakeMediaGateway();
    final controller = ImageComparisonController(service: service);
    await controller.bindAuthenticatedUser('user-a');
    final request = controller.ensureRounds();

    await controller.bindAuthenticatedUser('user-b');
    service.completeFetch([_round('a'), _round('b')]);

    expect(await request, isFalse);
    expect(controller.rounds, isEmpty);
  });

  test('User A submission result cannot update User B', () async {
    final service = _FakeMediaGateway();
    final controller = ImageComparisonController(service: service);
    await controller.bindAuthenticatedUser('user-a');

    final request = controller.submitAttempt(
      roundId: 'round-a',
      selectedSide: 'A',
    );
    await controller.bindAuthenticatedUser('user-b');
    service.completeSubmission('round-a');

    expect(await request, isNull);
    expect(controller.errorMessage, isNull);
  });
}

ImageComparisonRound _round(String id) => ImageComparisonRound(
  id: id,
  topic: 'online image',
  question: 'Which image is AI-made?',
  hint: 'Check the source.',
  imageA: ImageComparisonSource(
    id: '$id-a',
    imageUrl: 'https://example.com/$id-a.jpg',
  ),
  imageB: ImageComparisonSource(
    id: '$id-b',
    imageUrl: 'https://example.com/$id-b.jpg',
  ),
);

class _FakeMediaGateway implements VerificationMediaGateway {
  final _fetches = <Completer<List<ImageComparisonRound>>>[];
  final _submissions = <String, Completer<ImageComparisonAttemptResult>>{};
  int get fetchCalls => _fetches.length;

  @override
  Future<List<ImageComparisonRound>> fetchRounds({
    int count = 5,
    Set<String> seenIds = const {},
  }) {
    final completer = Completer<List<ImageComparisonRound>>();
    _fetches.add(completer);
    return completer.future;
  }

  void completeFetch(List<ImageComparisonRound> rounds) {
    _fetches.firstWhere((item) => !item.isCompleted).complete(rounds);
  }

  void failFetch(Object error) {
    _fetches.firstWhere((item) => !item.isCompleted).completeError(error);
  }

  @override
  Future<ImageComparisonAttemptResult> submitAttempt({
    required String roundId,
    required String selectedSide,
  }) => (_submissions[roundId] ??= Completer<ImageComparisonAttemptResult>())
      .future;

  void completeSubmission(String roundId) {
    _submissions[roundId]!.complete(
      ImageComparisonAttemptResult(
        roundId: roundId,
        selectedSide: 'A',
        correctSide: 'A',
        isCorrect: true,
        explanation: 'The source identifies image A as AI-made.',
        correctSource: const ImageComparisonSourceFeedback(
          title: 'Source-labeled image',
          sourcePageUrl: 'https://commons.wikimedia.org/wiki/File:example',
          creator: 'Creator',
          license: 'CC',
        ),
        countedForMastery: true,
        subskillMasteryAfter: 65,
        duplicate: false,
      ),
    );
  }
}
