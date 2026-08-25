class ImageComparisonSource {
  final String id;
  final String title;
  final String imageUrl;
  final String sourcePageUrl;
  final String creator;
  final String license;
  final bool labeledAiGenerated;

  const ImageComparisonSource({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.sourcePageUrl,
    required this.creator,
    required this.license,
    required this.labeledAiGenerated,
  });

  factory ImageComparisonSource.fromMap(Map<String, dynamic> map) {
    return ImageComparisonSource(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Untitled image',
      imageUrl: map['image_url']?.toString() ?? '',
      sourcePageUrl: map['source_page_url']?.toString() ?? '',
      creator: map['creator']?.toString() ?? '',
      license: map['license']?.toString() ?? '',
      labeledAiGenerated: map['labeled_ai_generated'] == true,
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
  final String explanation;
  final ImageComparisonSource imageA;
  final ImageComparisonSource imageB;
  final String correctSide;

  const ImageComparisonRound({
    required this.id,
    required this.topic,
    required this.question,
    required this.hint,
    required this.explanation,
    required this.imageA,
    required this.imageB,
    required this.correctSide,
  });

  factory ImageComparisonRound.fromMap(Map<String, dynamic> map) {
    final rawA = map['image_a'];
    final rawB = map['image_b'];
    if (rawA is! Map || rawB is! Map) {
      throw const FormatException('Image comparison round is incomplete.');
    }
    final a = ImageComparisonSource.fromMap(Map<String, dynamic>.from(rawA));
    final b = ImageComparisonSource.fromMap(Map<String, dynamic>.from(rawB));
    final side = map['correct_side']?.toString().toUpperCase();
    if (!a.isUsable || !b.isUsable || (side != 'A' && side != 'B')) {
      throw const FormatException('Image comparison round is invalid.');
    }
    return ImageComparisonRound(
      id: map['id']?.toString() ?? '${a.id}-${b.id}',
      topic: map['topic']?.toString() ?? 'image',
      question: map['question']?.toString() ?? 'Which image is AI-made?',
      hint: map['hint']?.toString() ?? 'Look closely, then check the source after you answer.',
      explanation: map['explanation']?.toString() ?? '',
      imageA: a,
      imageB: b,
      correctSide: side!,
    );
  }

  bool isCorrect(String side) => side.toUpperCase() == correctSide;
  ImageComparisonSource get correctImage =>
      correctSide == 'A' ? imageA : imageB;
}
