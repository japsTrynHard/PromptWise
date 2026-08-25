import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/content_controller.dart';
import '../../controllers/learning_progression_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../../data/models/learning_progression.dart';
import '../../../data/models/learning_topic.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/constants.dart';
import './adaptive_knowledge_check_screen.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/live_content_banner.dart';
import '../../widgets/page_intro.dart';
import '../../widgets/section_header.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<LearningProgressionController>().ensureLoaded();
    });
  }

  Future<void> _refresh(BuildContext context) async {
    final content = context.read<ContentController>();
    final progress = context.read<ProgressController>();
    final adaptive = context.read<AdaptiveLearningController>();
    final progression = context.read<LearningProgressionController>();

    await Future.wait<void>([
      content.refresh(),
      progress.refreshFromCloud(),
      adaptive.refreshFromCloud(),
      progression.refresh(),
    ]);
    await adaptive.synchronizeExistingProgress(
      quizzes: content.quizzes,
      bestScores: progress.progress.quizBestScores,
    );
  }

  void _start(
    BuildContext context, {
    LearningTopic? focusTopic,
    int questionCount = 10,
    String mode = 'adaptive',
  }) {
    Navigator.pushNamed(
      context,
      AppRoutes.adaptiveKnowledgeCheck,
      arguments: AdaptiveKnowledgeCheckArgs(
        focusTopic: focusTopic,
        questionCount: questionCount,
        mode: mode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adaptive = context.watch<AdaptiveLearningController>();
    final progression = context.watch<LearningProgressionController>();
    final focus = adaptive.recommendedTopic ?? adaptive.weakestTopic;

    return AdaptiveBody(
      safeTop: false,
      safeBottom: false,
      child: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: AdaptiveLayout.rootTabPageInsets(context),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const PageIntro(
                    eyebrow: 'Practice',
                    title: 'Practice and improve',
                    description:
                        'Practice prompts and quick checks that get more challenging as your skills improve.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const LiveContentBanner(),
                  const SizedBox(height: AppSpacing.xxl),
                  FadeSlideIn(
                    child: _PromptCoachHero(
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.sandbox),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  _AdaptiveKnowledgeCheckHero(
                    overallRank: progression.overallRankLabel,
                    focusTopic: focus,
                    dueCount: adaptive.dueReviews.length,
                    loading: progression.isStartingSession,
                    onStart: () => _start(
                      context,
                      focusTopic: focus,
                      questionCount: 10,
                      mode: adaptive.dueReviews.isNotEmpty
                          ? 'review'
                          : 'adaptive',
                    ),
                  ),
                  if (progression.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.45),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: Text(progression.errorMessage!)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.section),
                  const SectionHeader(
                    title: 'Focused practice',
                    subtitle:
                        'Choose one skill when you want extra practice in a specific area. Questions still match your current level.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...LearningTopic.values.map(
                    (topic) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _TopicPracticeCard(
                        topic: topic,
                        mastery: adaptive.masteryFor(topic).mastery,
                        rank: progression.rankFor(topic),
                        recommended: topic == focus,
                        onTap: () => _start(
                          context,
                          focusTopic: topic,
                          questionCount: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  const _HowItAdaptsCard(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdaptiveKnowledgeCheckHero extends StatelessWidget {
  final String overallRank;
  final LearningTopic? focusTopic;
  final int dueCount;
  final bool loading;
  final VoidCallback onStart;

  const _AdaptiveKnowledgeCheckHero({
    required this.overallRank,
    required this.focusTopic,
    required this.dueCount,
    required this.loading,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.5,
          ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(
                      Icons.psychology_alt_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Knowledge Check',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Current level: $overallRank',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                focusTopic == null
                    ? 'Try a mixed set of questions across your AI skills.'
                    : 'PromptWise will focus more on ${focusTopic!.label} while still mixing in other skills.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  const Chip(label: Text('10 questions')),
                  const Chip(label: Text('5 difficulty levels')),
                  Chip(
                    label: Text(
                      dueCount == 0
                          ? 'No overdue reviews'
                          : '$dueCount review${dueCount == 1 ? '' : 's'} due',
                    ),
                  ),
                ],
              ),
            ],
          );

          final button = FilledButton.icon(
            onPressed: loading ? null : onStart,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(loading ? 'Preparing...' : 'Start quick check'),
          );

          if (constraints.maxWidth >= 680) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: content),
                const SizedBox(width: AppSpacing.xxl),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              const SizedBox(height: AppSpacing.xl),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _TopicPracticeCard extends StatelessWidget {
  final LearningTopic topic;
  final int mastery;
  final LearnerTopicRank rank;
  final bool recommended;
  final VoidCallback onTap;

  const _TopicPracticeCard({
    required this.topic,
    required this.mastery,
    required this.rank,
    required this.recommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: mastery / 100,
                  strokeWidth: 5,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                Text(
                  '$mastery%',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        topic.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (recommended)
                      const Icon(Icons.auto_awesome_rounded, size: 20),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${rank.displayLabel} · ${rank.objectiveCoverage}% objective coverage',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        ],
      ),
    );
  }
}

class _HowItAdaptsCard extends StatelessWidget {
  const _HowItAdaptsCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How the challenge changes',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          const _RuleLine(
            icon: Icons.trending_up_rounded,
            text:
                'As you improve, the questions gradually become more challenging.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _RuleLine(
            icon: Icons.track_changes_rounded,
            text:
                'Skills that need practice appear more often without taking over the whole session.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _RuleLine(
            icon: Icons.repeat_rounded,
            text:
                'PromptWise prefers questions you have not seen recently, then brings older ones back later for review.',
          ),
        ],
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RuleLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _PromptCoachHero extends StatelessWidget {
  final VoidCallback onTap;

  const _PromptCoachHero({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      backgroundColor:
          isDark ? const Color(0xFF151D3A) : const Color(0xFFF0F0FF),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final information = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.violet],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.edit_note_rounded, color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Prompt Coach',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Get feedback on your prompt, revise it in your own words, and compare how it improves over time.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
            ],
          );

          if (constraints.maxWidth >= 650) {
            return Row(
              children: [
                Expanded(child: information),
                const SizedBox(width: AppSpacing.xxl),
                FilledButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Open Coach'),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              information,
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Open Coach'),
              ),
            ],
          );
        },
      ),
    );
  }
}
