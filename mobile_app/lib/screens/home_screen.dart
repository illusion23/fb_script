import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/app_settings.dart';
import '../services/poster_runner.dart';
import '../utils/text_direction_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/live_webview_sheet.dart';

/// Main runner screen featuring Start and Stop buttons, setup readiness pills,
/// active default post preview, easy group management, options, and live logs.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onNavigate,
  });

  final AppStateController controller;
  final ValueChanged<AppSection> onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _groupInputController = TextEditingController();
  late final TextEditingController _delayMinController;
  late final TextEditingController _delayMaxController;
  bool _showLiveBrowser = true;

  @override
  void initState() {
    super.initState();
    _delayMinController = TextEditingController(
      text: widget.controller.settings.delayMin.toStringAsFixed(0),
    );
    _delayMaxController = TextEditingController(
      text: widget.controller.settings.delayMax.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _groupInputController.dispose();
    _delayMinController.dispose();
    _delayMaxController.dispose();
    super.dispose();
  }

  Future<void> _handleStart() async {
    try {
      await widget.controller.startScript();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString()), backgroundColor: Colors.red),
      );
    }
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
    _groupInputController.text = text;
    await _handleAddGroups(text);
    _groupInputController.clear();
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

  Future<void> _setDelayPreset(double minVal, double maxVal) async {
    _delayMinController.text = minVal.toStringAsFixed(0);
    _delayMaxController.text = maxVal.toStringAsFixed(0);
    await widget.controller.updateSettings(
      widget.controller.settings.copyWith(delayMin: minVal, delayMax: maxVal),
    );
  }

  Future<void> _applyDelays() async {
    final minVal = double.tryParse(_delayMinController.text.trim());
    final maxVal = double.tryParse(_delayMaxController.text.trim());
    if (minVal == null || maxVal == null || minVal < 0 || maxVal < minVal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter valid min/max delay seconds (min <= max).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await widget.controller.updateSettings(
      widget.controller.settings.copyWith(delayMin: minVal, delayMax: maxVal),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Delay updated: ${minVal.toStringAsFixed(0)}s – ${maxVal.toStringAsFixed(0)}s',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final settings = ctrl.settings;
    final defaultPost = ctrl.defaultPost;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final progressValue = ctrl.totalGroups > 0
        ? (ctrl.currentGroupIndex / ctrl.totalGroups).clamp(0.0, 1.0)
        : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        // 1. Setup Readiness Strip (1-tap access to anything missing)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ReadinessPill(
                icon: ctrl.account.hasCredentials
                    ? Icons.check_circle
                    : Icons.person_outline,
                label: ctrl.account.hasCredentials
                    ? 'Account Ready'
                    : 'Set Account',
                ready: ctrl.account.hasCredentials,
                onTap: () => widget.onNavigate(AppSection.account),
              ),
              const SizedBox(width: 8),
              _ReadinessPill(
                icon: defaultPost != null
                    ? Icons.check_circle
                    : Icons.article_outlined,
                label: defaultPost != null
                    ? 'Post: ${defaultPost.title}'
                    : 'Select Post',
                ready: defaultPost != null,
                onTap: () => widget.onNavigate(AppSection.posts),
              ),
              const SizedBox(width: 8),
              _ReadinessPill(
                icon: settings.groups.isNotEmpty
                    ? Icons.check_circle
                    : Icons.group_add_outlined,
                label: settings.groups.isNotEmpty
                    ? '${settings.groups.length} Group(s)'
                    : 'Add Groups',
                ready: settings.groups.isNotEmpty,
                onTap: ctrl.isRunning ? null : _openBulkAddDialog,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Hero Start / Stop Control Card
        Card(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.35),
                  scheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: (ctrl.isRunning
                                ? scheme.primary
                                : scheme.secondary)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        ctrl.isRunning
                            ? Icons.sync
                            : Icons.rocket_launch_rounded,
                        color: ctrl.isRunning
                            ? scheme.primary
                            : scheme.secondary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ctrl.statusMessage,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (ctrl.currentGroupUrl.isNotEmpty)
                            Text(
                              ctrl.currentGroupUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (ctrl.isWebViewSupported)
                      IconButton.filledTonal(
                        tooltip: 'Open Live Browser',
                        icon: const Icon(Icons.open_in_browser),
                        onPressed: () => LiveWebViewSheet.show(context, ctrl),
                      ),
                  ],
                ),
                if (ctrl.isRunning || ctrl.totalGroups > 0) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      value: ctrl.isRunning && ctrl.currentGroupIndex == 0
                          ? null
                          : progressValue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress: ${ctrl.currentGroupIndex} / ${ctrl.totalGroups} groups',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (ctrl.countdownSeconds > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Next in ${ctrl.countdownSeconds}s',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('start_script_button'),
                        onPressed: ctrl.isRunning ? null : _handleStart,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 24),
                        label: const Text(
                          'Start',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('stop_script_button'),
                        onPressed: ctrl.isRunning && !ctrl.isStopping
                            ? ctrl.stopScript
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.stop_rounded, size: 24),
                        label: Text(
                          ctrl.isStopping ? 'Stopping...' : 'Stop',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (ctrl.needsManualAuth && ctrl.isWebViewSupported) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.security, color: Colors.orange),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Facebook needs 2FA or manual login. Sign in once, then press Start.',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await ctrl.openInteractiveLoginPage();
                            if (context.mounted) {
                              await LiveWebViewSheet.show(context, ctrl);
                            }
                          },
                          child: const Text('Sign In'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Live WebView Preview (mounted during mobile WebView runs)
        if (ctrl.isWebViewSupported &&
            ctrl.webViewController != null &&
            ((ctrl.isRunning &&
                    settings.executionMode == ExecutionMode.webView) ||
                ctrl.needsManualAuth)) ...[
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.public, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Live Facebook Browser',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _showLiveBrowser = !_showLiveBrowser),
                        child: Text(_showLiveBrowser ? 'Compact' : 'Expand'),
                      ),
                      IconButton(
                        tooltip: 'Full Browser Sheet',
                        icon: const Icon(Icons.open_in_full, size: 18),
                        onPressed: () => LiveWebViewSheet.show(context, ctrl),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SizedBox(
                  height: _showLiveBrowser ? 360 : 120,
                  child: WebViewWidget(controller: ctrl.webViewController!),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),

        // 3. Selected Default Post Preview Card
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => widget.onNavigate(AppSection.posts),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.article_outlined,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Default Post',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      FilledButton.tonal(
                        onPressed: () => widget.onNavigate(AppSection.posts),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          defaultPost == null ? 'Create Post' : 'Change',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (defaultPost == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'No default post selected yet. Tap here to create or choose a post.',
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    )
                  else ...[
                    Text(
                      defaultPost.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (defaultPost.message.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Directionality(
                          textDirection:
                              detectTextDirection(defaultPost.message),
                          child: Text(
                            defaultPost.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                    if (defaultPost.imagePaths.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 54,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: defaultPost.imagePaths.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final path = defaultPost.imagePaths[idx];
                            final file = File(path);
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: file.existsSync()
                                  ? Image.file(
                                      file,
                                      width: 54,
                                      height: 54,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 54,
                                      height: 54,
                                      color: scheme.surfaceContainerHighest,
                                      child: const Icon(Icons.image_outlined),
                                    ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 4. Target Groups Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.groups_outlined,
                        size: 22, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Target Groups (${settings.groups.length})',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: ctrl.isRunning ? null : _openBulkAddDialog,
                      icon: const Icon(Icons.playlist_add, size: 18),
                      label: const Text('Bulk'),
                    ),
                    if (settings.groups.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear all groups',
                        onPressed: ctrl.isRunning ? null : _clearAllGroups,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
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
                if (settings.groups.isEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Paste a Facebook group URL above, or tap "Bulk" to paste multiple URLs at once.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  ...settings.groups.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final url = entry.value;
                    final slug = Uri.tryParse(url)
                            ?.pathSegments
                            .where((s) => s.isNotEmpty)
                            .lastOrNull ??
                        url;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: scheme.primaryContainer,
                            child: Text(
                              '${idx + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Group $slug',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: ctrl.isRunning
                                ? null
                                : () => ctrl.removeGroupUrl(url),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 5. Script Options Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Script Options',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Anonymous Posting Mode',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Auto (If Active)'),
                      selected: settings.anonymousPolicy ==
                          AnonymousPolicy.preferAnonymous,
                      onSelected: ctrl.isRunning
                          ? null
                          : (_) => ctrl.updateSettings(
                                settings.copyWith(
                                  anonymousPolicy:
                                      AnonymousPolicy.preferAnonymous,
                                ),
                              ),
                    ),
                    ChoiceChip(
                      label: const Text('Strict Anonymous'),
                      selected: settings.anonymousPolicy ==
                          AnonymousPolicy.strictAnonymous,
                      onSelected: ctrl.isRunning
                          ? null
                          : (_) => ctrl.updateSettings(
                                settings.copyWith(
                                  anonymousPolicy:
                                      AnonymousPolicy.strictAnonymous,
                                ),
                              ),
                    ),
                    ChoiceChip(
                      label: const Text('Public Only'),
                      selected: settings.anonymousPolicy ==
                          AnonymousPolicy.publicOnly,
                      onSelected: ctrl.isRunning
                          ? null
                          : (_) => ctrl.updateSettings(
                                settings.copyWith(
                                  anonymousPolicy: AnonymousPolicy.publicOnly,
                                ),
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  switch (settings.anonymousPolicy) {
                    AnonymousPolicy.preferAnonymous =>
                      'Posts anonymously when the group supports it, and posts normally otherwise (does not skip).',
                    AnonymousPolicy.strictAnonymous =>
                      'Always posts anonymously. Groups without anonymous posting will be skipped.',
                    AnonymousPolicy.publicOnly => settings
                            .requireAnonymousIfAvailable
                        ? 'Posts publicly only when anonymous is NOT available in the group.'
                        : 'Always posts publicly with your account name (never skips).',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  key: const Key('require_anonymous_if_available_switch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.shield_outlined),
                  title: const Text('Block Non-Anonymous If Group Has Anonymous'),
                  subtitle: const Text(
                    'Applies in Public Only mode: skip groups where anonymous is active',
                  ),
                  value: settings.requireAnonymousIfAvailable,
                  onChanged: ctrl.isRunning
                      ? null
                      : (v) => ctrl.updateSettings(
                            settings.copyWith(requireAnonymousIfAvailable: v),
                          ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.science_outlined),
                  title: const Text('Dry Run (Test Only)'),
                  subtitle: const Text(
                    'Open & fill composer without clicking Post',
                  ),
                  value: settings.dryRun,
                  onChanged: ctrl.isRunning
                      ? null
                      : (v) => ctrl.updateSettings(
                            settings.copyWith(dryRun: v),
                          ),
                ),
                const Divider(height: 22),
                Text(
                  'Delay Between Groups',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Fast (5–12s)'),
                      selected:
                          settings.delayMin == 5 && settings.delayMax == 12,
                      onSelected: ctrl.isRunning
                          ? null
                          : (_) => _setDelayPreset(5, 12),
                    ),
                    ChoiceChip(
                      label: const Text('Safe (20–45s)'),
                      selected:
                          settings.delayMin == 20 && settings.delayMax == 45,
                      onSelected: ctrl.isRunning
                          ? null
                          : (_) => _setDelayPreset(20, 45),
                    ),
                    ChoiceChip(
                      label: const Text('Slow (45–90s)'),
                      selected:
                          settings.delayMin == 45 && settings.delayMax == 90,
                      onSelected: ctrl.isRunning
                          ? null
                          : (_) => _setDelayPreset(45, 90),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _delayMinController,
                        enabled: !ctrl.isRunning,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Min Delay (s)',
                          isDense: true,
                        ),
                        onEditingComplete: _applyDelays,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _delayMaxController,
                        enabled: !ctrl.isRunning,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max Delay (s)',
                          isDense: true,
                        ),
                        onEditingComplete: _applyDelays,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: ctrl.isRunning ? null : _applyDelays,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<ExecutionMode>(
                  initialValue: settings.executionMode,
                  decoration: const InputDecoration(
                    labelText: 'Execution Engine',
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: ExecutionMode.webView,
                      enabled: ctrl.isWebViewSupported,
                      child: Text(
                        ctrl.isWebViewSupported
                            ? 'On-Device Mobile Browser (WebView)'
                            : 'On-Device WebView (Android/iOS only)',
                      ),
                    ),
                    const DropdownMenuItem(
                      value: ExecutionMode.bridge,
                      child: Text('Python Script Bridge (fb_poster.py)'),
                    ),
                  ],
                  onChanged: ctrl.isRunning
                      ? null
                      : (mode) {
                          if (mode != null) {
                            ctrl.updateSettings(
                              settings.copyWith(executionMode: mode),
                            );
                          }
                        },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 6. Color-Coded Live Execution Log Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal_rounded,
                        size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Live Execution Log',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (ctrl.logs.isNotEmpty)
                      IconButton(
                        tooltip: 'Copy logs',
                        icon: const Icon(Icons.copy_all_outlined, size: 19),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: ctrl.logs.join('\n')),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Logs copied.')),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints:
                      const BoxConstraints(minHeight: 110, maxHeight: 240),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ctrl.logs.isEmpty
                      ? Text(
                          'Press Start above to begin posting to your configured groups.',
                          style: theme.textTheme.bodySmall,
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          reverse: true,
                          itemCount: ctrl.logs.length,
                          itemBuilder: (_, idx) {
                            final line =
                                ctrl.logs[ctrl.logs.length - 1 - idx];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: SelectableText(
                                line,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  color: _colorForLogLine(line, scheme),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Color _colorForLogLine(String line, ColorScheme scheme) {
    if (line.contains('[OK]')) return Colors.green.shade700;
    if (line.contains('[SKIP]') || line.contains('[WARN]')) {
      return Colors.orange.shade800;
    }
    if (line.contains('[ERROR]') || line.contains('[BLOCKED]')) {
      return Colors.red.shade700;
    }
    if (line.contains('[DRY RUN]')) return Colors.blue.shade700;
    return scheme.onSurface;
  }
}

class _ReadinessPill extends StatelessWidget {
  const _ReadinessPill({
    required this.icon,
    required this.label,
    required this.ready,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool ready;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = ready ? Colors.green.shade700 : Colors.orange.shade800;
    return Material(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
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
