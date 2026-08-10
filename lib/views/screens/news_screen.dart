import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/content_controller.dart';
import '../../models/awareness_filter.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_card.dart';
import '../widgets/live_content_banner.dart';
import '../widgets/page_intro.dart';
import '../widgets/state_message.dart';

class NewsScreen extends StatelessWidget {
  final AwarenessFilter? filter;

  const NewsScreen({super.key, this.filter});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentController>();
    final allItems = content.awarenessItems;
    final keywords =
        filter?.keywords
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final items = keywords.isEmpty
        ? allItems
        : allItems
              .where((item) {
                final searchable = '${item.title} ${item.summary}'
                    .toLowerCase();
                return keywords.any(searchable.contains);
              })
              .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(filter?.title ?? 'AI Awareness')),
      body: AdaptiveBody(
        child: RefreshIndicator(
          onRefresh: content.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: AdaptiveLayout.pageInsets(context, top: AppSpacing.sm),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    PageIntro(
                      title: filter?.title ?? 'Current AI awareness',
                      description: filter == null
                          ? 'Read the context, identify the risk, and apply the verification guidance before sharing information.'
                          : 'These awareness items match the selected verification path.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const LiveContentBanner(compact: true),
                    const SizedBox(height: AppSpacing.xxl),
                  ]),
                ),
              ),
              if (content.isLoading && !content.hasLoaded)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: StateMessage.empty(
                    title: allItems.isEmpty
                        ? 'No awareness updates available'
                        : 'No matching guidance',
                    message: allItems.isEmpty
                        ? 'New awareness guidance will appear here when available.'
                        : 'No awareness guidance currently matches this verification path.',
                  ),
                )
              else
                SliverPadding(
                  padding: AdaptiveLayout.pageInsets(context, top: 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = items[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == items.length - 1 ? 0 : AppSpacing.md,
                        ),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.md,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.campaign_outlined,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.lg),
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                item.summary,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(height: 1.55),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Chip(
                                    avatar: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16,
                                    ),
                                    label: Text(item.date),
                                  ),
                                  if (item.reviewDate != null)
                                    Chip(
                                      avatar: const Icon(
                                        Icons.image_search_outlined,
                                        size: 16,
                                      ),
                                      label: Text(
                                        'Review ${_formatReviewDate(item.reviewDate!)}',
                                      ),
                                    ),
                                  if (item.sourceUrl != null)
                                    Chip(
                                      avatar: const Icon(
                                        Icons.link_rounded,
                                        size: 16,
                                      ),
                                      label: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 360,
                                        ),
                                        child: Text(
                                          item.sourceUrl!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  const Chip(label: Text('Reviewed guidance')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }, childCount: items.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatReviewDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
