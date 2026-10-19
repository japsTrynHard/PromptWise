import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/image_comparison.dart';
import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/image_comparison_controller.dart';
import '../../controllers/image_round_readiness.dart';
import '../../controllers/learning_progression_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../controllers/verification_controller.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/promptwise_app_bar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/state_message.dart';
import '../../../core/utils/constants.dart';

class ImageCompareScreen extends StatefulWidget {
  const ImageCompareScreen({super.key});

  @override
  State<ImageCompareScreen> createState() => _ImageCompareScreenState();
}

class _ImageCompareScreenState extends State<ImageCompareScreen> {
  final ImageRoundReadiness _imageReadiness = ImageRoundReadiness();
  int _imageRetryEpoch = 0;
  bool _retryingImages = false;
  int _index = 0;

  String? _choice;

  bool _answered = false;
  bool _isSubmittingAnswer = false;
  bool _masteryCounted = false;
  ImageComparisonAttemptResult? _answerResult;

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
    final rounds = context.read<ImageComparisonController>().rounds;
    setState(() {
      _index = 0;
      _imageReadiness.reset(rounds.isEmpty ? null : rounds.first.id);
      _imageRetryEpoch++;
      _retryingImages = false;

      _choice = null;

      _answered = false;
      _isSubmittingAnswer = false;
      _masteryCounted = false;
      _answerResult = null;

      _score = 0;

      _completed = false;
    });
  }

  void _recordImageLoad(
    String roundId,
    int generation,
    String side,
    ImageLoadStatus status,
  ) {
    if (!mounted) return;
    if (_imageReadiness.record(
      roundId: roundId,
      generation: generation,
      side: side,
      status: status,
    )) {
      setState(() {});
    }
  }

  Future<void> _retryImages(ImageComparisonRound round) async {
    if (_answered ||
        _isSubmittingAnswer ||
        _retryingImages ||
        _imageReadiness.roundId != round.id) {
      return;
    }
    setState(() => _retryingImages = true);
    final generation = _imageReadiness.generation;
    // Failed ImageProviders can remain in the global cache. Evict both URLs
    // before mounting new image widgets so a retry actually fetches again.
    try {
      await Future.wait<bool>([
        NetworkImage(round.imageA.imageUrl).evict(),
        NetworkImage(round.imageB.imageUrl).evict(),
      ]);
    } catch (_) {
      if (!mounted || generation != _imageReadiness.generation) return;
      setState(() => _retryingImages = false);
      return; // Keep the original broken-image error and Another set action.
    }
    if (!mounted || generation != _imageReadiness.generation) return;
    setState(() {
      _imageReadiness.reset(round.id);
      _imageRetryEpoch++;
      _retryingImages = false;
    });
  }

  void _warmImages(List<ImageComparisonRound> rounds, int fromIndex) {
    if (!mounted || rounds.isEmpty) {
      return;
    }

    final end = (fromIndex + 2).clamp(0, rounds.length);

    for (var i = fromIndex; i < end; i++) {
      final round = rounds[i];

      // The visible Image.errorBuilder reports failures with a retry message.
      // Speculative preloading must not raise a second unhandled image error.
      unawaited(
        precacheImage(
          NetworkImage(round.imageA.imageUrl),
          context,
          onError: (error, stackTrace) {},
        ),
      );

      unawaited(
        precacheImage(
          NetworkImage(round.imageB.imageUrl),
          context,
          onError: (error, stackTrace) {},
        ),
      );
    }
  }

  Future<void> _choose(ImageComparisonRound round, String side) async {
    final controller = context.read<ImageComparisonController>();
    final rounds = controller.rounds;
    if (_answered ||
        _isSubmittingAnswer ||
        _completed ||
        _retryingImages ||
        controller.isLoading ||
        !_imageReadiness.canSubmit ||
        _imageReadiness.roundId != round.id ||
        !['A', 'B'].contains(side) ||
        _index >= rounds.length ||
        rounds[_index].id != round.id) {
      return;
    }

    setState(() {
      _choice = side;
      _isSubmittingAnswer = true;
    });

    final result = await context
        .read<ImageComparisonController>()
        .submitAttempt(
          roundId: round.id,
          selectedSide: side,
          readiness: _imageReadiness,
        );

    if (!mounted) {
      return;
    }

    if (result == null) {
      setState(() {
        _choice = null;
        _isSubmittingAnswer = false;
      });
      return;
    }

    setState(() {
      _choice = result.selectedSide;
      _answered = true;
      _isSubmittingAnswer = false;
      _answerResult = result;
      _masteryCounted = result.countedForMastery;
      if (result.isCorrect) _score += 1;
    });

    if (result.isCorrect) {
      await context.read<ProgressController>().addGameBadge();
    }
  }

  Future<void> _next(List<ImageComparisonRound> rounds) async {
    if (!_answered || _isSubmittingAnswer || _completed) return;
    if (_index < rounds.length - 1) {
      final nextIndex = _index + 1;

      setState(() {
        _index = nextIndex;
        _imageReadiness.reset(rounds[nextIndex].id);
        _imageRetryEpoch++;
        _retryingImages = false;

        _choice = null;

        _answered = false;
        _isSubmittingAnswer = false;
        _masteryCounted = false;
        _answerResult = null;
      });

      _warmImages(rounds, nextIndex);

      return;
    }

    setState(() => _completed = true);
    await Future.wait<void>([
      context.read<AdaptiveLearningController>().refreshFromCloud(),
      context.read<VerificationController>().refresh(),
      context.read<LearningProgressionController>().refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ImageComparisonController>();

    final rounds = controller.rounds;

    final theme = Theme.of(context);

    return Scaffold(
      appBar: PromptWiseAppBar(
        eyebrow: 'Verify',
        title: 'Compare Images',
        subtitle: 'Guess first, then check what the original source says.',
        backTooltip: 'Back to Verify',
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.72,
                ),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$_score / ${rounds.isEmpty ? 5 : rounds.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
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
              preparingAnotherSet: controller.isLoading,
              refreshError: controller.errorMessage,
            )
          : _RoundView(
              round: rounds[_index.clamp(0, rounds.length - 1)],
              imagesReady:
                  _imageReadiness.canSubmit &&
                  !_retryingImages &&
                  !controller.isLoading,
              imageLoadFailed: _imageReadiness.hasFailure && !_retryingImages,
              imageGeneration: _imageReadiness.generation,
              imageRetryEpoch: _imageRetryEpoch,
              onImageLoad: _recordImageLoad,
              onRetryImages: () => _retryImages(rounds[_index]),
              onAnotherSet: _loadFresh,

              roundNumber: _index + 1,

              totalRounds: rounds.length,

              choice: _choice,

              answered: _answered,

              isSubmittingAnswer: _isSubmittingAnswer,

              answerResult: _answerResult,

              masteryCounted: _masteryCounted,

              submissionError: controller.errorMessage,

              onChoose: (side) => _choose(rounds[_index], side),

              onNext: () async => _next(rounds),
            ),
    );
  }
}

class _RoundView extends StatelessWidget {
  final ImageComparisonRound round;
  final bool imagesReady;
  final bool imageLoadFailed;
  final int imageGeneration;
  final int imageRetryEpoch;
  final void Function(String, int, String, ImageLoadStatus) onImageLoad;
  final VoidCallback onRetryImages;
  final VoidCallback onAnotherSet;

  final int roundNumber;
  final int totalRounds;

  final String? choice;

  final bool answered;
  final bool isSubmittingAnswer;
  final ImageComparisonAttemptResult? answerResult;
  final bool masteryCounted;
  final String? submissionError;

  final ValueChanged<String> onChoose;

  final VoidCallback onNext;

  const _RoundView({
    required this.round,
    required this.imagesReady,
    required this.imageLoadFailed,
    required this.imageGeneration,
    required this.imageRetryEpoch,
    required this.onImageLoad,
    required this.onRetryImages,
    required this.onAnotherSet,
    required this.roundNumber,
    required this.totalRounds,
    required this.choice,
    required this.answered,
    required this.isSubmittingAnswer,
    required this.answerResult,
    required this.masteryCounted,
    required this.submissionError,
    required this.onChoose,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final correct = answerResult?.isCorrect ?? false;
    final correctSide = answerResult?.correctSide;

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
                        key: ValueKey('${round.id}:$imageRetryEpoch:A'),
                        side: 'A',
                        canChoose: imagesReady,
                        onLoadState: (status) =>
                            onImageLoad(round.id, imageGeneration, 'A', status),

                        source: round.imageA,

                        selected: choice == 'A',

                        answered: answered,

                        submitting: isSubmittingAnswer,

                        correctSide: correctSide,

                        onTap: () => onChoose('A'),
                      ),

                      _ImageCard(
                        key: ValueKey('${round.id}:$imageRetryEpoch:B'),
                        side: 'B',
                        canChoose: imagesReady,
                        onLoadState: (status) =>
                            onImageLoad(round.id, imageGeneration, 'B', status),

                        source: round.imageB,

                        selected: choice == 'B',

                        answered: answered,

                        submitting: isSubmittingAnswer,

                        correctSide: correctSide,

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

                if (!answered && imageLoadFailed) ...[
                  const SizedBox(height: AppSpacing.lg),
                  StateMessage.error(
                    title: 'An image could not load',
                    message:
                        'Both images must be visible before you can answer. No answer has been recorded.',
                    actionLabel: 'Retry images',
                    onAction: onRetryImages,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onAnotherSet,
                      child: const Text('Try another set'),
                    ),
                  ),
                ],

                if (isSubmittingAnswer) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Semantics(
                    liveRegion: true,
                    label: 'Checking the selected image with the source',
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text('Checking the source...'),
                      ],
                    ),
                  ),
                ] else if (!answered && submissionError != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    submissionError!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],

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
                          answerResult!.explanation,

                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.55,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.md),

                        _SourceSummary(source: answerResult!.correctSource),

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
  final bool canChoose;
  final ValueChanged<ImageLoadStatus> onLoadState;
  final String side;

  final ImageComparisonSource source;

  final bool selected;
  final bool answered;
  final bool submitting;

  final String? correctSide;

  final VoidCallback onTap;

  const _ImageCard({
    super.key,
    required this.canChoose,
    required this.onLoadState,
    required this.side,
    required this.source,
    required this.selected,
    required this.answered,
    required this.submitting,
    required this.correctSide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Image.frameBuilder runs before loadingBuilder. Do not declare this image
    // ready until a decoded frame exists AND the loading overlay is gone.
    var decodedFrame = false;

    final correct = answered && correctSide == side;

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
          onTap: answered || submitting || !canChoose ? null : onTap,

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

                    // A non-null frame proves an image was actually decoded,
                    // unlike a completed network request with broken bytes.
                    frameBuilder: (context, child, frame, wasSyncLoaded) {
                      decodedFrame = frame != null;
                      return child;
                    },

                    loadingBuilder: (context, child, event) {
                      if (event == null) {
                        if (decodedFrame) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            onLoadState(ImageLoadStatus.ready);
                          });
                        }
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

                    errorBuilder: (context, error, stackTrace) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        onLoadState(ImageLoadStatus.failed);
                      });
                      return ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.broken_image_outlined,
                                  size: 40,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                const Text('This online image could not load.'),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Retry images or try another set.',
                                  style: theme.textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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
                          onPressed: submitting || !canChoose ? null : onTap,

                          child: submitting && selected
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Pick this'),
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
  final ImageComparisonSourceFeedback source;

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
  final bool preparingAnotherSet;
  final String? refreshError;

  const _CompleteView({
    required this.score,
    required this.total,
    required this.onAnotherSet,
    required this.preparingAnotherSet,
    required this.refreshError,
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

                  if (preparingAnotherSet) ...[
                    Semantics(
                      liveRegion: true,
                      label: 'Preparing another image set',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Text('Preparing another set...'),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ] else if (refreshError != null) ...[
                    Text(
                      refreshError!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  Wrap(
                    spacing: AppSpacing.sm,

                    runSpacing: AppSpacing.sm,

                    alignment: WrapAlignment.center,

                    children: [
                      OutlinedButton(
                        onPressed: preparingAnotherSet
                            ? null
                            : () => Navigator.pop(context),

                        child: const Text('Back to Verify'),
                      ),

                      FilledButton.icon(
                        onPressed: preparingAnotherSet ? null : onAnotherSet,

                        icon: preparingAnotherSet
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),

                        label: Text(
                          preparingAnotherSet
                              ? 'Preparing another set...'
                              : 'Try another set',
                        ),
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
