class GameRound {
  final String id;
  final String title;
  final String imagePathA;
  final String imagePathB;
  final bool isAAI;
  final String explanation;

  const GameRound({
    required this.id,
    this.title = 'Real or AI?',
    required this.imagePathA,
    required this.imagePathB,
    required this.isAAI,
    required this.explanation,
  });
}
