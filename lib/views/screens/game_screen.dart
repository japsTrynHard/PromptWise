import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/game_data.dart';
import '../../controllers/progress_controller.dart';
import '../../models/game_item.dart'; // FIXED: Imported your existing GameRound model

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  int _currentRound = 0;
  bool _answered = false;
  bool? _choseA;
  int _score = 0;

  GameRound get current => gameRounds[_currentRound];

  void _selectImage(bool isA) {
    if (_answered) return;
    setState(() {
      _answered = true;
      _choseA = isA;
      final correctAi = current.isAAI ? current.imagePathA : current.imagePathB;
      final userPicked = isA ? current.imagePathA : current.imagePathB;
      if (userPicked == correctAi) {
        _score += 100;
        context.read<ProgressController>().addGameBadge();
      }
    });
  }

  void _nextRound() {
    if (_currentRound < gameRounds.length - 1) {
      setState(() {
        _currentRound++;
        _answered = false;
        _choseA = null;
      });
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Game Over'),
          content: Text('Your score: $_score points'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Real or AI?'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: Text('Score: $_score'),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Which image is AI-generated?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _selectImage(true),
                            child: _ImageOption(
                              imagePath: current.imagePathA,
                              label: 'A',
                              selected: _choseA == true,
                              isCorrect: _answered
                                  ? (current.isAAI ? true : false)
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _selectImage(false),
                            child: _ImageOption(
                              imagePath: current.imagePathB,
                              label: 'B',
                              selected: _choseA == false,
                              isCorrect: _answered
                                  ? (current.isAAI ? false : true)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_answered) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(current.explanation),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_answered)
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextRound,
                  child: const Text('Next'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageOption extends StatelessWidget {
  final String imagePath;
  final String label;
  final bool selected;
  final bool? isCorrect;

  const _ImageOption({
    required this.imagePath,
    required this.label,
    required this.selected,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? (isCorrect == null
                    ? Theme.of(context).colorScheme.primary
                    : isCorrect!
                    ? Colors.green
                    : Colors.red)
              : Colors.grey.shade300,
          width: selected ? 3 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(imagePath, fit: BoxFit.cover),
            Positioned(
              top: 8,
              left: 8,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black54,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (selected && isCorrect != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: Icon(
                  isCorrect! ? Icons.check_circle : Icons.cancel,
                  color: isCorrect! ? Colors.green : Colors.red,
                  size: 32,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
