class ImageComparisonSource {
  final String id;
  final String imageUrl;

  const ImageComparisonSource({required this.id, required this.imageUrl});

  factory ImageComparisonSource.fromMap(Map<String, dynamic> map) {
    return ImageComparisonSource(
      id: map['id']?.toString() ?? '',
      imageUrl: map['image_url']?.toString() ?? '',
    );
  }

  bool get isUsable =>
      id.trim().isNotEmpty &&
      imageUrl.trim().isNotEmpty &&
      Uri.tryParse(imageUrl)?.hasScheme == true;
}

class ImageComparisonRound {
  final String id;
  final String topic;
  final String question;
  final String hint;
  final ImageComparisonSource imageA;
  final ImageComparisonSource imageB;

  const ImageComparisonRound({
    required this.id,
    required this.topic,
    required this.question,
    required this.hint,
    required this.imageA,
    required this.imageB,
  });

  factory ImageComparisonRound.fromMap(Map<String, dynamic> map) {
    final rawA = map['image_a'];
    final rawB = map['image_b'];
    if (rawA is! Map || rawB is! Map) {
      throw const FormatException('Image comparison round is incomplete.');
    }
    final a = ImageComparisonSource.fromMap(Map<String, dynamic>.from(rawA));
    final b = ImageComparisonSource.fromMap(Map<String, dynamic>.from(rawB));
    if (!a.isUsable || !b.isUsable) {
      throw const FormatException('Image comparison round is invalid.');
    }
    return ImageComparisonRound(
      id: map['id']?.toString() ?? '${a.id}-${b.id}',
      topic: map['topic']?.toString() ?? 'image',
      question: map['question']?.toString() ?? 'Which image is AI-made?',
      hint:
          map['hint']?.toString() ??
          'Look closely, then check the source after you answer.',
      imageA: a,
      imageB: b,
    );
  }
}

class ImageComparisonSourceFeedback {
  final String title;
  final String sourcePageUrl;
  final String creator;
  final String license;

  const ImageComparisonSourceFeedback({
    required this.title,
    required this.sourcePageUrl,
    required this.creator,
    required this.license,
  });

  factory ImageComparisonSourceFeedback.fromMap(Map<String, dynamic> map) {
    final title = map['title']?.toString().trim() ?? '';
    if (title.isEmpty) {
      throw const FormatException('Image source feedback is incomplete.');
    }
    return ImageComparisonSourceFeedback(
      title: title,
      sourcePageUrl: map['source_page_url']?.toString().trim() ?? '',
      creator: map['creator']?.toString().trim() ?? '',
      license: map['license']?.toString().trim() ?? '',
    );
  }
}

class ImageComparisonAttemptResult {
  final String roundId;
  final String selectedSide;
  final String correctSide;
  final bool isCorrect;
  final String explanation;
  final ImageComparisonSourceFeedback correctSource;
  final bool countedForMastery;
  final int subskillMasteryAfter;
  final bool duplicate;

  const ImageComparisonAttemptResult({
    required this.roundId,
    required this.selectedSide,
    required this.correctSide,
    required this.isCorrect,
    required this.explanation,
    required this.correctSource,
    required this.countedForMastery,
    required this.subskillMasteryAfter,
    required this.duplicate,
  });

  factory ImageComparisonAttemptResult.fromMap(Map<String, dynamic> map) {
    final roundId = map['round_id']?.toString().trim() ?? '';
    if (roundId.isEmpty) {
      throw const FormatException('Image comparison attempt is incomplete.');
    }
    final selectedSide = map['selected_side']?.toString().toUpperCase() ?? '';
    final correctSide = map['correct_side']?.toString().toUpperCase() ?? '';
    final explanation = map['explanation']?.toString().trim() ?? '';
    final rawSource = map['correct_source'];
    if ((selectedSide != 'A' && selectedSide != 'B') ||
        (correctSide != 'A' && correctSide != 'B') ||
        explanation.isEmpty ||
        rawSource is! Map) {
      throw const FormatException('Image comparison feedback is incomplete.');
    }
    return ImageComparisonAttemptResult(
      roundId: roundId,
      selectedSide: selectedSide,
      correctSide: correctSide,
      isCorrect: map['is_correct'] == true,
      explanation: explanation,
      correctSource: ImageComparisonSourceFeedback.fromMap(
        Map<String, dynamic>.from(rawSource),
      ),
      countedForMastery: map['counted_for_mastery'] == true,
      subskillMasteryAfter:
          int.tryParse(map['subskill_mastery_after']?.toString() ?? '') ?? 0,
      duplicate: map['duplicate'] == true,
    );
  }
}
