import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/poster_runner.dart';
import '../utils/compat_theme.dart';

enum AppSection {
  home,
  account,
  posts,
  groups,
  options,
  history,
}

/// Polished side menu (Drawer) with grouped navigation, quick-status pills,
/// icon badges, and active selection indicators.
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
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final account = controller.account;
    final defaultPost = controller.defaultPost;

    final drawerBg = isDark ? const Color(0xFF171926) : Colors.white;

    return Drawer(
      backgroundColor: drawerBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Sleek Header with quick-status chips
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B4BDB), Color(0xFF1877F2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorWithOpacity(const Color(0xFF1877F2), 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colorWithOpacity(Colors.white, 0.2),
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
                            const Text(
                              'FB Group Poster',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            Text(
                              controller.isRunning
                                  ? 'Script running...'
                                  : '${controller.settings.groups.length} group(s) ready',
                              style: TextStyle(
                                color: colorWithOpacity(Colors.white, 0.85),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _HeaderStatusChip(
                          icon: account.hasCredentials
                              ? Icons.verified_user_rounded
                              : Icons.person_outline,
                          label: account.hasCredentials
                              ? account.maskedEmail
                              : 'No account',
                          onTap: () {
                            Navigator.of(context).pop();
                            onSelectSection(AppSection.account);
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _HeaderStatusChip(
                          icon: Icons.article_outlined,
                          label: defaultPost != null
                              ? defaultPost.title
                              : 'No post',
                          onTap: () {
                            Navigator.of(context).pop();
                            onSelectSection(AppSection.posts);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Grouped Navigation Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                children: [
                  _DrawerNavTile(
                    icon: Icons.play_circle_outline,
                    selectedIcon: Icons.play_circle_rounded,
                    label: 'Script Runner (Start / Stop)',
                    selected: currentSection == AppSection.home,
                    onTap: () => onSelectSection(AppSection.home),
                  ),
                  const _SectionHeader(title: 'CONFIGURATION'),
                  _DrawerNavTile(
                    icon: Icons.manage_accounts_outlined,
                    selectedIcon: Icons.manage_accounts_rounded,
                    label: 'FB Account (Email & Password)',
                    selected: currentSection == AppSection.account,
                    trailing: _StatusDot(ready: account.hasCredentials),
                    onTap: () => onSelectSection(AppSection.account),
                  ),
                  _DrawerNavTile(
                    icon: Icons.post_add_outlined,
                    selectedIcon: Icons.post_add_rounded,
                    label: 'Default Post (Create & Select)',
                    selected: currentSection == AppSection.posts,
                    trailing: controller.posts.isNotEmpty
                        ? _CountPill(count: controller.posts.length)
                        : null,
                    onTap: () => onSelectSection(AppSection.posts),
                  ),
                  _DrawerNavTile(
                    icon: Icons.groups_outlined,
                    selectedIcon: Icons.groups_rounded,
                    label: 'Target Groups',
                    selected: currentSection == AppSection.groups,
                    trailing: controller.settings.groups.isNotEmpty
                        ? _CountPill(count: controller.settings.groups.length)
                        : null,
                    onTap: () => onSelectSection(AppSection.groups),
                  ),
                  _DrawerNavTile(
                    icon: Icons.tune_outlined,
                    selectedIcon: Icons.tune_rounded,
                    label: 'Script Options',
                    selected: currentSection == AppSection.options,
                    trailing: _TagPill(
                      text: switch (controller.settings.anonymousPolicy) {
                        AnonymousPolicy.preferAnonymous => 'Auto',
                        AnonymousPolicy.strictAnonymous => 'Anon',
                        AnonymousPolicy.publicOnly => 'Public',
                      },
                    ),
                    onTap: () => onSelectSection(AppSection.options),
                  ),
                  const _SectionHeader(title: 'LOGS & REPORTS'),
                  _DrawerNavTile(
                    icon: Icons.history_outlined,
                    selectedIcon: Icons.history_rounded,
                    label: 'Script History',
                    selected: currentSection == AppSection.history,
                    trailing: controller.history.isNotEmpty
                        ? _CountPill(count: controller.history.length)
                        : null,
                    onTap: () => onSelectSection(AppSection.history),
                  ),
                ],
              ),
            ),

            // Clean Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: colorWithOpacity(scheme.outlineVariant, 0.35),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: controller.isRunning
                          ? Colors.greenAccent.shade400
                          : scheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      switch (controller.settings.executionMode) {
                        ExecutionMode.webView => 'Mobile Browser',
                        ExecutionMode.desktopBrowser => 'Desktop Browser',
                        ExecutionMode.bridge => 'Python Bridge',
                      },
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    'v1.0.1',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.outline,
            ),
      ),
    );
  }
}

class _HeaderStatusChip extends StatelessWidget {
  const _HeaderStatusChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorWithOpacity(Colors.white, 0.16),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 13.5, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ready ? Colors.green : Colors.orange,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorWithOpacity(scheme.primaryContainer, 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colorWithOpacity(surfaceContainerHighestCompat(scheme), 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
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
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? colorWithOpacity(scheme.primary, 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 3,
                  height: selected ? 20 : 0,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? colorWithOpacity(scheme.primary, 0.2)
                        : colorWithOpacity(
                            surfaceContainerHighestCompat(scheme),
                            0.5,
                          ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    size: 18,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
