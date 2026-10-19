import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:promptwise/data/models/image_comparison.dart';
import 'package:promptwise/data/services/verification_media_service.dart';
import 'package:promptwise/presentation/controllers/image_comparison_controller.dart';
import 'package:promptwise/presentation/controllers/image_round_readiness.dart';

class _FakeMediaGateway implements VerificationMediaGateway {
  int submissions = 0;
  Completer<ImageComparisonAttemptResult>? pending;

  @override
  Future<List<ImageComparisonRound>> fetchRounds({
    int count = 5,
    Set<String> seenIds = const {},
  }) async => const [
    ImageComparisonRound(
      id: 'round-1',
      topic: 'verification',
      question: 'Which is AI-made?',
      hint: 'Inspect both.',
      imageA: ImageComparisonSource(
        id: 'a',
        imageUrl: 'https://example.test/a.png',
      ),
      imageB: ImageComparisonSource(
        id: 'b',
        imageUrl: 'https://example.test/b.png',
      ),
    ),
  ];

  @override
  Future<ImageComparisonAttemptResult> submitAttempt({
    required String roundId,
    required String selectedSide,
  }) {
    submissions++;
    pending ??= Completer<ImageComparisonAttemptResult>();
    return pending!.future;
  }
}

void main() {
  test(
    'controller rejects unrendered/broken pairs without calling service',
    () async {
      final gateway = _FakeMediaGateway();
      final controller = ImageComparisonController(service: gateway);
      await controller.bindAuthenticatedUser('learner-test');
      expect(await controller.ensureRounds(), true);
      final images = ImageRoundReadiness()..reset('round-1');
      expect(
        await controller.submitAttempt(
          roundId: 'round-1',
          selectedSide: 'A',
          readiness: images,
        ),
        isNull,
      );
      final epoch = images.generation;
      images.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'A',
        status: ImageLoadStatus.failed,
      );
      images.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'B',
        status: ImageLoadStatus.ready,
      );
      expect(
        await controller.submitAttempt(
          roundId: 'round-1',
          selectedSide: 'B',
          readiness: images,
        ),
        isNull,
      );
      expect(gateway.submissions, 0);
      controller.dispose();
    },
  );

  test(
    'controller checks current round/side and blocks concurrent submissions',
    () async {
      final gateway = _FakeMediaGateway();
      final controller = ImageComparisonController(service: gateway);
      await controller.bindAuthenticatedUser('learner-test');
      await controller.ensureRounds();
      final images = ImageRoundReadiness()..reset('round-1');
      final epoch = images.generation;
      images.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'A',
        status: ImageLoadStatus.ready,
      );
      images.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'B',
        status: ImageLoadStatus.ready,
      );
      expect(
        await controller.submitAttempt(
          roundId: 'wrong-round',
          selectedSide: 'A',
          readiness: images,
        ),
        isNull,
      );
      expect(
        await controller.submitAttempt(
          roundId: 'round-1',
          selectedSide: 'C',
          readiness: images,
        ),
        isNull,
      );
      final first = controller.submitAttempt(
        roundId: 'round-1',
        selectedSide: 'A',
        readiness: images,
      );
      expect(
        await controller.submitAttempt(
          roundId: 'round-1',
          selectedSide: 'A',
          readiness: images,
        ),
        isNull,
      );
      expect(gateway.submissions, 1);
      gateway.pending!.complete(
        const ImageComparisonAttemptResult(
          roundId: 'round-1',
          selectedSide: 'A',
          correctSide: 'A',
          isCorrect: true,
          explanation: 'Evidence from the original source.',
          correctSource: ImageComparisonSourceFeedback(
            title: 'Original source',
            sourcePageUrl: 'https://example.test',
            creator: 'Test fixture',
            license: 'Test',
          ),
          countedForMastery: true,
          subskillMasteryAfter: 1,
          duplicate: false,
        ),
      );
      expect((await first)?.isCorrect, true);
      controller.dispose();
    },
  );
}
