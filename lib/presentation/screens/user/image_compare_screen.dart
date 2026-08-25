import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/image_comparison.dart';
import '../../../data/models/learning_topic.dart';
import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/image_comparison_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/state_message.dart';
import '../../../core/utils/constants.dart';

class ImageCompareScreen extends StatefulWidget {
  const ImageCompareScreen({super.key});

  @override
  State<ImageCompareScreen> createState() => _ImageCompareScreenState();
}

class _ImageCompareScreenState extends State<ImageCompareScreen> {
  int _index = 0;

  String? _choice;

  bool _answered = false;
  bool _masteryCounted = false;

  int _score = 0;

  bool _completed = false;
  bool _requestedInitialLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_requestedInitialLoad) {
      return;
    }

    _requestedInitialLoad = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _ensureReady();
    });
  }

  Future<void> _ensureReady() async {
    final controller = context.read<ImageComparisonController>();

    final loaded = await controller.ensureRounds(count: 5);

    if (!mounted || !loaded) {
      return;
    }

    _resetActivity();

    _warmImages(controller.rounds, 0);
  }

  Future<void> _loadFresh() async {
    final controller = context.read<ImageComparisonController>();

    final loaded = await controller.loadFreshRounds(count: 5);

    if (!mounted || !loaded) {
      return;
    }

    _resetActivity();

    _warmImages(controller.rounds, 0);
  }

  void _resetActivity() {
    setState(() {
      _index = 0;

      _choice = null;

      _answered = false;
      _masteryCounted = false;

      _score = 0;

      _completed = false;
    });
  }

  void _warmImages(List<ImageComparisonRound> rounds, int fromIndex) {
    if (!mounted || rounds.isEmpty) {
      return;
    }

    final end = (fromIndex + 2).clamp(0, rounds.length);

    for (var i = fromIndex; i < end; i++) {
      final round = rounds[i];

      unawaited(precacheImage(NetworkImage(round.imageA.imageUrl), context));

      unawaited(precacheImage(NetworkImage(round.imageB.imageUrl), context));
    }
  }

  Future<void> _choose(ImageComparisonRound round, String side) async {
    if (_answered) {
      return;
    }

    final correct = round.isCorrect(side);

    setState(() {
      _choice = side;
      _answered = true;

      if (correct) {
        _score += 1;
      }
    });

    final counted = await context
        .read<AdaptiveLearningController>()
        .recordPracticeAttempt(
          itemId: 'image_compare:${round.id}',
          topic: LearningTopic.verification,
          isCorrect: correct,
          attemptType: 'verification_activity',
        );

    if (!mounted) {
      return;
    }

    setState(() => _masteryCounted = counted);

    if (correct) {
      await context.read<ProgressController>().addGameBadge();
    }
  }

  void _next(List<ImageComparisonRound> rounds) {
    if (_index < rounds.length - 1) {
      final nextIndex = _index + 1;

      setState(() {
        _index = nextIndex;

        _choice = null;

        _answered = false;
        _masteryCounted = false;
      });

      _warmImages(rounds, nextIndex);

      return;
    }

    setState(() => _completed = true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ImageComparisonController>();

    final rounds = controller.rounds;

    final theme = Theme.of(context);

    final compact = AdaptiveLayout.isCompact(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,

        toolbarHeight: compact ? 76 : 88,

        elevation: 0,
        scrolledUnderElevation: 0,

        surfaceTintColor: Colors.transparent,

        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.96),

        leadingWidth: compact ? 68 : 78,

        leading: Padding(
          padding: EdgeInsets.only(
            left: compact ? AppSpacing.md : AppSpacing.xl,
            top: AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Tooltip(
            message: 'Back to Verify',
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,

              shape: const CircleBorder(),

              child: InkWell(
                customBorder: const CircleBorder(),

                onTap: () => Navigator.maybePop(context),

                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
              ),
            ),
          ),
        ),

        titleSpacing: AppSpacing.sm,

        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          mainAxisSize: MainAxisSize.min,

          children: [
            Text(
              'VERIFY · IMAGE CHALLENGE',

              maxLines: 1,

              overflow: TextOverflow.ellipsis,

              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,

                fontWeight: FontWeight.w800,

                letterSpacing: 0.8,
              ),
            ),

            const SizedBox(height: 2),

            Text(
              'Compare Images',

              maxLines: 1,

              overflow: TextOverflow.ellipsis,

              style:
                  (compact
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(
                        fontWeight: FontWeight.w800,

                        letterSpacing: -0.4,
                      ),
            ),

            if (!compact)
              Text(
                'Guess first, then check what the original source says.',

                maxLines: 1,

                overflow: TextOverflow.ellipsis,

                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),

        actions: [
          Container(
            margin: EdgeInsets.only(
              right: compact ? AppSpacing.md : AppSpacing.xl,
            ),

            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),

            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,

              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),

            child: Text(
              '$_score / ${rounds.isEmpty ? 5 : rounds.length}',

              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,

                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),

          child: Divider(
            height: 1,

            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),

      body: controller.isLoading && rounds.isEmpty
          ? const _LoadingChallengeView()
          : controller.errorMessage != null && rounds.isEmpty
          ? AdaptiveBody(
              child: Padding(
                padding: AdaptiveLayout.pageInsets(context),

                child: StateMessage.error(
                  title: 'Fresh images could not load',

                  message: controller.errorMessage!,

                  actionLabel: 'Try again',

                  onAction: _loadFresh,
                ),
              ),
            )
          : rounds.isEmpty
          ? AdaptiveBody(
              child: Padding(
                padding: AdaptiveLayout.pageInsets(context),

                child: StateMessage.empty(
                  title: 'No image challenge yet',

                  message:
                      'PromptWise could not prepare enough online image examples. Try again in a moment.',

                  actionLabel: 'Try again',

                  onAction: _loadFresh,
                ),
              ),
            )
          : _completed
          ? _CompleteView(
              score: _score,

              total: rounds.length,

              onAnotherSet: _loadFresh,
            )
          : _RoundView(
              round: rounds[_index.clamp(0, rounds.length - 1)],

              roundNumber: _index + 1,

              totalRounds: rounds.length,

              choice: _choice,

              answered: _answered,

              masteryCounted: _masteryCounted,

              onChoose: (side) => _choose(rounds[_index], side),

              onNext: () => _next(rounds),
            ),
    );
  }
}

