import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/content_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../routes/app_routes.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/live_content_banner.dart';
import '../widgets/page_intro.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentController>();
    final progress = context.watch<ProgressController>();
    final quizzes = content.quizzes;

    return AdaptiveBody(
      child: RefreshIndicator(
        onRefresh: content.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: AdaptiveLayout.pageInsets(context),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const PageIntro(
                    title: 'Practice',
                    description:
                        'Use the Prompt Coach and knowledge checks to strengthen your own reasoning.',
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
                  SectionHeader(
                    title: 'Knowledge checks',
                    subtitle:
                        '${quizzes.length} knowledge check${quizzes.length == 1 ? '' : 's'} available. Your best results are saved to your account.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ]),
              ),
            ),
            if (content.isLoading && !content.hasLoaded)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (quizzes.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: StateMessage.empty(
                  title: 'No knowledge checks available',
                  message:
                      'New knowledge checks will appear here when available.',
                ),
              )
            else
              SliverPadding(
                padding: AdaptiveLayout.pageInsets(context, top: 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final quiz = quizzes[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == quizzes.length - 1 ? 0 : AppSpacing.md,
                      ),
                      child: FadeSlideIn(
                        order: index + 1,
                        child: _QuizPracticeCard(
                          index: index + 1,
                          title: quiz.displayTitle,
                          description: quiz.description.isEmpty
                              ? 'Answer the question and review the explanation.'
                              : quiz.description,
                          bestScore: progress.bestScoreForQuiz(quiz.id),
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.quiz,
                            arguments: quiz,
                          ),
                        ),
                      ),
                    );
                  }, childCount: quizzes.length),
                ),
              ),
          ],
        ),
      ),
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
      backgroundColor: isDark
          ? const Color(0xFF151D3A)
          : const Color(0xFFF0F0FF),
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
              Text(
                'Prompt Coach',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Write a prompt, receive guided feedback, and revise it using your own words.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  Chip(label: Text('No automatic rewriting')),
                  Chip(label: Text('Privacy reminders')),
                  Chip(label: Text('Revision guidance')),
                ],
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

class _QuizPracticeCard extends StatelessWidget {
  final int index;
  final String title;
  final String description;
  final int bestScore;
  final VoidCallback onTap;

  const _QuizPracticeCard({
    required this.index,
    required this.title,
    required this.description,
    required this.bestScore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              '$index',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  bestScore > 0 ? 'Best score: $bestScore%' : 'Not attempted',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: bestScore == 100
                        ? AppColors.success
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
