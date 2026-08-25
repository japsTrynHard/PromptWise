import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import '../../../data/models/learning_progression.dart';
import '../../../data/models/verification.dart';
import '../../controllers/content_controller.dart';
import '../../controllers/learning_progression_controller.dart';
import '../../controllers/verification_controller.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_intro.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_message.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future.wait<void>([
        context.read<VerificationController>().ensureLoaded(),
        context.read<LearningProgressionController>().ensureLoaded(),
      ]);
    });
  }

  Future<void> _startQuickCheck(BuildContext context) async {
    final verification = context.read<VerificationController>();
    final progression = context.read<LearningProgressionController>();

    final started = await verification.startSession(
      caseCount: 5,
      rankLevel: progression.overallRank.level,
    );
    if (!context.mounted) return;

    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            verification.errorMessage ?? 'The quick check could not start.',
          ),
        ),
      );
      return;
    }

    await Navigator.pushNamed(context, AppRoutes.verificationSession);
    if (context.mounted) await verification.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentController>();
    final verification = context.watch<VerificationController>();
    final awareness = content.awarenessItems;

    final attempts = VerificationSubskill.values.fold<int>(
      0,
      (sum, item) => sum + verification.masteryFor(item).attempts,
    );
    final average = VerificationSubskill.values.fold<int>(
          0,
          (sum, item) => sum + verification.masteryFor(item).mastery,
        ) ~/
        VerificationSubskill.values.length;
    final weakest = verification.weakestSubskill;

    return AdaptiveBody(
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([content.refresh(), verification.refresh()]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: AdaptiveLayout.pageInsets(context),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const PageIntro(
                    eyebrow: 'Verify',
                    title: 'Check before you trust it',
                    description:
                        'Practice with images and short real-world examples. Make a quick choice, then see the reason behind the answer.',
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _ImageCompareFeature(
                    onOpen: () => Navigator.pushNamed(context, AppRoutes.imageCompare),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _QuickCheckFeature(
                    isStarting: verification.isStarting,
                    onStart: () => _startQuickCheck(context),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  const SectionHeader(
                    title: 'Your Verify progress',
                    subtitle:
                        'PromptWise quietly keeps track of the skills you practice so the next activities can fit you better.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _FriendlyProgressCard(
                    attempts: attempts,
                    average: average,
                    focus: weakest,
                  ),
                  const SizedBox(height: AppSpacing.section),
                  const SectionHeader(
                    title: 'Skills you are building',
                    subtitle: 'Simple habits that help you avoid misleading content.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SkillChips(controller: verification),
                  const SizedBox(height: AppSpacing.section),
                  SectionHeader(
                    title: 'Quick tips',
                    subtitle: awareness.isEmpty
                        ? 'Helpful verification tips will appear here.'
                        : 'Short guides you can read anytime.',
                    actionLabel: awareness.isEmpty ? null : 'See all',
                    onAction: awareness.isEmpty
                        ? null
                        : () => Navigator.pushNamed(context, AppRoutes.awareness),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (awareness.isEmpty)
                    const StateMessage.empty(
                      title: 'No tips available yet',
                      message: 'Published verification guides will appear here.',
                    )
                  else
                    ...awareness.take(3).map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: AppCard(
                              onTap: () => Navigator.pushNamed(
                                context,
                                AppRoutes.awareness,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lightbulb_outline_rounded),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(child: Text(item.title)),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(height: AppSpacing.section),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCompareFeature extends StatelessWidget {
  final VoidCallback onOpen;

  const _ImageCompareFeature({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onOpen,
      backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleRow = Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.image_search_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Compare Images',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );

          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (constraints.maxWidth < 430) ...[
                titleRow,
                const SizedBox(height: AppSpacing.sm),
                const Chip(label: Text('Fresh online images')),
              ] else
                Row(
                  children: [
                    Expanded(child: titleRow),
                    const SizedBox(width: AppSpacing.sm),
                    const Chip(label: Text('Fresh online images')),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Pick which image was marked as AI-made. The examples are pulled from online source information, so the set can change instead of repeating the same pictures every time.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              const Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  Chip(label: Text('5 quick rounds')),
                  Chip(label: Text('Image-first')),
                  Chip(label: Text('Source shown after answer')),
                ],
              ),
            ],
          );

          final button = FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start image challenge'),
          );

          if (constraints.maxWidth >= 760) {
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: AppSpacing.xl),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: AppSpacing.lg),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _QuickCheckFeature extends StatelessWidget {
  final bool isStarting;
  final VoidCallback onStart;

  const _QuickCheckFeature({
    required this.isStarting,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Check',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Five short situations about claims, sources, edited media, and references. New users start with easier examples.',
              ),
            ],
          );
          final button = OutlinedButton.icon(
            onPressed: isStarting ? null : onStart,
            icon: isStarting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: const Text('Start quick check'),
          );
          if (constraints.maxWidth >= 720) {
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: AppSpacing.xl),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: AppSpacing.lg),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _FriendlyProgressCard extends StatelessWidget {
  final int attempts;
  final int average;
  final VerificationSubskill focus;

  const _FriendlyProgressCard({
    required this.attempts,
    required this.average,
    required this.focus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Text(
            attempts == 0
                ? 'You are just getting started'
                : '$average% overall progress',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          );
          final attemptsText = Text(
            '$attempts practice ${attempts == 1 ? 'answer' : 'answers'}',
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (constraints.maxWidth < 430) ...[
                title,
                const SizedBox(height: AppSpacing.xs),
                attemptsText,
              ] else
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: AppSpacing.sm),
                    attemptsText,
                  ],
                ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(value: attempts == 0 ? 0 : average / 100),
          const SizedBox(height: AppSpacing.md),
              Text(
                attempts == 0
                    ? 'Try Compare Images or Quick Check. Your progress will appear here as you practice.'
                    : 'A useful next focus is “${focus.learnerLabel}”. PromptWise will bring that kind of practice back more often.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SkillChips extends StatelessWidget {
  final VerificationController controller;

  const _SkillChips({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: VerificationSubskill.values.map((skill) {
        final progress = controller.masteryFor(skill);
        return Tooltip(
          message: skill.learnerDescription,
          child: Chip(
            avatar: Icon(
              progress.attempts == 0 ? Icons.circle_outlined : Icons.check_circle_outline_rounded,
              size: 18,
            ),
            label: Text(
              progress.attempts == 0
                  ? skill.learnerLabel
                  : '${skill.learnerLabel} · ${progress.mastery}%',
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}
