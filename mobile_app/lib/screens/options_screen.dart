import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/poster_runner.dart';
import '../utils/compat_theme.dart';

/// Side-menu screen for configuring Anonymous Posting Mode, Dry Run,
/// inter-group Delays, and Execution Engine.
class OptionsScreen extends StatefulWidget {
  const OptionsScreen({super.key, required this.controller});

  final AppStateController controller;

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  late final TextEditingController _delayMinController;
  late final TextEditingController _delayMaxController;
  late final TextEditingController _browserPathController;

  @override
  void initState() {
    super.initState();
    _delayMinController = TextEditingController(
      text: widget.controller.settings.delayMin.toStringAsFixed(0),
    );
    _delayMaxController = TextEditingController(
      text: widget.controller.settings.delayMax.toStringAsFixed(0),
    );
    _browserPathController = TextEditingController(
      text: widget.controller.settings.browserExecutablePath,
    );
  }

  @override
  void dispose() {
    _delayMinController.dispose();
    _delayMaxController.dispose();
    _browserPathController.dispose();
    super.dispose();
  }

  Future<void> _saveBrowserPath() async {
    final path = _browserPathController.text.trim();
    await widget.controller.updateSettings(
      widget.controller.settings.copyWith(browserExecutablePath: path),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path.isEmpty
              ? 'Browser path reset to auto-detect.'
              : 'Custom browser path saved.',
        ),
      ),
    );
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
                    Icon(Icons.visibility_off_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Anonymous Posting Mode',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 8),
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
                const Divider(height: 16),
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Delay Between Groups',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 12),
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings_suggest_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Execution Engine',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ExecutionMode>(
                  // Flutter 3.19.6 uses `value` (`initialValue` was added later).
                  // ignore: deprecated_member_use
                  value: settings.executionMode,
                  decoration: const InputDecoration(
                    labelText: 'Mode',
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: ExecutionMode.desktopBrowser,
                      enabled: ctrl.isDesktopBrowserSupported,
                      child: Text(
                        ctrl.isDesktopBrowserSupported
                            ? 'Built-In Desktop Browser (Chrome / Edge — No Python)'
                            : 'Built-In Desktop Browser (Windows / Linux / macOS)',
                      ),
                    ),
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
                if (ctrl.isDesktopBrowserSupported &&
                    settings.executionMode == ExecutionMode.desktopBrowser) ...[
                  const SizedBox(height: 12),
                  Text(
                    ctrl.detectedDesktopBrowserPath != null
                        ? 'Detected browser: ${ctrl.detectedDesktopBrowserPath}'
                        : 'No Chrome/Edge/Supermium/Brave auto-detected. Install Chrome/Edge (or Supermium on Windows 7) or set the .exe path below.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ctrl.detectedDesktopBrowserPath != null
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _browserPathController,
                          enabled: !ctrl.isRunning,
                          decoration: const InputDecoration(
                            labelText: 'Custom Browser Path (Optional)',
                            hintText:
                                r'Leave empty for auto-detect (e.g. C:\Program Files\...\chrome.exe)',
                            isDense: true,
                          ),
                          onEditingComplete: _saveBrowserPath,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: ctrl.isRunning ? null : _saveBrowserPath,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
