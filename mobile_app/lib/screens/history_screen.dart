import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/run_history.dart';
import '../services/poster_runner.dart';
import '../utils/compat_theme.dart';
import '../utils/text_direction_helper.dart';

/// Side-menu screen displaying execution history of the posting script,
/// aggregate summary metrics, filter chips, per-group breakdowns, and Bridge sync.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.controller});

  final AppStateController controller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  RunOverallStatus? _filter;
  bool _syncing = false;

  Future<void> _syncBridge() async {
    setState(() => _syncing = true);
    try {
      final count = await widget.controller.syncHistoryFromBridge();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? 'Imported $count report(s) from bridge.'
                : 'History is already up to date.',
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bridge sync failed: $err'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History?'),
        content: const Text('Remove all saved script execution logs?'),
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
      await widget.controller.clearHistory();
    }
  }

  void _showEntryDetail(BuildContext context, RunHistoryEntry entry) {
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                _StatusBadge(status: entry.status),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.postTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy JSON Report',
                  icon: const Icon(Icons.copy_all_outlined),
                  onPressed: () {
                    final jsonStr = const JsonEncoder.withIndent('  ').convert(
                      entry.results.map((r) => r.toJson()).toList(),
                    );
                    Clipboard.setData(ClipboardData(text: jsonStr));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied JSON report.')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Started: ${dateFmt.format(entry.startedAt.toLocal())} • '
              'Duration: ${entry.duration.inSeconds}s • Mode: ${entry.mode}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (entry.postMessagePreview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorWithOpacity(
                    surfaceContainerHighestCompat(Theme.of(context).colorScheme),
                    0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Directionality(
                  textDirection: detectTextDirection(entry.postMessagePreview),
                  child: Text(entry.postMessagePreview),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Per-Group Results (${entry.results.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (entry.results.isEmpty)
              const Text('No groups were processed in this run.')
            else
              ...entry.results.map(
                (r) => AppCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      _iconForGroupStatus(r.status),
                      color: _colorForGroupStatus(r.status),
                    ),
                    title: Text(
                      r.group,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      [
                        'Status: ${r.status}',
                        if (r.anonymous == true) 'anonymous',
                        if (r.reason != null) r.reason!,
                        if (r.error != null) r.error!,
                      ].join(' • '),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.controller.history;
    final filtered = _filter == null
        ? all
        : all.where((e) => e.status == _filter).toList();
    final dateFmt = DateFormat('MMM d, yyyy • HH:mm');
    final totalPosted = all.fold<int>(0, (sum, e) => sum + e.postedCount);
    final totalSkipped = all.fold<int>(0, (sum, e) => sum + e.skippedCount);
    final totalFailed = all.fold<int>(0, (sum, e) => sum + e.failedCount);

    return Column(
      children: [
        if (all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _StatTile(
                  label: 'Runs',
                  value: '${all.length}',
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _StatTile(
                  label: 'Posted',
                  value: '$totalPosted',
                  color: Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                _StatTile(
                  label: 'Skipped',
                  value: '$totalSkipped',
                  color: Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                _StatTile(
                  label: 'Failed',
                  value: '$totalFailed',
                  color: Colors.red.shade700,
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      const SizedBox(width: 6),
                      ...RunOverallStatus.values.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(_labelForOverall(s)),
                            selected: _filter == s,
                            onSelected: (_) => setState(() => _filter = s),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sync from Bridge',
                onPressed: _syncing ? null : _syncBridge,
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
              ),
              if (all.isNotEmpty)
                IconButton(
                  tooltip: 'Clear History',
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_toggle_off,
                          size: 56,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        const Text('No script execution history yet.'),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return AppCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        onTap: () => _showEntryDetail(context, entry),
                        leading: _StatusBadge(status: entry.status),
                        title: Text(
                          entry.postTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              '${dateFmt.format(entry.startedAt.toLocal())} • ${entry.mode}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 10,
                              children: [
                                _MiniMetric(
                                  text: '${entry.postedCount} posted',
                                  color: Colors.green.shade700,
                                ),
                                _MiniMetric(
                                  text: '${entry.skippedCount} skipped',
                                  color: Colors.orange.shade800,
                                ),
                                _MiniMetric(
                                  text: '${entry.failedCount} failed',
                                  color: Colors.red.shade700,
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _labelForOverall(RunOverallStatus s) => switch (s) {
        RunOverallStatus.completed => 'Completed',
        RunOverallStatus.stopped => 'Stopped',
        RunOverallStatus.failed => 'Failed',
        RunOverallStatus.blocked => 'Blocked',
        RunOverallStatus.dryRun => 'Dry Run',
      };

  static IconData _iconForGroupStatus(String status) => switch (status) {
        'posted' => Icons.check_circle,
        'dry_run_ok' => Icons.science,
        'skipped' => Icons.skip_next,
        'blocked' => Icons.lock_outline,
        _ => Icons.error_outline,
      };

  static Color _colorForGroupStatus(String status) => switch (status) {
        'posted' => Colors.green,
        'dry_run_ok' => Colors.blue,
        'skipped' => Colors.orange,
        'blocked' => Colors.deepOrange,
        _ => Colors.red,
      };
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: colorWithOpacity(color, 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorWithOpacity(color, 0.28)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final RunOverallStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      RunOverallStatus.completed => ('OK', Colors.green),
      RunOverallStatus.stopped => ('STOPPED', Colors.amber.shade800),
      RunOverallStatus.failed => ('FAILED', Colors.red),
      RunOverallStatus.blocked => ('AUTH', Colors.deepOrange),
      RunOverallStatus.dryRun => ('DRY', Colors.blue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorWithOpacity(color, 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorWithOpacity(color, 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