class _RoundView extends StatelessWidget {
  final ImageComparisonRound round;

  final int roundNumber;
  final int totalRounds;

  final String? choice;

  final bool answered;
  final bool masteryCounted;

  final ValueChanged<String> onChoose;

  final VoidCallback onNext;

  const _RoundView({
    required this.round,
    required this.roundNumber,
    required this.totalRounds,
    required this.choice,
    required this.answered,
    required this.masteryCounted,
    required this.onChoose,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final correct = choice != null && round.isCorrect(choice!);

    return AdaptiveBody(
      child: SingleChildScrollView(
        padding: AdaptiveLayout.pageInsets(context, top: AppSpacing.lg),

        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            'Round $roundNumber of $totalRounds',

                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,

                              fontWeight: FontWeight.w700,
                            ),
                          ),

                          const SizedBox(height: AppSpacing.xs),

                          Text(
                            'Which image does its source identify as AI-made?',

                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: AppSpacing.xs),

                          Text(
                            'Pick one first. Then PromptWise will show what the original source says.',

                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: AppSpacing.lg),

                    SizedBox(
                      width: 90,

                      child: LinearProgressIndicator(
                        value: roundNumber / totalRounds,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xxl),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final children = [
                      _ImageCard(
                        side: 'A',

                        source: round.imageA,

                        selected: choice == 'A',

                        answered: answered,

                        correctSide: round.correctSide,

                        onTap: () => onChoose('A'),
                      ),

                      _ImageCard(
                        side: 'B',

                        source: round.imageB,

                        selected: choice == 'B',

                        answered: answered,

                        correctSide: round.correctSide,

                        onTap: () => onChoose('B'),
                      ),
                    ];

                    if (constraints.maxWidth >= 760) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Expanded(child: children[0]),

                          const SizedBox(width: AppSpacing.lg),

                          Expanded(child: children[1]),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        children[0],

                        const SizedBox(height: AppSpacing.lg),

                        children[1],
                      ],
                    );
                  },
                ),

                if (answered) ...[
                  const SizedBox(height: AppSpacing.xl),

                  AppCard(
                    backgroundColor:
                        (correct ? AppColors.success : AppColors.warning)
                            .withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.14
                                  : 0.08,
                            ),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Row(
                          children: [
                            Icon(
                              correct
                                  ? Icons.check_circle_rounded
                                  : Icons.lightbulb_rounded,

                              color: correct
                                  ? AppColors.success
                                  : AppColors.warning,
                            ),

                            const SizedBox(width: AppSpacing.sm),

                            Expanded(
                              child: Text(
                                correct
                                    ? 'Nice catch.'
                                    : 'Not this time — here is the clue.',

                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.md),

                        Text(
                          round.explanation,

                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.55,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.md),

                        _SourceSummary(source: round.correctImage),

                        const SizedBox(height: AppSpacing.sm),

                        Text(
                          masteryCounted
                              ? 'This round helped update your Verify progress.'
                              : 'You can practice this again, but repeating it right away will not boost progress twice.',

                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  Align(
                    alignment: Alignment.centerRight,

                    child: FilledButton.icon(
                      onPressed: onNext,

                      icon: const Icon(Icons.arrow_forward_rounded),

                      label: Text(
                        roundNumber == totalRounds
                            ? 'See results'
                            : 'Next image',
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.section),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String side;

  final ImageComparisonSource source;

  final bool selected;
  final bool answered;

  final String correctSide;

  final VoidCallback onTap;

  const _ImageCard({
    required this.side,
    required this.source,
    required this.selected,
    required this.answered,
    required this.correctSide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final correct = correctSide == side;

    var borderColor = theme.colorScheme.outlineVariant;

    if (answered && correct) {
      borderColor = AppColors.success;
    } else if (answered && selected && !correct) {
      borderColor = AppColors.danger;
    } else if (selected) {
      borderColor = theme.colorScheme.primary;
    }

    return Semantics(
      button: true,

      label: 'Image $side',

      child: Material(
        color: theme.colorScheme.surface,

        borderRadius: BorderRadius.circular(AppRadius.lg),

        clipBehavior: Clip.antiAlias,

        child: InkWell(
          onTap: answered ? null : onTap,

          child: AnimatedContainer(
            duration: AppMotion.fast,

            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),

              border: Border.all(
                color: borderColor,

                width: selected || (answered && correct) ? 2 : 1,
              ),
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,

                  child: Image.network(
                    source.imageUrl,

                    fit: BoxFit.cover,

                    loadingBuilder: (context, child, event) {
                      if (event == null) {
                        return child;
                      }

                      final expected = event.expectedTotalBytes;

                      return ColoredBox(
                        color: theme.colorScheme.surfaceContainerLow,

                        child: Center(
                          child: CircularProgressIndicator(
                            value: expected == null
                                ? null
                                : event.cumulativeBytesLoaded / expected,
                          ),
                        ),
                      );
                    },

                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,

                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),

                          child: Column(
                            mainAxisSize: MainAxisSize.min,

                            children: [
                              const Icon(Icons.broken_image_outlined, size: 40),

                              const SizedBox(height: AppSpacing.sm),

                              const Text('This online image could not load.'),

                              const SizedBox(height: AppSpacing.xs),

                              Text(
                                'Try another set if this keeps happening.',

                                style: theme.textTheme.bodySmall,

                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),

                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Image $side',

                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                      if (!answered)
                        FilledButton.tonal(
                          onPressed: onTap,

                          child: const Text('Pick this'),
                        )
                      else
                        Icon(
                          correct
                              ? Icons.check_circle_rounded
                              : selected
                              ? Icons.cancel_rounded
                              : Icons.circle_outlined,

                          color: correct
                              ? AppColors.success
                              : selected
                              ? AppColors.danger
                              : theme.colorScheme.outline,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceSummary extends StatelessWidget {
  final ImageComparisonSource source;

  const _SourceSummary({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final details = <String>[
      'Source: Wikimedia Commons',

      if (source.creator.trim().isNotEmpty) 'Creator: ${source.creator}',

      if (source.license.trim().isNotEmpty) 'License: ${source.license}',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),

      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.75),

        borderRadius: BorderRadius.circular(AppRadius.md),

        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Text(source.title, style: theme.textTheme.titleSmall),

          const SizedBox(height: AppSpacing.xs),

          Text(details.join(' · '), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LoadingChallengeView extends StatelessWidget {
  const _LoadingChallengeView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdaptiveBody(
      child: Padding(
        padding: AdaptiveLayout.pageInsets(context, top: AppSpacing.xl),

        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),

            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,

              children: [
                Container(
                  width: 64,
                  height: 64,

                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,

                    shape: BoxShape.circle,
                  ),

                  child: Icon(
                    Icons.image_search_rounded,

                    color: theme.colorScheme.primary,

                    size: 30,
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                Text(
                  'Preparing fresh images…',

                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),

                Text(
                  'Getting one source-labeled AI image and one regular photo.',

                  textAlign: TextAlign.center,

                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                const SizedBox(width: 220, child: LinearProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompleteView extends StatelessWidget {
  final int score;
  final int total;

  final Future<void> Function() onAnotherSet;

  const _CompleteView({
    required this.score,
    required this.total,
    required this.onAnotherSet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final percent = total == 0 ? 0 : ((score / total) * 100).round();

    return AdaptiveBody(
      child: SingleChildScrollView(
        padding: AdaptiveLayout.pageInsets(context),

        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),

            child: AppCard(
              child: Column(
                children: [
                  Icon(
                    Icons.image_search_rounded,

                    size: 54,

                    color: theme.colorScheme.primary,
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  Text(
                    'Image set complete',

                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    '$score of $total correct · $percent%',

                    style: theme.textTheme.titleLarge,
                  ),

                  const SizedBox(height: AppSpacing.md),

                  const Text(
                    'The next set can use different online examples, so you can keep practicing without seeing the exact same images every time.',

                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  Wrap(
                    spacing: AppSpacing.sm,

                    runSpacing: AppSpacing.sm,

                    alignment: WrapAlignment.center,

                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),

                        child: const Text('Back to Verify'),
                      ),

                      FilledButton.icon(
                        onPressed: onAnotherSet,

                        icon: const Icon(Icons.refresh_rounded),

                        label: const Text('Try another set'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
