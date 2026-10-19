import 'package:flutter_test/flutter_test.dart';

import 'package:promptwise/presentation/controllers/image_round_readiness.dart';

void main() {
  test('both decoded images are required before choosing', () {
    final readiness = ImageRoundReadiness()..reset('round-1');
    final epoch = readiness.generation;
    expect(readiness.canSubmit, false);
    expect(
      readiness.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'A',
        status: ImageLoadStatus.ready,
      ),
      true,
    );
    expect(readiness.canSubmit, false);
    expect(
      readiness.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'B',
        status: ImageLoadStatus.ready,
      ),
      true,
    );
    expect(readiness.canSubmit, true);
  });

  test('broken image blocks either choice until explicit retry', () {
    final readiness = ImageRoundReadiness()..reset('round-1');
    final epoch = readiness.generation;
    readiness.record(
      roundId: 'round-1',
      generation: epoch,
      side: 'A',
      status: ImageLoadStatus.failed,
    );
    readiness.record(
      roundId: 'round-1',
      generation: epoch,
      side: 'B',
      status: ImageLoadStatus.ready,
    );
    expect(readiness.hasFailure, true);
    expect(readiness.canSubmit, false);
    expect(
      readiness.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'A',
        status: ImageLoadStatus.ready,
      ),
      false,
    );
    expect(readiness.canSubmit, false);
    readiness.reset('round-1');
    final retryEpoch = readiness.generation;
    readiness.record(
      roundId: 'round-1',
      generation: retryEpoch,
      side: 'A',
      status: ImageLoadStatus.ready,
    );
    readiness.record(
      roundId: 'round-1',
      generation: retryEpoch,
      side: 'B',
      status: ImageLoadStatus.ready,
    );
    expect(readiness.canSubmit, true);
    expect(readiness.hasFailure, false);
  });

  test('callbacks from prior rounds and attempts are discarded', () {
    final readiness = ImageRoundReadiness()..reset('round-1');
    final staleEpoch = readiness.generation;
    readiness.reset('round-2');
    expect(
      readiness.record(
        roundId: 'round-1',
        generation: staleEpoch,
        side: 'A',
        status: ImageLoadStatus.ready,
      ),
      false,
    );
    expect(
      readiness.record(
        roundId: 'round-2',
        generation: staleEpoch,
        side: 'B',
        status: ImageLoadStatus.ready,
      ),
      false,
    );
    expect(readiness.canSubmit, false);
  });

  test('invalid side and duplicate notifications cannot affect readiness', () {
    final readiness = ImageRoundReadiness()..reset('round-1');
    final epoch = readiness.generation;
    expect(
      readiness.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'C',
        status: ImageLoadStatus.ready,
      ),
      false,
    );
    expect(
      readiness.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'A',
        status: ImageLoadStatus.ready,
      ),
      true,
    );
    expect(
      readiness.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'A',
        status: ImageLoadStatus.ready,
      ),
      false,
    );
    expect(readiness.imageA, ImageLoadStatus.ready);
    expect(readiness.hasFailure, false);
    expect(readiness.canSubmit, false);
  });

  test('late image failure overrides prior successful frame', () {
    final readiness = ImageRoundReadiness()..reset('round-1');
    final epoch = readiness.generation;
    readiness.record(
      roundId: 'round-1',
      generation: epoch,
      side: 'A',
      status: ImageLoadStatus.ready,
    );
    readiness.record(
      roundId: 'round-1',
      generation: epoch,
      side: 'B',
      status: ImageLoadStatus.ready,
    );
    expect(readiness.canSubmit, true);
    expect(
      readiness.record(
        roundId: 'round-1',
        generation: epoch,
        side: 'B',
        status: ImageLoadStatus.failed,
      ),
      true,
    );
    expect(readiness.canSubmit, false);
  });
}
