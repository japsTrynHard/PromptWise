import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';
import 'app_card.dart';

class StudioFocusOption<T> {
  final T value;
  final String label;
  final String description;
  final IconData icon;

  const StudioFocusOption(this.value, this.label, this.description, this.icon);
}

/// The same one-run selection flow for both administrator studios.
class StudioFocusDialog<T> extends StatefulWidget {
  final String title;
  final String description;
  final List<StudioFocusOption<T>> options;
  final List<T> initial;

  const StudioFocusDialog({
    super.key,
    required this.title,
    required this.description,
    required this.options,
    this.initial = const [],
  });

  @override
  State<StudioFocusDialog<T>> createState() => _StudioFocusDialogState<T>();
}

class _StudioFocusDialogState<T> extends State<StudioFocusDialog<T>> {
  late final Set<T> selected = Set<T>.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 680),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      title: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${selected.length} selected',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (selected.length == widget.options.length) {
                        selected.clear();
                      } else {
                        selected.addAll(
                          widget.options.map((option) => option.value),
                        );
                      }
                    }),
                    child: Text(
                      selected.length == widget.options.length
                          ? 'Clear selection'
                          : 'Select all',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 500 ? 2 : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final option in widget.options)
                        SizedBox(
                          width: width,
                          child: Semantics(
                            checked: selected.contains(option.value),
                            child: Material(
                              color: selected.contains(option.value)
                                  ? colors.primaryContainer.withValues(
                                      alpha: 0.4,
                                    )
                                  : colors.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                side: BorderSide(
                                  color: selected.contains(option.value)
                                      ? colors.primary
                                      : colors.outlineVariant,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => setState(() {
                                  if (!selected.add(option.value)) {
                                    selected.remove(option.value);
                                  }
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            option.icon,
                                            color: colors.primary,
                                            size: 22,
                                          ),
                                          const Spacer(),
                                          Icon(
                                            selected.contains(option.value)
                                                ? Icons.check_circle_rounded
                                                : Icons
                                                      .check_box_outline_blank_rounded,
                                            color:
                                                selected.contains(option.value)
                                                ? colors.primary
                                                : colors.outline,
                                            size: 22,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      Text(
                                        option.label,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        option.description,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                              height: 1.4,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Drafts require your review before publication.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: selected.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.options
                      .map((option) => option.value)
                      .where(selected.contains)
                      .toList(growable: false),
                ),
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: const Text('Generate drafts'),
        ),
      ],
    );
  }
}

class StudioNotice extends StatelessWidget {
  final String title;
  final String message;
  final bool isError;
  final bool isWarning;
  final VoidCallback? onDismiss;

  const StudioNotice({
    super.key,
    required this.title,
    required this.message,
    this.isError = false,
    this.isWarning = false,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      backgroundColor: isError
          ? colors.errorContainer.withValues(alpha: 0.3)
          : colors.primaryContainer.withValues(alpha: 0.25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            (isError || isWarning)
                ? Icons.info_outline_rounded
                : Icons.check_circle_outline,
            color: isError ? colors.error : colors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: 'Dismiss message',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

class StudioMetricRow extends StatelessWidget {
  final List<Widget> children;
  const StudioMetricRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600
          ? 3
          : constraints.maxWidth >= 400
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class StudioMetric extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const StudioMetric({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 172,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 20),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
