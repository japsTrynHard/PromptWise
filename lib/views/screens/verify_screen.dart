import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/content_controller.dart';
import '../../routes/app_routes.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/live_content_banner.dart';
import '../widgets/page_intro.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';

class VerifyScreen extends StatelessWidget {
  const VerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentController>();
    final awareness = content.awarenessItems;
    final activities = content.activities;

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
                    title: 'Verify',
                    description:
                        'Practice recognizing AI-generated or manipulated media and review safe, responsible AI-use guidance.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const LiveContentBanner(),
                  const SizedBox(height: AppSpacing.xxl),
                  FadeSlideIn(
                    child: _VerificationHero(
                      activityCount: activities.length,
                      onTap: activities.isEmpty
                          ? null
                          : () => Navigator.pushNamed(context, AppRoutes.game),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  const SectionHeader(
                    title: 'Choose what to review',
                    subtitle:
                        'Keep verification focused on AI-generated media and responsible AI use.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cards = [
                        _VerificationPath(
                          icon: Icons.perm_media_outlined,
                          title: 'Real or AI practice',
                          description:
                              'Compare images, look for useful clues, and explain why one clue alone is not perfect proof.',
                          onTap: activities.isEmpty
                              ? null
                              : () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.game,
                                ),
                        ),
                        _VerificationPath(
                          icon: Icons.health_and_safety_outlined,
                          title: 'AI safety guidance',
                          description:
                              'Review guidance about deepfakes, impersonation, privacy, misleading AI content, and responsible use.',
                          onTap: awareness.isEmpty
                              ? null
                              : () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.awareness,
                                ),
                        ),
                      ];

                      if (constraints.maxWidth >= 760) {
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: FadeSlideIn(order: 1, child: cards[0]),
                              ),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(
                                child: FadeSlideIn(order: 2, child: cards[1]),
                              ),
                            ],
                          ),
                        );
                      }
                      return Column(
                        children: [
                          FadeSlideIn(order: 1, child: cards[0]),
                          const SizedBox(height: AppSpacing.md),
                          FadeSlideIn(order: 2, child: cards[1]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.section),
                  SectionHeader(
                    title: 'Real or AI activities',
                    subtitle: activities.isEmpty
                        ? 'No comparison rounds are available right now.'
                        : '${activities.length} round${activities.length == 1 ? '' : 's'} available.',
                    actionLabel: activities.isEmpty ? null : 'Start',
                    onAction: activities.isEmpty
                        ? null
                        : () => Navigator.pushNamed(context, AppRoutes.game),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (content.isLoading && !content.hasLoaded)
                    const Center(child: CircularProgressIndicator())
                  else if (activities.isEmpty)
                    const StateMessage.empty(
                      title: 'No activity available',
                      message:
                          'New Real or AI activities will appear here when available.',
                    )
                  else
                    ...activities.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: AppCard(
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.game),
                          child: Row(
                            children: [
                              CircleAvatar(child: Text('${entry.key + 1}')),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.value.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      'Compare two images and review the explanation.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.section),
                  SectionHeader(
                    title: 'AI safety guidance',
                    subtitle:
                        '${awareness.length} guidance item${awareness.length == 1 ? '' : 's'} available.',
                    actionLabel: awareness.isEmpty ? null : 'View all',
                    onAction: awareness.isEmpty
                        ? null
                        : () =>
                              Navigator.pushNamed(context, AppRoutes.awareness),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (awareness.isEmpty)
                    const StateMessage.empty(
                      title: 'No guidance available',
                      message:
                          'New AI safety guidance will appear here when available.',
                    )
                  else
                    ...awareness
                        .take(3)
                        .toList()
                        .asMap()
                        .entries
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: FadeSlideIn(
                              order: entry.key + 3,
                              child: AppCard(
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.awareness,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.article_outlined,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: AppSpacing.lg),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.value.title,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            entry.value.date,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                              ),
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
}

class _VerificationHero extends StatelessWidget {
  final int activityCount;
  final VoidCallback? onTap;

  const _VerificationHero({required this.activityCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      backgroundColor: AppColors.teal.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.09,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.teal,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(
                  Icons.image_search_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Real or AI activity',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                activityCount == 0
                    ? 'No comparison round is available yet.'
                    : 'Practice with $activityCount comparison round${activityCount == 1 ? '' : 's'} and explain the clues you notice before seeing the answer.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          );

          final button = FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start Activity'),
          );

          if (constraints.maxWidth >= 650) {
            return Row(
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

class _VerificationPath extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  const _VerificationPath({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text(
                onTap == null ? 'Unavailable' : 'Open',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: onTap == null
                      ? Theme.of(context).disabledColor
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: onTap == null
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
