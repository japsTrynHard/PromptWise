import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/content_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../models/game_item.dart';
import '../../models/learning_topic.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/page_intro.dart';
import '../widgets/state_message.dart';

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
  bool _masteryCounted = false;
  List<GameRound> _sessionRounds = const [];
  String _roundSignature = '';

  List<GameRound> get _rounds => _sessionRounds;
  GameRound get _current => _rounds[_currentRound];

  void _prepareSessionRounds(List<GameRound> source) {
    final signature = source.map((round) => round.id).join('|');
    if (signature == _roundSignature) return;

    final adaptive = context.read<AdaptiveLearningController>();
    final eligible = <GameRound>[];
    final waiting = <GameRound>[];
    for (final round in source) {
      final canCount = adaptive.canCountEvidenceNow(
        itemId: round.id,
        topic: LearningTopic.verification,
        attemptType: 'verification_activity',
      );
      (canCount ? eligible : waiting).add(round);
    }
    _sessionRounds = [...eligible, ...waiting];
    _roundSignature = signature;
    _currentRound = 0;
    _answered = false;
    _choseA = null;
    _masteryCounted = false;
  }

  Future<void> _selectImage(bool isA) async {
    if (_answered || _rounds.isEmpty) return;

    final isCorrect = isA == _current.isAAI;
    setState(() {
      _answered = true;
      _choseA = isA;
      if (isCorrect) _score += 100;
    });

    final masteryCounted = await context
        .read<AdaptiveLearningController>()
        .recordPracticeAttempt(
          itemId: _current.id,
          topic: LearningTopic.verification,
          isCorrect: isCorrect,
          attemptType: 'verification_activity',
        );

    if (!mounted) return;
    setState(() => _masteryCounted = masteryCounted);
    if (isCorrect) {
      await context.read<ProgressController>().addGameBadge();
    }
  }

  Future<void> _nextRound() async {
    if (_currentRound < _rounds.length - 1) {
      setState(() {
        _currentRound++;
        _answered = false;
        _choseA = null;
        _masteryCounted = false;
      });
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.image_search_outlined),
        title: const Text('Activity complete'),
        content: Text(
          'You scored $_score out of ${_rounds.length * 100}. Visual clues can guide investigation, but source and context verification are still necessary.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourceRounds = context.watch<ContentController>().activities;
    _prepareSessionRounds(sourceRounds);
    final rounds = _sessionRounds;
    if (_currentRound >= rounds.length && rounds.isNotEmpty) {
      _currentRound = 0;
      _answered = false;
      _choseA = null;
      _masteryCounted = false;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Real or AI Activity'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Center(child: Chip(label: Text('Score $_score'))),
          ),
        ],
      ),
      body: rounds.isEmpty
          ? const StateMessage.empty(
              title: 'No activity available',
              message:
                  'Media verification activities will appear here when content is available.',
            )
          : AdaptiveBody(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: AdaptiveLayout.pageInsets(
                      context,
                      top: AppSpacing.sm,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 980),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PageIntro(
                                  title: 'Which image is likely AI-generated?',
                                  description:
                                      'Round ${_currentRound + 1} of ${rounds.length}. Examine both images, choose one, then review the evidence and uncertainty.',
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                AppCard(
                                  backgroundColor: AppColors.teal.withValues(
                                    alpha:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.11
                                        : 0.08,
                                  ),
                                  child: const Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        color: AppColors.teal,
                                      ),
                                      SizedBox(width: AppSpacing.md),
                                      Expanded(
                                        child: Text(
                                          'Do not treat one visual clue as perfect proof. A reliable decision also checks the original source, publication context, and available provenance.',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxl),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final cards = [
                                      _ImageChoice(
                                        label: 'Image A',
                                        imagePath: _current.imagePathA,
                                        selected: _choseA == true,
                                        answered: _answered,
                                        isCorrectChoice: _current.isAAI,
                                        onTap: () => _selectImage(true),
                                      ),
                                      _ImageChoice(
                                        label: 'Image B',
                                        imagePath: _current.imagePathB,
                                        selected: _choseA == false,
                                        answered: _answered,
                                        isCorrectChoice: !_current.isAAI,
                                        onTap: () => _selectImage(false),
                                      ),
                                    ];

                                    if (constraints.maxWidth >= 720) {
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(child: cards[0]),
                                          const SizedBox(width: AppSpacing.lg),
                                          Expanded(child: cards[1]),
                                        ],
                                      );
                                    }
                                    return Column(
                                      children: [
                                        cards[0],
                                        const SizedBox(height: AppSpacing.lg),
                                        cards[1],
                                      ],
                                    );
                                  },
                                ),
                                if (_answered) ...[
                                  const SizedBox(height: AppSpacing.xl),
                                  AppCard(
                                    backgroundColor:
                                        (_isCurrentCorrect
                                                ? AppColors.success
                                                : AppColors.warning)
                                            .withValues(
                                              alpha:
                                                  Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? 0.13
                                                  : 0.08,
                                            ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              _isCurrentCorrect
                                                  ? Icons.check_circle_rounded
                                                  : Icons.info_outline_rounded,
                                              color: _isCurrentCorrect
                                                  ? AppColors.success
                                                  : AppColors.warning,
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                            Expanded(
                                              child: Text(
                                                _isCurrentCorrect
                                                    ? 'Your choice matches the activity answer.'
                                                    : 'Your choice does not match the activity answer.',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        Text(
                                          _current.explanation,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(height: 1.55),
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        Text(
                                          _masteryCounted
                                              ? 'Verification mastery evidence counted for this round.'
                                              : 'This round was already counted for the current review cycle, so mastery did not increase again.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _nextRound,
                                      icon: const Icon(
                                        Icons.arrow_forward_rounded,
                                      ),
                                      label: Text(
                                        _currentRound < rounds.length - 1
                                            ? 'Next Round'
                                            : 'Finish Activity',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  bool get _isCurrentCorrect {
    if (!_answered || _choseA == null) return false;
    return _choseA == _current.isAAI;
  }
}

class _ImageChoice extends StatelessWidget {
  final String label;
  final String imagePath;
  final bool selected;
  final bool answered;
  final bool isCorrectChoice;
  final VoidCallback onTap;

  const _ImageChoice({
    required this.label,
    required this.imagePath,
    required this.selected,
    required this.answered,
    required this.isCorrectChoice,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Color border = colorScheme.outlineVariant;
    if (answered && isCorrectChoice) {
      border = AppColors.success;
    } else if (answered && selected && !isCorrectChoice) {
      border = AppColors.danger;
    } else if (selected) {
      border = colorScheme.primary;
    }

    return Semantics(
      button: true,
      label: '$label, select as the likely AI-generated image',
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: border,
            width: selected || (answered && isCorrectChoice) ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: answered ? null : onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: _buildImage(context, colorScheme),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (!answered)
                      OutlinedButton(
                        onPressed: onTap,
                        child: const Text('Choose'),
                      )
                    else
                      Icon(
                        isCorrectChoice
                            ? Icons.check_circle_rounded
                            : selected
                            ? Icons.cancel_rounded
                            : Icons.circle_outlined,
                        color: isCorrectChoice
                            ? AppColors.success
                            : selected
                            ? AppColors.danger
                            : colorScheme.outline,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context, ColorScheme colorScheme) {
    final uri = Uri.tryParse(imagePath);
    final isNetworkImage =
        uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
    Widget errorBuilder(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) {
      return ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                size: 42,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Image preview unavailable',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isNetworkImage) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: errorBuilder,
      );
    }
    return Image.asset(
      imagePath,
      fit: BoxFit.cover,
      errorBuilder: errorBuilder,
    );
  }
}
