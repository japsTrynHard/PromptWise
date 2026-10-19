/// Only score an image comparison after *both* images have displayed a frame.
/// The generation token discards callbacks from earlier rounds and retries.
enum ImageLoadStatus { loading, ready, failed }

class ImageRoundReadiness {
  String? _roundId;
  int _generation = 0;
  ImageLoadStatus _imageA = ImageLoadStatus.loading;
  ImageLoadStatus _imageB = ImageLoadStatus.loading;

  String? get roundId => _roundId;
  int get generation => _generation;
  bool get canSubmit =>
      _roundId != null &&
      _imageA == ImageLoadStatus.ready &&
      _imageB == ImageLoadStatus.ready;
  bool get hasFailure =>
      _imageA == ImageLoadStatus.failed || _imageB == ImageLoadStatus.failed;
  ImageLoadStatus get imageA => _imageA;
  ImageLoadStatus get imageB => _imageB;

  void reset(String? roundId) {
    _generation++;
    _roundId = roundId;
    _imageA = ImageLoadStatus.loading;
    _imageB = ImageLoadStatus.loading;
  }

  /// Returns true only for a state change in the current attempt.
  /// After failure, only an explicit reset/retry can make an image ready.
  bool record({
    required String roundId,
    required int generation,
    required String side,
    required ImageLoadStatus status,
  }) {
    if (_roundId != roundId ||
        _generation != generation ||
        status == ImageLoadStatus.loading) {
      return false;
    }
    final previous = side == 'A'
        ? _imageA
        : side == 'B'
        ? _imageB
        : null;
    // Failure takes precedence even if a previous frame was shown; a late
    // decode/network failure must immediately disable further submissions.
    if (previous == ImageLoadStatus.failed ||
        previous == status ||
        (previous == ImageLoadStatus.ready &&
            status != ImageLoadStatus.failed)) {
      return false;
    }
    if (side == 'A') {
      _imageA = status;
    } else if (side == 'B') {
      _imageB = status;
    } else {
      return false;
    }
    return true;
  }
}
