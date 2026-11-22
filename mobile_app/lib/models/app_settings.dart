enum ExecutionMode {
  webView,
  bridge,
}

enum AnonymousPolicy {
  /// Always post anonymously; skip groups where anonymous posting is disabled.
  strictAnonymous,

  /// Post anonymously if the group has it active; otherwise post normally.
  preferAnonymous,

  /// Post publicly with your account name (optionally blocking if anonymous is active).
  publicOnly,
}

/// Persisted poster configuration mirroring config.json options.
class AppSettings {
  static const List<String> defaultGroups = [
    'https://www.facebook.com/groups/2338817133078126/',
    'https://www.facebook.com/groups/356949655982125/',
    'https://www.facebook.com/groups/4369447123145015/',
    'https://www.facebook.com/groups/305533033724233/',
    'https://www.facebook.com/groups/538858678019757/',
    'https://www.facebook.com/groups/32805080205772085/',
    'https://www.facebook.com/groups/9863293940361144/',
    'https://www.facebook.com/groups/536800640731186/',
    'https://www.facebook.com/groups/432165591420240/',
    'https://www.facebook.com/groups/661920747330839/',
    'https://www.facebook.com/groups/1477161749230307/',
    'https://www.facebook.com/groups/354321778673724/',
    'https://www.facebook.com/groups/1228346991425028/',
    'https://www.facebook.com/groups/1401662116893508/',
  ];

  const AppSettings({
    this.groups = defaultGroups,
    this.anonymousPolicy = AnonymousPolicy.preferAnonymous,
    this.requireAnonymousIfAvailable = false,
    this.dryRun = false,
    this.delayMin = 5.0,
    this.delayMax = 12.0,
    this.bridgeUrl = 'http://127.0.0.1:8765',
    this.executionMode = ExecutionMode.webView,
  });

  final List<String> groups;
  final AnonymousPolicy anonymousPolicy;
  final bool requireAnonymousIfAvailable;
  final bool dryRun;
  final double delayMin;
  final double delayMax;
  final String bridgeUrl;
  final ExecutionMode executionMode;

  bool get anonymous => anonymousPolicy == AnonymousPolicy.strictAnonymous;
  bool get preferAnonymous => anonymousPolicy == AnonymousPolicy.preferAnonymous;

  AppSettings copyWith({
    List<String>? groups,
    AnonymousPolicy? anonymousPolicy,
    bool? anonymous,
    bool? requireAnonymousIfAvailable,
    bool? dryRun,
    double? delayMin,
    double? delayMax,
    String? bridgeUrl,
    ExecutionMode? executionMode,
  }) {
    final resolvedPolicy = anonymousPolicy ??
        (anonymous != null
            ? (anonymous
                ? AnonymousPolicy.strictAnonymous
                : AnonymousPolicy.publicOnly)
            : this.anonymousPolicy);
    return AppSettings(
      groups: groups ?? this.groups,
      anonymousPolicy: resolvedPolicy,
      requireAnonymousIfAvailable:
          requireAnonymousIfAvailable ?? this.requireAnonymousIfAvailable,
      dryRun: dryRun ?? this.dryRun,
      delayMin: delayMin ?? this.delayMin,
      delayMax: delayMax ?? this.delayMax,
      bridgeUrl: bridgeUrl ?? this.bridgeUrl,
      executionMode: executionMode ?? this.executionMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'groups': groups,
        'anonymousPolicy': anonymousPolicy.name,
        'anonymous': anonymous,
        'requireAnonymousIfAvailable': requireAnonymousIfAvailable,
        'dryRun': dryRun,
        'delayMin': delayMin,
        'delayMax': delayMax,
        'bridgeUrl': bridgeUrl,
        'executionMode': executionMode.name,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final modeName = json['executionMode'] as String? ?? 'webView';
    final mode = ExecutionMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => ExecutionMode.webView,
    );

    AnonymousPolicy policy;
    final policyName = json['anonymousPolicy'] as String?;
    if (policyName != null) {
      policy = AnonymousPolicy.values.firstWhere(
        (p) => p.name == policyName,
        orElse: () => AnonymousPolicy.preferAnonymous,
      );
    } else if (json['anonymous'] is bool) {
      policy = (json['anonymous'] as bool)
          ? AnonymousPolicy.strictAnonymous
          : AnonymousPolicy.publicOnly;
    } else {
      policy = AnonymousPolicy.preferAnonymous;
    }

    return AppSettings(
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      anonymousPolicy: policy,
      requireAnonymousIfAvailable:
          json['requireAnonymousIfAvailable'] as bool? ?? false,
      dryRun: json['dryRun'] as bool? ?? false,
      delayMin: (json['delayMin'] as num?)?.toDouble() ?? 5.0,
      delayMax: (json['delayMax'] as num?)?.toDouble() ?? 12.0,
      bridgeUrl: json['bridgeUrl'] as String? ?? 'http://127.0.0.1:8765',
      executionMode: mode,
    );
  }
}
