import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';
import 'app_card.dart';

String draftTimestampLabel(DateTime? createdAt, {required DateTime now}) {
  if (createdAt == null) return 'Generation time unavailable';
  final date = createdAt.toLocal();
  final localNow = now.toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final yesterday = DateTime(localNow.year, localNow.month, localNow.day - 1);
  final day = DateTime(date.year, date.month, date.day);
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final time =
      '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'}';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final label = day == today
      ? 'today'
      : day == yesterday
      ? 'yesterday'
      : '${months[date.month - 1]} ${date.day}, ${date.year}';
  return 'Generated $label at $time';
}

class DraftTimestamp extends StatelessWidget {
  final DateTime? createdAt;
  const DraftTimestamp({super.key, required this.createdAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: createdAt == null
          ? 'This draft has no recorded generation time.'
          : '${MaterialLocalizations.of(context).formatFullDate(createdAt!.toLocal())} '
                '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(createdAt!.toLocal()))} (your local time)',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              draftTimestampLabel(createdAt, now: DateTime.now()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Local paging of the drafts already loaded by the Studio; no generation calls.
class DraftQueue<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemId;
  final Widget Function(T) itemBuilder;
  final bool busy;
  const DraftQueue({
    super.key,
    required this.items,
    required this.itemId,
    required this.itemBuilder,
    this.busy = false,
  });

  @override
  State<DraftQueue<T>> createState() => _DraftQueueState<T>();
}

class _DraftQueueState<T> extends State<DraftQueue<T>> {
  int _page = 0;
  int _pageSize = 5;
  final _topKey = GlobalKey();
  int get _pages => (widget.items.length / _pageSize).ceil().clamp(1, 1000000);

  @override
  void didUpdateWidget(covariant DraftQueue<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.items.map(oldWidget.itemId).toSet();
    if (widget.items.isNotEmpty &&
        !oldIds.contains(widget.itemId(widget.items.first))) {
      _page =
          0; // Newly generated drafts or a different account start at the top.
    }
    _page = _page.clamp(0, _pages - 1);
  }

  void _changePage(int page) {
    setState(() => _page = page.clamp(0, _pages - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _topKey.currentContext != null) {
        Scrollable.ensureVisible(
          _topKey.currentContext!,
          alignment: 0.05,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.items.length);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final visiblePages = compact ? 1 : 3;
    final firstPage = (_page - (compact ? 0 : 1)).clamp(
      0,
      (_pages - visiblePages).clamp(0, _pages),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: _topKey,
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Showing ${start + 1}-$end of ${widget.items.length} loaded drafts',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Per page'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _pageSize,
                    items: [
                      for (final count in [5, 10, 20])
                        DropdownMenuItem(value: count, child: Text('$count')),
                    ],
                    onChanged: widget.busy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _pageSize = value;
                              _page = 0;
                            });
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final item in widget.items.sublist(start, end))
          Padding(
            key: ValueKey(widget.itemId(item)),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: widget.itemBuilder(item),
          ),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Page ${_page + 1} of $_pages',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!compact)
                    IconButton(
                      tooltip: 'First page',
                      onPressed: widget.busy || _page == 0
                          ? null
                          : () => _changePage(0),
                      icon: const Icon(Icons.first_page_rounded),
                    ),
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: widget.busy || _page == 0
                        ? null
                        : () => _changePage(_page - 1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  for (
                    var page = firstPage;
                    page < (firstPage + visiblePages).clamp(0, _pages);
                    page++
                  )
                    Semantics(
                      selected: page == _page,
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: page == _page
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            foregroundColor: page == _page
                                ? Theme.of(context).colorScheme.onPrimary
                                : null,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: widget.busy
                              ? null
                              : () => _changePage(page),
                          child: Text('${page + 1}'),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: widget.busy || _page == _pages - 1
                        ? null
                        : () => _changePage(_page + 1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  if (!compact)
                    IconButton(
                      tooltip: 'Last page',
                      onPressed: widget.busy || _page == _pages - 1
                          ? null
                          : () => _changePage(_pages - 1),
                      icon: const Icon(Icons.last_page_rounded),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
