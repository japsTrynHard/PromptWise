import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/adaptive_learning_controller.dart';
import '../../controllers/content_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../models/lesson.dart';
import '../../routes/app_routes.dart';
import '../../utils/constants.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/live_content_banner.dart';
import '../widgets/module_card.dart';
import '../widgets/page_intro.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedModuleId;
  bool _onlyIncomplete = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentController>();
    final progress = context.watch<ProgressController>();
    final adaptive = context.watch<AdaptiveLearningController>();
    final recommendedTopic = adaptive.recommendedTopic;
    final modules = List.of(content.modules)
      ..sort((a, b) {
        final aRecommended = recommendedTopic != null &&
            (a.topic == recommendedTopic ||
                a.lessons.any((lesson) => lesson.topic == recommendedTopic));
        final bRecommended = recommendedTopic != null &&
            (b.topic == recommendedTopic ||
                b.lessons.any((lesson) => lesson.topic == recommendedTopic));
        if (aRecommended != bRecommended) return aRecommended ? -1 : 1;
        return a.title.compareTo(b.title);
      });
    final completedIds = progress.progress.completedLessonIds.toSet();

    final selectedModuleId =
        _selectedModuleId != null &&
            modules.any((module) => module.id == _selectedModuleId)
        ? _selectedModuleId
        : null;

    final filtered = modules
        .where((module) {
          final query = _query.trim().toLowerCase();
          final matchesQuery =
              query.isEmpty ||
              module.title.toLowerCase().contains(query) ||
              module.description.toLowerCase().contains(query) ||
              module.lessons.any(
                (lesson) =>
                    lesson.title.toLowerCase().contains(query) ||
                    lesson.content.toLowerCase().contains(query),
              );
          final matchesModule =
              selectedModuleId == null || module.id == selectedModuleId;
          final hasIncomplete = module.lessons.any(
            (lesson) => !completedIds.contains(lesson.id),
          );
          return matchesQuery &&
              matchesModule &&
              (!_onlyIncomplete || hasIncomplete);
        })
        .toList(growable: false);

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
                    title: 'Learn',
                    description:
                        'Choose a learning module, complete its lessons, and continue from your saved progress.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const LiveContentBanner(),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search modules, lessons, or lesson text',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final moduleFilter = DropdownButtonFormField<String?>(
                        initialValue: selectedModuleId,
                        decoration: const InputDecoration(
                          labelText: 'Module filter',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All modules'),
                          ),
                          ...modules.map(
                            (module) => DropdownMenuItem<String?>(
                              value: module.id,
                              child: Text(
                                module.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedModuleId = value),
                      );
                      final incompleteFilter = FilterChip(
                        avatar: const Icon(Icons.pending_actions_outlined),
                        label: const Text('Incomplete only'),
                        selected: _onlyIncomplete,
                        onSelected: (value) =>
                            setState(() => _onlyIncomplete = value),
                      );

                      if (constraints.maxWidth >= 620) {
                        return Row(
                          children: [
                            Expanded(child: moduleFilter),
                            const SizedBox(width: AppSpacing.md),
                            incompleteFilter,
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          moduleFilter,
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: incompleteFilter,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.section),
                  SectionHeader(
                    title: _hasActiveFilter
                        ? 'Filtered learning modules'
                        : 'Learning modules',
                    subtitle:
                        '${filtered.length} of ${modules.length} module${modules.length == 1 ? '' : 's'} shown.',
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
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: StateMessage.empty(
                  title: modules.isEmpty
                      ? 'No learning modules available'
                      : 'No matching modules',
                  message: modules.isEmpty
                      ? 'Learning modules are not available right now. Try refreshing in a moment.'
                      : 'Clear the search or filters to view other modules.',
                ),
              )
            else
              SliverPadding(
                padding: AdaptiveLayout.pageInsets(context, top: 0),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns = AdaptiveLayout.gridColumns(
                      width,
                      minimumTileWidth: 320,
                      maximumColumns: 3,
                    );

                    if (columns == 1) {
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding: EdgeInsets.only(
                              bottom: index == filtered.length - 1
                                  ? 0
                                  : AppSpacing.md,
                            ),
                            child: FadeSlideIn(
                              order: index,
                              child: ModuleCard(
                                module: filtered[index],
                                onTap: () =>
                                    _openModule(context, filtered[index]),
                              ),
                            ),
                          ),
                          childCount: filtered.length,
                        ),
                      );
                    }

                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppSpacing.lg,
                        mainAxisSpacing: AppSpacing.lg,
                        childAspectRatio: columns == 3 ? 1.1 : 1.25,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => FadeSlideIn(
                          order: index,
                          child: ModuleCard(
                            module: filtered[index],
                            onTap: () => _openModule(context, filtered[index]),
                          ),
                        ),
                        childCount: filtered.length,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool get _hasActiveFilter =>
      _query.trim().isNotEmpty || _selectedModuleId != null || _onlyIncomplete;

  void _openModule(BuildContext context, Module module) {
    Navigator.pushNamed(context, AppRoutes.module, arguments: module);
  }
}
