import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/constants.dart';
import '../../../core/utils/external_link.dart';
import '../../../data/models/awareness_article.dart';
import '../../../data/models/awareness_filter.dart';
import '../../controllers/awareness_feed_controller.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/app_card.dart';
import '../../widgets/state_message.dart';
import '../../widgets/promptwise_app_bar.dart';

class NewsScreen extends StatelessWidget {
  final AwarenessFilter? filter;

  const NewsScreen({super.key, this.filter});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AwarenessFeedController>();
    final items = _applyLegacyFilter(controller.articles, filter);
    final featured = items.isEmpty ? null : items.first;
    final remaining = items.length <= 1
        ? const <AwarenessArticle>[]
        : items.skip(1).toList(growable: false);

    return Scaffold(
      appBar: PromptWiseAppBar(
        eyebrow: 'DISCOVER · AI AWARENESS',
        title: 'AI Awareness',
        subtitle:
            'Current AI, deepfake, synthetic-media, and AI misinformation updates.',
        backTooltip: 'Back to Home',
        actions: [
          PromptWiseHeaderIconButton(
            tooltip: controller.isRefreshing
                ? 'Checking for updates'
                : 'Check for updates',
            icon: Icons.refresh_rounded,
            loading: controller.isRefreshing,
            onPressed: controller.isLoading || controller.isRefreshing
                ? null
                : () => _checkForUpdates(context, controller),
          ),
        ],
      ),
      body: AdaptiveBody(
        child: RefreshIndicator(
          onRefresh: () =>
              _checkForUpdates(context, controller, showMessage: false),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: AdaptiveLayout.pageInsets(context, top: AppSpacing.md),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _Header(controller: controller),
                    const SizedBox(height: AppSpacing.lg),
                    _ScopePicker(controller: controller),
                    const SizedBox(height: AppSpacing.md),
                    _CategoryPicker(controller: controller),
                    if (controller.backgroundUpdateMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      MaterialBanner(
                        content: Text(controller.backgroundUpdateMessage!),
                        leading: const Icon(Icons.new_releases_outlined),
                        actions: [
                          TextButton(
                            onPressed: controller.clearBackgroundUpdateMessage,
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ],
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      StateMessage.error(
                        title: 'Live updates are temporarily unavailable',
                        message: controller.errorMessage!,
                        actionLabel: 'Try again',
                        onAction: () => _checkForUpdates(context, controller),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                  ]),
                ),
              ),
              if (controller.isLoading && !controller.hasLoaded)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (items.isEmpty)
                SliverPadding(
                  padding: AdaptiveLayout.pageInsets(context, top: 0),
                  sliver: SliverToBoxAdapter(
                    child: StateMessage.empty(
                      title: 'No matching updates yet',
                      message:
                          'PromptWise checks current trusted sources for AI, deepfake, synthetic-media, AI scam, and AI misinformation updates. Generic fake-news or scam stories are excluded. Try another filter or refresh later.',
                      actionLabel: 'Show all',
                      onAction: () async {
                        await controller.setCategory(null);
                        await controller.setScope(AwarenessScope.forYou);
                      },
                    ),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: AdaptiveLayout.pageInsets(context, top: 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SectionTitle(
                          title: 'Worth knowing now',
                          subtitle:
                              'A current update selected for relevance, freshness, and source quality.',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (featured != null)
                          _FeaturedArticleCard(
                            article: featured,
                            onOpen: () =>
                                _openArticle(context, controller, featured),
                            onSave: () => controller.toggleSaved(featured),
                          ),
                        const SizedBox(height: AppSpacing.section),
                        _SectionTitle(
                          title: 'Latest updates',
                          subtitle: remaining.isEmpty
                              ? 'More relevant stories will appear as trusted sources publish them.'
                              : '${remaining.length} more current update${remaining.length == 1 ? '' : 's'} in this feed.',
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: AdaptiveLayout.pageInsets(context, top: 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final article = remaining[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == remaining.length - 1
                              ? AppSpacing.section
                              : AppSpacing.md,
                        ),
                        child: _ArticleCard(
                          article: article,
                          onOpen: () =>
                              _openArticle(context, controller, article),
                          onSave: () => controller.toggleSaved(article),
                        ),
                      );
                    }, childCount: remaining.length),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _checkForUpdates(
  BuildContext context,
  AwarenessFeedController controller, {
  bool showMessage = true,
}) async {
  final message = await controller.checkForUpdates();

  if (!context.mounted || !showMessage) {
    return;
  }

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _openArticle(
  BuildContext context,
  AwarenessFeedController controller,
  AwarenessArticle article,
) async {
  await controller.markRead(article);
  final opened = await openExternalLink(article.sourceUrl);
  if (!context.mounted || opened) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'The article link was copied. Open it in your browser to read the original source.',
      ),
    ),
  );
}

List<AwarenessArticle> _applyLegacyFilter(
  List<AwarenessArticle> source,
  AwarenessFilter? filter,
) {
  final keywords =
      filter?.keywords
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toList(growable: false) ??
      const <String>[];
  if (keywords.isEmpty) {
    return source;
  }
  return source
      .where((article) {
        final searchable =
            '${article.title} ${article.summary} ${article.whyItMatters} ${article.category.label}'
                .toLowerCase();
        return keywords.any(searchable.contains);
      })
      .toList(growable: false);
}

class _Header extends StatelessWidget {
  final AwarenessFeedController controller;

  const _Header({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What you should know about AI right now',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Current AI, deepfake, synthetic-media, AI scam, AI misinformation, privacy, and safety updates from trusted Philippine and major sources.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.public_rounded,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  _updatedLabel(controller.lastUpdatedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        );

        if (constraints.maxWidth < 760) {
          return copy;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: controller.isLoading || controller.isRefreshing
                  ? null
                  : () => _checkForUpdates(context, controller),
              icon: controller.isRefreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                controller.isRefreshing ? 'Checking...' : 'Check for updates',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScopePicker extends StatelessWidget {
  final AwarenessFeedController controller;

  const _ScopePicker({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: AwarenessScope.values
            .map(
              (scope) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(
                  label: Text(scope.label),
                  selected: controller.scope == scope,
                  onSelected: (_) => controller.setScope(scope),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  final AwarenessFeedController controller;

  const _CategoryPicker({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              label: const Text('All topics'),
              selected: controller.category == null,
              onSelected: (_) => controller.setCategory(null),
            ),
          ),
          ...AwarenessCategory.values.map(
            (category) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilterChip(
                label: Text(category.label),
                selected: controller.category == category,
                onSelected: (_) => controller.setCategory(category),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedArticleCard extends StatelessWidget {
  final AwarenessArticle article;
  final VoidCallback onOpen;
  final VoidCallback onSave;

  const _FeaturedArticleCard({
    required this.article,
    required this.onOpen,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          final image = _ArticleImage(
            imageUrl: article.imageUrl,
            category: article.category,
            height: wide ? 330 : 250,
          );
          final copy = Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ArticleMeta(article: article),
                const SizedBox(height: AppSpacing.md),
                Text(
                  article.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                if (article.summary.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    article.summary,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                  ),
                ],
                if (article.whyItMatters.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _WhyItMatters(text: article.whyItMatters),
                ],
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Read original'),
                    ),
                    IconButton.outlined(
                      tooltip: article.saved
                          ? 'Remove saved article'
                          : 'Save article',
                      onPressed: onSave,
                      icon: Icon(
                        article.saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [image, copy],
            );
          }
          // This card is inside a sliver with unbounded vertical constraints.
          // Stretching the Row on web can request infinite height and prevent the
          // entire Awareness body from rendering, leaving only the AppBar visible.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 11, child: image),
              Expanded(flex: 10, child: copy),
            ],
          );
        },
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final AwarenessArticle article;
  final VoidCallback onOpen;
  final VoidCallback onSave;

  const _ArticleCard({
    required this.article,
    required this.onOpen,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onOpen,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final image = SizedBox(
            width: compact ? double.infinity : 230,
            child: _ArticleImage(
              imageUrl: article.imageUrl,
              category: article.category,
              height: compact ? 190 : 180,
              radius: AppRadius.md,
            ),
          );
          final copy = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ArticleMeta(article: article),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  article.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (article.summary.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    article.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Read original'),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: article.saved
                          ? 'Remove saved article'
                          : 'Save article',
                      onPressed: onSave,
                      icon: Icon(
                        article.saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                image,
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [copy],
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              image,
              const SizedBox(width: AppSpacing.xl),
              copy,
            ],
          );
        },
      ),
    );
  }
}

class _ArticleMeta extends StatelessWidget {
  final AwarenessArticle article;

  const _ArticleMeta({required this.article});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          article.sourceName,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text('·', style: theme.textTheme.bodySmall),
        Text(
          _relativeTime(article.publishedAt ?? article.discoveredAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        _MetaPill(label: article.isPhilippines ? 'Philippines' : 'Global'),
        _MetaPill(label: article.category.label),
        if (article.read) const _MetaPill(label: 'Read'),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;

  const _MetaPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

class _WhyItMatters extends StatelessWidget {
  final String text;

  const _WhyItMatters({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Why this matters: $text',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticleImage extends StatelessWidget {
  final String? imageUrl;
  final AwarenessCategory category;
  final double height;
  final double radius;

  const _ArticleImage({
    required this.imageUrl,
    required this.category,
    required this.height,
    this.radius = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Icon(
          _categoryIcon(category),
          size: 48,
          color: theme.colorScheme.primary,
        ),
      ),
    );
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return Container(
            height: height,
            color: theme.colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _updatedLabel(DateTime? value) {
  if (value == null) {
    return 'Checks for fresh updates when you open this page';
  }
  return 'Updated ${_relativeTime(value)}';
}

String _relativeTime(DateTime? value) {
  if (value == null) {
    return 'Recently';
  }
  final difference = DateTime.now().difference(value);
  if (difference.isNegative) {
    return 'Just now';
  }
  if (difference.inMinutes < 1) {
    return 'Just now';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes} min ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d ago';
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

IconData _categoryIcon(AwarenessCategory category) {
  return switch (category) {
    AwarenessCategory.scams => Icons.gpp_maybe_outlined,
    AwarenessCategory.deepfakes => Icons.face_retouching_natural_outlined,
    AwarenessCategory.fakeNews => Icons.newspaper_rounded,
    AwarenessCategory.privacy => Icons.privacy_tip_outlined,
    AwarenessCategory.onlineSafety => Icons.shield_outlined,
    AwarenessCategory.aiMisuse => Icons.smart_toy_outlined,
    AwarenessCategory.factChecking => Icons.fact_check_outlined,
    AwarenessCategory.cybersecurity => Icons.security_outlined,
  };
}
