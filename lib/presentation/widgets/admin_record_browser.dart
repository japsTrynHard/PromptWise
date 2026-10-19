import 'package:flutter/material.dart';

/// Flexy-inspired table controls shared by the admin directories.
class AdminRecordBrowser<T> extends StatefulWidget {
  final List<T> items;
  final String noun;
  final Widget Function(List<T>) builder;
  const AdminRecordBrowser({
    super.key,
    required this.items,
    required this.noun,
    required this.builder,
  });
  @override
  State<AdminRecordBrowser<T>> createState() => _AdminRecordBrowserState<T>();
}

class _AdminRecordBrowserState<T> extends State<AdminRecordBrowser<T>> {
  int _page = 0;
  int _size = 10;
  final _header = GlobalKey();

  void _go(int page) {
    setState(() => _page = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _header.currentContext == null) return;
      Scrollable.ensureVisible(
        _header.currentContext!,
        duration: const Duration(milliseconds: 200),
        alignment: 0.05,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    final pages = (count / _size).ceil().clamp(1, 1000000);
    _page = _page.clamp(0, pages - 1);
    final start = _page * _size;
    final end = (start + _size).clamp(0, count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          key: _header,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          children: [
            Text(
              count == 0
                  ? '0 ${widget.noun}'
                  : 'Showing ${start + 1}–$end of $count ${widget.noun}',
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Per page '),
                DropdownButton<int>(
                  value: _size,
                  items: [10, 25, 50]
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (value) => setState(() {
                    _size = value!;
                    _page = 0;
                  }),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        widget.builder(widget.items.sublist(start, end)),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Page ${_page + 1} of $pages'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'First page',
                  onPressed: _page > 0 ? () => _go(0) : null,
                  icon: const Icon(Icons.first_page),
                ),
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: _page > 0 ? () => _go(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${_page + 1}'),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: _page < pages - 1 ? () => _go(_page + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: 'Last page',
                  onPressed: _page < pages - 1 ? () => _go(pages - 1) : null,
                  icon: const Icon(Icons.last_page),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
