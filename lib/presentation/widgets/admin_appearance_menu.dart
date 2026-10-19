import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/theme_controller.dart';

/// Uses the app's existing persisted preference, including device appearance.
class AdminAppearanceMenu extends StatelessWidget {
  final bool compact;
  const AdminAppearanceMenu({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final mode = controller.themeMode;
    final theme = Theme.of(context);
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      initialValue: mode,
      constraints: const BoxConstraints(minWidth: 220),
      onSelected: controller.setThemeMode,
      itemBuilder: (_) => [
        for (final option in const [
          ThemeMode.light,
          ThemeMode.dark,
          ThemeMode.system,
        ])
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(_icon(option), size: 20),
                const SizedBox(width: 12),
                Text(_label(option)),
                const Spacer(),
                if (mode == option)
                  Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
      icon: compact ? Icon(_icon(mode)) : null,
      child: compact
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    _icon(mode),
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Appearance')),
                  Text(
                    _label(mode),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_rounded, size: 18),
                ],
              ),
            ),
    );
  }

  static String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };

  static IconData _icon(ThemeMode mode) => switch (mode) {
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
    ThemeMode.system => Icons.brightness_auto_outlined,
  };
}
