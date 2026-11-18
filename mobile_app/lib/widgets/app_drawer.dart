import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/poster_runner.dart';

enum AppSection {
  home,
  account,
  posts,
  history,
}

/// Side menu (Drawer) providing navigation to Runner, FB Account credentials,
/// Default Post creation/selection, and Script Execution History.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.currentSection,
    required this.controller,
    required this.onSelectSection,
  });

  final AppSection currentSection;
  final AppStateController controller;
  final ValueChanged<AppSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = controller.account;
    final defaultPost = controller.defaultPost;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    Color.lerp(
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                          0.35,
                        ) ??
                        theme.colorScheme.primaryContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FB Group Poster',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${controller.settings.groups.length} group(s) configured',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _HeaderBadge(
                    icon: Icons.person_outline,
                    label: account.hasCredentials
                        ? account.maskedEmail
                        : 'Account not configured',
                  ),
                  const SizedBox(height: 5),
                  _HeaderBadge(
                    icon: Icons.article_outlined,
                    label: defaultPost != null
                        ? 'Default: ${defaultPost.title}'
                        : 'No default post selected',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  _DrawerNavTile(
                    icon: Icons.play_circle_outline,
                    selectedIcon: Icons.play_circle,
                    label: 'Script Runner (Start / Stop)',
                    subtitle: controller.isRunning ? 'Active run' : 'Ready',
                    selected: currentSection == AppSection.home,
                    onTap: () => onSelectSection(AppSection.home),
                  ),
                  _DrawerNavTile(
                    icon: Icons.manage_accounts_outlined,
                    selectedIcon: Icons.manage_accounts,
                    label: 'FB Account (Email & Password)',
                    subtitle: account.hasCredentials
                        ? account.maskedEmail
                        : 'Set login details',
                    selected: currentSection == AppSection.account,
                    trailing: Icon(
                      account.hasCredentials
                          ? Icons.check_circle
                          : Icons.warning_amber_rounded,
                      color: account.hasCredentials
                          ? Colors.green
                          : Colors.orange,
                      size: 19,
                    ),
                    onTap: () => onSelectSection(AppSection.account),
                  ),
                  _DrawerNavTile(
                    icon: Icons.post_add_outlined,
                    selectedIcon: Icons.post_add,
                    label: 'Default Post (Create & Select)',
                    subtitle: defaultPost != null
                        ? 'Selected: ${defaultPost.title}'
                        : 'Create your post template',
                    selected: currentSection == AppSection.posts,
                    trailing: controller.posts.isNotEmpty
                        ? _CountPill(count: controller.posts.length)
                        : null,
                    onTap: () => onSelectSection(AppSection.posts),
                  ),
                  _DrawerNavTile(
                    icon: Icons.history_outlined,
                    selectedIcon: Icons.history,
                    label: 'Script History',
                    subtitle: controller.history.isEmpty
                        ? 'No runs yet'
                        : '${controller.history.length} run(s) logged',
                    selected: currentSection == AppSection.history,
                    trailing: controller.history.isNotEmpty
                        ? _CountPill(count: controller.history.length)
                        : null,
                    onTap: () => onSelectSection(AppSection.history),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          controller.isRunning ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      controller.isRunning
                          ? 'Posting in progress...'
                          : 'Engine: ${controller.settings.executionMode == ExecutionMode.webView ? 'Mobile Browser' : 'Python Bridge'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        selected: selected,
        selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.55),
        leading: Icon(selected ? selectedIcon : icon),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: trailing,
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }
}
