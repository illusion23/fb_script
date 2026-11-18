/// Per-group posting outcome matching fb_poster.py report items.
class GroupRunResult {
  const GroupRunResult({
    required this.group,
    required this.status,
    this.anonymous,
    this.reason,
    this.error,
  });

  final String group;

  /// One of: 'posted', 'dry_run_ok', 'skipped', 'blocked', 'failed'
  final String status;
  final bool? anonymous;
  final String? reason;
  final String? error;

  Map<String, dynamic> toJson() => {
        'group': group,
        'status': status,
        if (anonymous != null) 'anonymous': anonymous,
        if (reason != null) 'reason': reason,
        if (error != null) 'error': error,
      };

  factory GroupRunResult.fromJson(Map<String, dynamic> json) => GroupRunResult(
        group: json['group'] as String? ?? '',
        status: json['status'] as String? ?? 'failed',
        anonymous: json['anonymous'] as bool?,
        reason: json['reason'] as String?,
        error: json['error'] as String?,
      );
}

enum RunOverallStatus {
  completed,
  stopped,
  failed,
  blocked,
  dryRun,
}

/// Complete record of a single script execution for the History screen.
class RunHistoryEntry {
  const RunHistoryEntry({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.mode,
    required this.postTitle,
    required this.postMessagePreview,
    required this.anonymous,
    required this.dryRun,
    required this.results,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final RunOverallStatus status;

  /// 'webview' or 'bridge'
  final String mode;
  final String postTitle;
  final String postMessagePreview;
  final bool anonymous;
  final bool dryRun;
  final List<GroupRunResult> results;

  Duration get duration => endedAt.difference(startedAt);

  int countByStatus(String targetStatus) =>
      results.where((r) => r.status == targetStatus).length;

  int get postedCount =>
      results.where((r) => r.status == 'posted' || r.status == 'dry_run_ok').length;
  int get skippedCount => countByStatus('skipped');
  int get failedCount =>
      results.where((r) => r.status == 'failed' || r.status == 'blocked').length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'status': status.name,
        'mode': mode,
        'postTitle': postTitle,
        'postMessagePreview': postMessagePreview,
        'anonymous': anonymous,
        'dryRun': dryRun,
        'results': results.map((r) => r.toJson()).toList(),
      };

  factory RunHistoryEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    final statusName = json['status'] as String? ?? 'completed';
    final parsedStatus = RunOverallStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => RunOverallStatus.completed,
    );
    return RunHistoryEntry(
      id: json['id'] as String? ?? now.microsecondsSinceEpoch.toString(),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ?? now,
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? '') ?? now,
      status: parsedStatus,
      mode: json['mode'] as String? ?? 'webview',
      postTitle: json['postTitle'] as String? ?? 'Post',
      postMessagePreview: json['postMessagePreview'] as String? ?? '',
      anonymous: json['anonymous'] as bool? ?? false,
      dryRun: json['dryRun'] as bool? ?? false,
      results: (json['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GroupRunResult.fromJson)
          .toList(),
    );
  }
}
