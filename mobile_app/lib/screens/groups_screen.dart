import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/poster_runner.dart';
import '../utils/compat_theme.dart';

/// Side-menu screen for adding, pasting, bulk-importing, and removing target
/// Facebook group URLs.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.controller});

  final AppStateController controller;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _groupInputController = TextEditingController();

  @override
  void dispose() {
    _groupInputController.dispose();
    super.dispose();
  }

  Future<void> _handleAddGroups([String? overrideInput]) async {
    final raw = (overrideInput ?? _groupInputController.text).trim();
    if (raw.isEmpty) return;
    try {
      final added = await widget.controller.addGroupUrls(raw);
      if (overrideInput == null) {
        _groupInputController.clear();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added > 0
                ? 'Added $added group${added == 1 ? '' : 's'}.'
                : 'Group URL already in list.',
          ),
        ),
      );
    } on FormatException catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pasteGroupsFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty.')),
      );
      return;
    }
    await _handleAddGroups(text);
  }

  Future<void> _openBulkAddDialog() async {
    final bulkCtrl = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Add Facebook Groups'),
        content: TextField(
          controller: bulkCtrl,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText:
                'Paste one group URL per line:\nhttps://www.facebook.com/groups/...\nhttps://www.facebook.com/groups/...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(bulkCtrl.text),
            child: const Text('Add Groups'),
          ),
        ],
      ),
    );
    bulkCtrl.dispose();
    if (submitted != null && submitted.trim().isNotEmpty) {
      await _handleAddGroups(submitted);
    }
  }

  Future<void> _clearAllGroups() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Groups?'),
        content: Text(
          'Remove all ${widget.controller.settings.groups.length} groups from the target list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.updateSettings(
        widget.controller.settings.copyWith(groups: const []),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final groups = ctrl.settings.groups;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.groups_outlined, size: 22, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Target Groups (${groups.length})',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: ctrl.isRunning ? null : _openBulkAddDialog,
                      icon: const Icon(Icons.playlist_add, size: 18),
                      label: const Text('Bulk'),
                    ),
                    IconButton(
                      tooltip: 'Restore default groups (${AppSettings.defaultGroups.length})',
                      onPressed: ctrl.isRunning
                          ? null
                          : () async {
                              await ctrl.restoreDefaultGroups();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Restored ${AppSettings.defaultGroups.length} default groups.',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.restore_outlined, size: 20),
                    ),
                    if (groups.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear all groups',
                        onPressed: ctrl.isRunning ? null : _clearAllGroups,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('group_url_field'),
                        controller: _groupInputController,
                        enabled: !ctrl.isRunning,
                        decoration: InputDecoration(
                          hintText: 'https://www.facebook.com/groups/...',
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: 'Paste & Add',
                            icon: const Icon(Icons.content_paste_go, size: 20),
                            onPressed: ctrl.isRunning
                                ? null
                                : _pasteGroupsFromClipboard,
                          ),
                        ),
                        onSubmitted: (_) => _handleAddGroups(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: ctrl.isRunning ? null : _handleAddGroups,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.group_add_outlined,
                    size: 48,
                    color: scheme.outline,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No Groups Configured',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Paste a Facebook group URL above, or tap "Bulk" to import multiple URLs at once.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          )
        else
          ...groups.asMap().entries.map((entry) {
            final idx = entry.key;
            final url = entry.value;
            final segments = Uri.tryParse(url)
                    ?.pathSegments
                    .where((s) => s.isNotEmpty)
                    .toList() ??
                const <String>[];
            final slug = segments.isNotEmpty ? segments.last : url;
            return AppCard(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    '${idx + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                title: Text(
                  'Group $slug',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 19),
                  onPressed:
                      ctrl.isRunning ? null : () => ctrl.removeGroupUrl(url),
                ),
              ),
            );
          }),
      ],
    );
  }
}
