import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../data/shortcut_link.dart';
import '../util/url_opener.dart';

class ShortcutsCard extends StatelessWidget {
  const ShortcutsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DashboardCard(
      title: '바로가기',
      icon: Icons.link,
      accentColor: theme.extension<AppAccentColors>()?.shortcuts,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < shortcutLinks.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _ShortcutRow(link: shortcutLinks[i]),
          ],
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.link});

  final ShortcutLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openUrl(link.url),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(link.icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(child: Text(link.label, style: theme.textTheme.bodyMedium)),
              Icon(Icons.open_in_new, size: 16, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
