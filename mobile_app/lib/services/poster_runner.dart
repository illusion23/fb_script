import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../models/app_settings.dart';
import '../models/fb_account.dart';
import '../models/post_template.dart';
import '../models/run_history.dart';
import '../utils/group_url_validator.dart';
import 'desktop_browser_driver.dart';
import 'fb_webview_scripts.dart';
import 'storage_service.dart';

/// Adapts [WebViewController] to the shared [AutomationBrowserSession] interface.
class _WebViewBrowserSession implements AutomationBrowserSession {
  _WebViewBrowserSession(this._controller, this._navigate);

  final WebViewController _controller;
  final Future<void> Function(WebViewController ctrl, String url) _navigate;

  @override
  Future<void> navigateAndWait(String url) => _navigate(_controller, url);

  @override
  Future<Object?> evalJs(String script) =>
      _controller.runJavaScriptReturningResult(script);
}

/// Central application state and script runner controller supporting:
/// - on-device mobile WebView automation (Android/iOS)
/// - built-in desktop Chrome/Edge/Supermium CDP automation (Windows 7/10/11, Linux, macOS)
/// - optional companion Python bridge execution (`bridge_server.py`)
class AppStateController extends ChangeNotifier {
  AppStateController(
    this._storage, {
    http.Client? httpClient,
    DesktopBrowserDriver? desktopBrowserDriver,
  })  : _http = httpClient ?? http.Client(),
        _desktopDriverOverride = desktopBrowserDriver;

  final StorageService _storage;
  final http.Client _http;
  final DesktopBrowserDriver? _desktopDriverOverride;
  final Random _random = Random();

  DesktopBrowserDriver? _desktopDriver;

  FbAccount _account = const FbAccount();
  List<PostTemplate> _posts = [];
  String? _defaultPostId;
  AppSettings _settings = const AppSettings();
  List<RunHistoryEntry> _history = [];

  // Runtime execution state
  bool _isRunning = false;
  bool _isStopping = false;
  bool _stopRequested = false;
  bool _needsManualAuth = false;
  int _currentGroupIndex = 0;
  int _totalGroups = 0;
  String _currentGroupUrl = '';
  int _countdownSeconds = 0;
  String _statusMessage = 'Ready';
  final List<String> _logs = [];
  final List<GroupRunResult> _liveResults = [];

  Completer<void>? _delayCompleter;
  WebViewController? _webViewController;
  Completer<void>? _pageFinishedCompleter;

  FbAccount get account => _account;
  List<PostTemplate> get posts => List.unmodifiable(_posts);
  String? get defaultPostId => _defaultPostId;
  AppSettings get settings => _settings;
  List<RunHistoryEntry> get history => List.unmodifiable(_history);

  PostTemplate? get defaultPost {
    if (_posts.isEmpty) return null;
    if (_defaultPostId != null) {
      for (final p in _posts) {
        if (p.id == _defaultPostId) return p;
      }
    }
    return null;
  }

  bool get isRunning => _isRunning;
  bool get isStopping => _isStopping;
  bool get needsManualAuth => _needsManualAuth;
  int get currentGroupIndex => _currentGroupIndex;
  int get totalGroups => _totalGroups;
  String get currentGroupUrl => _currentGroupUrl;
  int get countdownSeconds => _countdownSeconds;
  String get statusMessage => _statusMessage;
  List<String> get logs => List.unmodifiable(_logs);
  List<GroupRunResult> get liveResults => List.unmodifiable(_liveResults);
  WebViewController? get webViewController => _webViewController;

  bool get isWebViewSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get isDesktopBrowserSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  String? get detectedDesktopBrowserPath => isDesktopBrowserSupported
      ? DesktopBrowserDriver.findBrowserExecutable(
          customPath: _settings.browserExecutablePath,
        )
      : null;

  void init() {
    _account = _storage.loadAccount();
    _posts = List<PostTemplate>.from(_storage.loadPosts());
    _defaultPostId = _storage.loadDefaultPostId();
    _settings = _storage.loadSettings();
    _history = List<RunHistoryEntry>.from(_storage.loadHistory());

    if (!_storage.hasSeededDefaultGroups()) {
      final merged = <String>[..._settings.groups];
      for (final g in AppSettings.defaultGroups) {
        if (!merged.contains(g)) {
          merged.add(g);
        }
      }
      _settings = _settings.copyWith(groups: merged);
      _storage.saveSettings(_settings);
      _storage.markDefaultGroupsSeeded();
    }

    // Default to Built-In Desktop Browser on Windows/Linux/macOS where mobile WebView is absent.
    if (!isWebViewSupported && _settings.executionMode == ExecutionMode.webView) {
      _settings = _settings.copyWith(
        executionMode: isDesktopBrowserSupported
            ? ExecutionMode.desktopBrowser
            : ExecutionMode.bridge,
      );
    } else if (!isDesktopBrowserSupported &&
        _settings.executionMode == ExecutionMode.desktopBrowser) {
      _settings = _settings.copyWith(
        executionMode:
            isWebViewSupported ? ExecutionMode.webView : ExecutionMode.bridge,
      );
    }

    if (_defaultPostId == null && _posts.isNotEmpty) {
      _defaultPostId = _posts.first.id;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Account Management
  // ---------------------------------------------------------------------------

  Future<void> saveAccount(FbAccount account) async {
    _account = account;
    await _storage.saveAccount(account);
    notifyListeners();
  }

  Future<void> clearAccount() async {
    _account = const FbAccount();
    await _storage.saveAccount(_account);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Post Templates & Default Post Selection
  // ---------------------------------------------------------------------------

  Future<PostTemplate> createPost({
    required String title,
    required String message,
    List<String> imagePaths = const [],
    bool setAsDefault = true,
  }) async {
    final now = DateTime.now().toUtc();
    final post = PostTemplate(
      id: 'post_${now.microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Untitled Post' : title.trim(),
      message: message.trim(),
      imagePaths: List<String>.from(imagePaths),
      createdAt: now,
      updatedAt: now,
    );
    _posts = [post, ..._posts];
    await _storage.savePosts(_posts);
    if (setAsDefault || _defaultPostId == null) {
      _defaultPostId = post.id;
      await _storage.saveDefaultPostId(post.id);
    }
    notifyListeners();
    return post;
  }

  Future<void> updatePost(PostTemplate updated) async {
    final idx = _posts.indexWhere((p) => p.id == updated.id);
    if (idx == -1) return;
    _posts[idx] = updated.copyWith(updatedAt: DateTime.now().toUtc());
    await _storage.savePosts(_posts);
    notifyListeners();
  }

  Future<void> deletePost(String id) async {
    _posts.removeWhere((p) => p.id == id);
    await _storage.savePosts(_posts);
    if (_defaultPostId == id) {
      _defaultPostId = _posts.isNotEmpty ? _posts.first.id : null;
      await _storage.saveDefaultPostId(_defaultPostId);
    }
    notifyListeners();
  }

  Future<void> selectDefaultPost(String id) async {
    if (!_posts.any((p) => p.id == id)) return;
    _defaultPostId = id;
    await _storage.saveDefaultPostId(id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Settings & Groups
  // ---------------------------------------------------------------------------

  Future<void> updateSettings(AppSettings next) async {
    _settings = next;
    await _storage.saveSettings(next);
    notifyListeners();
  }

  Future<int> addGroupUrls(String rawInput) async {
    final parsed = GroupUrlValidator.parseMany(rawInput);
    final merged = <String>[..._settings.groups];
    var added = 0;
    for (final url in parsed) {
      if (!merged.contains(url)) {
        merged.add(url);
        added++;
      }
    }
    if (added > 0) {
      await updateSettings(_settings.copyWith(groups: merged));
    }
    return added;
  }

  Future<void> removeGroupUrl(String url) async {
    final updated = _settings.groups.where((g) => g != url).toList();
    await updateSettings(_settings.copyWith(groups: updated));
  }

  Future<void> restoreDefaultGroups() async {
    await updateSettings(
      _settings.copyWith(groups: List<String>.from(AppSettings.defaultGroups)),
    );
  }

  // ---------------------------------------------------------------------------
  // History Management
  // ---------------------------------------------------------------------------

  Future<void> _recordRunHistory(RunHistoryEntry entry) async {
    _history = [entry, ..._history];
    await _storage.saveHistory(_history);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = [];
    await _storage.saveHistory(_history);
    notifyListeners();
  }

  Future<int> syncHistoryFromBridge() async {
    final uri = Uri.parse('${_normalizedBridgeUrl()}/history');
    final resp = await _http.get(uri).timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) {
      throw Exception('Bridge returned HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final reports = decoded['reports'] as List<dynamic>? ?? const [];
    final existingIds = _history.map((h) => h.id).toSet();
    var added = 0;
    final imported = <RunHistoryEntry>[];

    for (final item in reports) {
      if (item is! Map<String, dynamic>) continue;
      final filename = item['filename'] as String? ?? '';
      final id = 'bridge_$filename';
      if (existingIds.contains(id)) continue;

      final results = (item['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GroupRunResult.fromJson)
          .toList();

      final stamp = _parseBridgeTimestamp(filename);
      final status = _deriveOverallStatus(
        results: results,
        stopped: false,
        dryRun: results.isNotEmpty && results.every((r) => r.status == 'dry_run_ok'),
      );

      imported.add(
        RunHistoryEntry(
          id: id,
          startedAt: stamp,
          endedAt: stamp,
          status: status,
          mode: 'bridge',
          postTitle: 'Bridge Run ($filename)',
          postMessagePreview: 'Executed via fb_poster.py bridge',
          anonymous: results.any((r) => r.anonymous == true),
          dryRun: status == RunOverallStatus.dryRun,
          results: results,
        ),
      );
      added++;
    }

    if (added > 0) {
      _history = [...imported, ..._history]
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      await _storage.saveHistory(_history);
      notifyListeners();
    }
    return added;
  }

  // ---------------------------------------------------------------------------
  // WebView Initialization & Interactive Login
  // ---------------------------------------------------------------------------

  WebViewController ensureWebViewController() {
    if (_webViewController != null) return _webViewController!;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(FbWebViewScripts.desktopUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (_pageFinishedCompleter != null &&
                !_pageFinishedCompleter!.isCompleted) {
              _pageFinishedCompleter!.complete();
            }
          },
          onWebResourceError: (err) {
            if (err.isForMainFrame == true) {
              _appendLog('[WARN] WebView error: ${err.description}');
            }
          },
        ),
      );
    _webViewController = controller;
    return controller;
  }

  DesktopBrowserDriver _ensureDesktopDriver() {
    if (_desktopDriverOverride != null) return _desktopDriverOverride;
    final customPath = _settings.browserExecutablePath.trim();
    if (_desktopDriver != null &&
        _desktopDriver!.customBrowserPath != customPath) {
      _desktopDriver!.dispose();
      _desktopDriver = null;
    }
    _desktopDriver ??= DesktopBrowserDriver(
      customBrowserPath: customPath,
      httpClient: _http,
    );
    return _desktopDriver!;
  }

  Future<void> openInteractiveLoginPage() async {
    if (_settings.executionMode == ExecutionMode.desktopBrowser &&
        isDesktopBrowserSupported) {
      final driver = _ensureDesktopDriver();
      _needsManualAuth = false;
      await driver.openInteractiveLogin(onLog: _appendLog);
      notifyListeners();
      return;
    }
    if (!isWebViewSupported) {
      final uri = Uri.parse('${_normalizedBridgeUrl()}/login');
      await _http.post(uri).timeout(const Duration(seconds: 6));
      return;
    }
    final ctrl = ensureWebViewController();
    _needsManualAuth = false;
    await ctrl.loadRequest(Uri.parse('https://www.facebook.com/'));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Start / Stop Script Execution
  // ---------------------------------------------------------------------------

  Future<void> startScript() async {
    if (_isRunning) return;

    final post = defaultPost;
    if (post == null || !post.isValid) {
      throw StateError(
        'Please create and select a valid Default Post (text or image) first.',
      );
    }
    if (_settings.groups.isEmpty) {
      throw StateError('Please add at least one Facebook group URL first.');
    }
    if (_settings.delayMin < 0 || _settings.delayMax < _settings.delayMin) {
      throw StateError('Delay min/max values are invalid.');
    }

    _isRunning = true;
    _isStopping = false;
    _stopRequested = false;
    _needsManualAuth = false;
    _currentGroupIndex = 0;
    _totalGroups = _settings.groups.length;
    _currentGroupUrl = '';
    _countdownSeconds = 0;
    _logs.clear();
    _liveResults.clear();
    _statusMessage = 'Starting...';
    notifyListeners();

    final startedAt = DateTime.now().toUtc();
    final mode = _settings.executionMode;

    try {
      if (mode == ExecutionMode.webView) {
        if (!isWebViewSupported) {
          throw UnsupportedError(
            'On-device WebView automation requires Android or iOS. '
            'Switch Execution Mode to "Built-In Desktop Browser" or "Python Bridge".',
          );
        }
        await _runWebViewWorkflow(post);
      } else if (mode == ExecutionMode.desktopBrowser) {
        if (!isDesktopBrowserSupported) {
          throw UnsupportedError(
            'Built-In Desktop Browser mode is available on Windows, Linux, and macOS.',
          );
        }
        await _runDesktopBrowserWorkflow(post);
      } else {
        await _runBridgeWorkflow(post);
      }
    } catch (err) {
      _appendLog('[ERROR] $err');
      if (mode == ExecutionMode.bridge &&
          isDesktopBrowserSupported &&
          err.toString().contains('SocketException')) {
        _appendLog(
          '[HINT] Python Bridge server is not running. To post with zero Python setup, '
          'open Script Options and set Execution Engine to "Built-In Desktop Browser".',
        );
      }
      _statusMessage = 'Error: $err';
    } finally {
      final endedAt = DateTime.now().toUtc();
      final overallStatus = _deriveOverallStatus(
        results: _liveResults,
        stopped: _stopRequested,
        dryRun: _settings.dryRun,
      );

      final entry = RunHistoryEntry(
        id: 'run_${startedAt.microsecondsSinceEpoch}',
        startedAt: startedAt,
        endedAt: endedAt,
        status: overallStatus,
        mode: mode.name,
        postTitle: post.title,
        postMessagePreview: post.message,
        anonymous: _settings.anonymous,
        dryRun: _settings.dryRun,
        results: List<GroupRunResult>.from(_liveResults),
      );
      await _recordRunHistory(entry);

      _isRunning = false;
      _isStopping = false;
      _countdownSeconds = 0;
      if (_stopRequested) {
        _statusMessage = 'Stopped by user';
      } else if (overallStatus == RunOverallStatus.blocked) {
        _statusMessage = 'Stopped: Authentication / 2FA required';
      } else {
        _statusMessage = 'Finished (${overallStatus.name})';
      }
      notifyListeners();
    }
  }

  Future<void> stopScript() async {
    if (!_isRunning || _isStopping) return;
    _stopRequested = true;
    _isStopping = true;
    _statusMessage = 'Stopping...';
    _appendLog('[INFO] Stop button pressed — halting script...');
    if (_delayCompleter != null && !_delayCompleter!.isCompleted) {
      _delayCompleter!.complete();
    }
    notifyListeners();

    if (_settings.executionMode == ExecutionMode.bridge) {
      try {
        final uri = Uri.parse('${_normalizedBridgeUrl()}/stop');
        await _http.post(uri).timeout(const Duration(seconds: 5));
      } catch (err) {
        _appendLog('[WARN] Could not reach bridge /stop: $err');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // On-Device WebView & Built-In Desktop Browser Automation Loop
  // ---------------------------------------------------------------------------

  Future<void> _runWebViewWorkflow(PostTemplate post) async {
    final ctrl = ensureWebViewController();
    notifyListeners();
    // Allow HomeScreen to mount the WebViewWidget with non-zero layout bounds.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final session = _WebViewBrowserSession(ctrl, _navigateAndWait);
    await _runBrowserAutomationLoop(
      session: session,
      post: post,
      engineLabel: 'on-device WebView',
    );
  }

  Future<void> _runDesktopBrowserWorkflow(PostTemplate post) async {
    final driver = _ensureDesktopDriver();
    await driver.ensureConnected(onLog: _appendLog);
    try {
      await _runBrowserAutomationLoop(
        session: driver,
        post: post,
        engineLabel: 'built-in Desktop Browser (CDP)',
      );
    } finally {
      // Leave browser open if Facebook requires manual 2FA / login so the user
      // can finish authenticating right inside the visible window.
      if (!_needsManualAuth && _desktopDriverOverride == null) {
        await driver.close();
      }
    }
  }

  Future<void> _runBrowserAutomationLoop({
    required AutomationBrowserSession session,
    required PostTemplate post,
    required String engineLabel,
  }) async {
    final imagesPayload = await _encodePostImages(post.imagePaths);
    final groups = _settings.groups;

    _appendLog(
      '[INFO] Starting $engineLabel run across ${groups.length} group(s) '
      '(anonymous=${_settings.anonymous}, dry_run=${_settings.dryRun})',
    );

    for (var i = 0; i < groups.length; i++) {
      if (_stopRequested) break;

      final groupUrl = groups[i];
      _currentGroupIndex = i + 1;
      _currentGroupUrl = groupUrl;
      _statusMessage = 'Opening group ${i + 1} of ${groups.length}';
      _appendLog('[INFO] (${i + 1}/${groups.length}) Opening $groupUrl');
      notifyListeners();

      var skipped = false;
      try {
        await session.navigateAndWait(groupUrl);
        if (_stopRequested) break;

        await _dismissBanners(session);

        // Check login / checkpoint
        var authState = await _checkAuthState(session);
        if (authState['status'] == 'login' && _account.hasCredentials) {
          _appendLog('[INFO] Login required (${authState['reason']}); signing in with saved account...');
          await _attemptCredentialLogin(session, groupUrl);
          if (_stopRequested) break;
          await _dismissBanners(session);
          authState = await _checkAuthState(session);
        }

        if (authState['status'] == 'login' || authState['status'] == 'checkpoint') {
          final reason = authState['reason'] as String? ?? 'Facebook authentication required';
          _needsManualAuth = true;
          _appendLog('[BLOCKED] $reason');
          _liveResults.add(
            GroupRunResult(group: groupUrl, status: 'blocked', error: reason),
          );
          notifyListeners();
          break;
        }

        // Open composer and enforce anonymous mode rules
        final composerState = await _waitForComposerReady(
          session,
          _settings.anonymous,
          preferAnonymous: _settings.preferAnonymous,
          requireAnonymousIfAvailable: _settings.requireAnonymousIfAvailable,
        );
        final composerStatus = composerState['status'] as String? ?? '';
        final usedAnonymous = composerState['usedAnonymous'] == true;
        if (composerStatus == 'anonymous_unavailable' ||
            composerStatus == 'anonymous_required_blocked') {
          final reason = composerStatus == 'anonymous_required_blocked'
              ? 'Group has anonymous posting active; skipped without anonymous option.'
              : 'Anonymous posting is not available in this group; skipped.';
          _appendLog('[SKIP] $groupUrl — $reason');
          _liveResults.add(
            GroupRunResult(group: groupUrl, status: 'skipped', reason: reason),
          );
          skipped = true;
        } else {
          final mustEnforceAnonymous =
              _settings.anonymous || (_settings.preferAnonymous && usedAnonymous);
          // Fill text & images and submit (or close if dry-run)
          final submitOutcome = await _submitPostInComposer(
            session: session,
            message: post.message,
            imagesBase64: imagesPayload,
            dryRun: _settings.dryRun,
            requireAnonymous: mustEnforceAnonymous,
          );
          if (submitOutcome == 'anonymous_unavailable') {
            const reason =
                'Anonymous mode could not be confirmed before posting; skipped.';
            _appendLog('[SKIP] $groupUrl — $reason');
            _liveResults.add(
              GroupRunResult(group: groupUrl, status: 'skipped', reason: reason),
            );
            skipped = true;
          } else if (_settings.dryRun) {
            _appendLog('[DRY RUN] Composer verified for $groupUrl (anonymous=$usedAnonymous)');
            _liveResults.add(
              GroupRunResult(
                group: groupUrl,
                status: 'dry_run_ok',
                anonymous: usedAnonymous,
              ),
            );
          } else if (submitOutcome == 'posted') {
            _appendLog('[OK] Posted to $groupUrl (anonymous=$usedAnonymous)');
            _liveResults.add(
              GroupRunResult(
                group: groupUrl,
                status: 'posted',
                anonymous: usedAnonymous,
              ),
            );
          }
        }
      } catch (err) {
        _appendLog('[ERROR] Failed on $groupUrl: $err');
        _liveResults.add(
          GroupRunResult(group: groupUrl, status: 'failed', error: err.toString()),
        );
      }

      notifyListeners();
      if (_stopRequested) break;

      if (i < groups.length - 1) {
        final delay = skipped
            ? min(2.0, _settings.delayMax)
            : _settings.delayMin +
                _random.nextDouble() * (_settings.delayMax - _settings.delayMin);
        await _waitCancellableDelay(delay);
      }
    }
  }

  Future<void> _navigateAndWait(WebViewController ctrl, String url) async {
    _pageFinishedCompleter = Completer<void>();
    await ctrl.loadRequest(Uri.parse(url));
    await _pageFinishedCompleter!.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {},
    );
    await Future<void>.delayed(const Duration(seconds: 3));
  }

  Future<void> _dismissBanners(AutomationBrowserSession session) async {
    try {
      final res = _decodeJsMap(
        await session.evalJs(
          FbWebViewScripts.dismissBannersAndPrompts(),
        ),
      );
      if (res['clicked'] != null) {
        _appendLog('[INFO] Dismissed prompt: ${res['clicked']}');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (_) {
      // ignore non-critical banner check errors
    }
  }

  Future<Map<String, dynamic>> _checkAuthState(
    AutomationBrowserSession session,
  ) async {
    final raw = await session.evalJs(
      FbWebViewScripts.detectAuthOrCheckpoint(),
    );
    return _decodeJsMap(raw);
  }

  Future<void> _attemptCredentialLogin(
    AutomationBrowserSession session,
    String targetGroupUrl,
  ) async {
    var res = _decodeJsMap(
      await session.evalJs(
        FbWebViewScripts.fillAndSubmitLogin(_account.email, _account.password),
      ),
    );
    if (res['ok'] != true) {
      await session.navigateAndWait('https://www.facebook.com/login/');
      await _dismissBanners(session);
      res = _decodeJsMap(
        await session.evalJs(
          FbWebViewScripts.fillAndSubmitLogin(_account.email, _account.password),
        ),
      );
    }
    if (res['ok'] != true) {
      throw Exception(res['error'] ?? 'Could not fill login form');
    }
    await Future<void>.delayed(const Duration(seconds: 5));
    await _dismissBanners(session);
    final afterLogin = await _checkAuthState(session);
    if (afterLogin['status'] == 'ok') {
      await session.navigateAndWait(targetGroupUrl);
    }
  }

  Future<Map<String, dynamic>> _waitForComposerReady(
    AutomationBrowserSession session,
    bool anonymous, {
    bool preferAnonymous = false,
    bool requireAnonymousIfAvailable = false,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    Map<String, dynamic> lastRes = const {};
    while (DateTime.now().isBefore(deadline)) {
      if (_stopRequested) throw Exception('Stopped by user');
      await _dismissBanners(session);
      final res = _decodeJsMap(
        await session.evalJs(
          FbWebViewScripts.openGroupComposer(
            anonymous,
            preferAnonymous: preferAnonymous,
            requireAnonymousIfAvailable: requireAnonymousIfAvailable,
          ),
        ),
      );
      lastRes = res;
      final status = res['status'] as String? ?? '';
      if (status == 'composer_ready' ||
          status == 'anonymous_unavailable' ||
          status == 'anonymous_required_blocked') {
        return res;
      }
      if (status == 'not_a_member') {
        throw Exception(
          res['reason'] ?? 'Account is not a member of this group.',
        );
      }
      final pauseMs = (status == 'trigger_clicked' ||
              status == 'toggled_anonymous' ||
              status == 'dismissed_intro')
          ? 1000
          : 600;
      await Future<void>.delayed(Duration(milliseconds: pauseMs));
    }
    throw Exception(
      'Timed out waiting for group post composer dialog. '
      'Last state: ${jsonEncode(lastRes)}',
    );
  }

  Future<String> _submitPostInComposer({
    required AutomationBrowserSession session,
    required String message,
    required List<Map<String, String>> imagesBase64,
    required bool dryRun,
    bool requireAnonymous = false,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    Map<String, dynamic> lastRes = const {};
    while (DateTime.now().isBefore(deadline)) {
      if (_stopRequested) throw Exception('Stopped by user');
      final res = _decodeJsMap(
        await session.evalJs(
          FbWebViewScripts.fillAndSubmitPost(
            message: message,
            imagesBase64: imagesBase64,
            dryRun: dryRun,
            requireAnonymous: requireAnonymous,
          ),
        ),
      );
      lastRes = res;
      final status = res['status'] as String? ?? '';
      if (status == 'dry_run_ok') return 'dry_run_ok';
      if (status == 'anonymous_unavailable') return 'anonymous_unavailable';
      if (status == 'error') {
        throw Exception(res['error'] ?? 'Unknown composer error');
      }
      if (status == 'submitted') {
        // Wait for dialog to close
        final closeDeadline = DateTime.now().add(const Duration(seconds: 15));
        while (DateTime.now().isBefore(closeDeadline)) {
          if (_stopRequested) return 'posted';
          final closedRaw = await session.evalJs(
            FbWebViewScripts.isComposerClosed(),
          );
          if (closedRaw.toString().contains('true')) {
            return 'posted';
          }
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        throw Exception(
          'Composer dialog stayed open after clicking Post; post may need review.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    throw Exception(
      'Submit button (Post/Publier/نشر) remained unavailable. '
      'Last state: ${jsonEncode(lastRes)}',
    );
  }

  Future<void> _waitCancellableDelay(double seconds) async {
    final wholeSeconds = seconds.ceil().clamp(0, 600);
    _appendLog('[INFO] Waiting ${seconds.toStringAsFixed(1)}s before next group...');
    _delayCompleter = Completer<void>();

    for (var remaining = wholeSeconds; remaining > 0; remaining--) {
      if (_stopRequested) break;
      _countdownSeconds = remaining;
      _statusMessage = 'Waiting ${remaining}s before next group...';
      notifyListeners();

      await Future.any([
        Future<void>.delayed(const Duration(seconds: 1)),
        _delayCompleter!.future,
      ]);
      if (_stopRequested) break;
    }
    _countdownSeconds = 0;
    _delayCompleter = null;
  }

  // ---------------------------------------------------------------------------
  // Python Bridge Automation Loop
  // ---------------------------------------------------------------------------

  Future<void> _runBridgeWorkflow(PostTemplate post) async {
    final baseUrl = _normalizedBridgeUrl();
    final encodedImages = await _encodePostImages(post.imagePaths);

    _appendLog('[INFO] Connecting to Python bridge at $baseUrl...');
    final startResp = await _http
        .post(
          Uri.parse('$baseUrl/start'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': _account.email,
            'password': _account.password,
            'message': post.message,
            'images_base64': encodedImages,
            'groups': _settings.groups,
            'anonymous': _settings.anonymous,
            'prefer_anonymous': _settings.preferAnonymous,
            'require_anonymous_if_available':
                _settings.requireAnonymousIfAvailable,
            'dry_run': _settings.dryRun,
            'delay_min': _settings.delayMin,
            'delay_max': _settings.delayMax,
          }),
        )
        .timeout(const Duration(seconds: 8));

    if (startResp.statusCode != 202 && startResp.statusCode != 200) {
      throw Exception(
        'Bridge refused start (${startResp.statusCode}): ${startResp.body}',
      );
    }

    _appendLog('[INFO] Bridge started fb_poster.py successfully.');
    var lastLogCount = 0;

    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final statusResp = await _http
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 6));
      if (statusResp.statusCode != 200) {
        throw Exception('Bridge /status returned HTTP ${statusResp.statusCode}');
      }

      final data = jsonDecode(statusResp.body) as Map<String, dynamic>;
      final bridgeLogs = (data['logs'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      if (bridgeLogs.length > lastLogCount) {
        for (final line in bridgeLogs.sublist(lastLogCount)) {
          _appendLog(line);
        }
        lastLogCount = bridgeLogs.length;
      }

      _currentGroupIndex = (data['current_index'] as num?)?.toInt() ?? 0;
      _totalGroups = (data['total_groups'] as num?)?.toInt() ?? _settings.groups.length;
      _currentGroupUrl = data['current_group'] as String? ?? '';
      _liveResults
        ..clear()
        ..addAll(
          (data['results'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(GroupRunResult.fromJson),
        );

      final stillRunning = data['running'] as bool? ?? false;
      _statusMessage = stillRunning
          ? 'Bridge posting ($_currentGroupIndex/$_totalGroups)...'
          : 'Bridge finished (${data['last_status'] ?? 'done'})';
      notifyListeners();

      if (!stillRunning) {
        final lastError = data['last_error'] as String?;
        if (lastError != null && lastError.isNotEmpty) {
          throw Exception(lastError);
        }
        break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<List<Map<String, String>>> _encodePostImages(List<String> paths) async {
    final result = <Map<String, String>>[];
    for (final p in paths) {
      final file = File(p);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final lower = p.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      result.add({
        'name': file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'image.jpg',
        'mimeType': mime,
        'data': base64Encode(bytes),
      });
    }
    return result;
  }

  String _normalizedBridgeUrl() {
    var url = _settings.bridgeUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  void _appendLog(String line) {
    _logs.add(line);
    if (_logs.length > 250) {
      _logs.removeAt(0);
    }
    notifyListeners();
  }

  Map<String, dynamic> _decodeJsMap(Object? raw) {
    if (raw == null) return const {};
    var str = raw.toString().trim();
    try {
      dynamic decoded = jsonDecode(str);
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // ignore malformed JS output
    }
    return const {};
  }

  RunOverallStatus _deriveOverallStatus({
    required List<GroupRunResult> results,
    required bool stopped,
    required bool dryRun,
  }) {
    if (stopped) return RunOverallStatus.stopped;
    if (results.any((r) => r.status == 'blocked')) return RunOverallStatus.blocked;
    if (results.any((r) => r.status == 'failed')) return RunOverallStatus.failed;
    if (dryRun) return RunOverallStatus.dryRun;
    return RunOverallStatus.completed;
  }

  DateTime _parseBridgeTimestamp(String filename) {
    // Expected: run_20261118T142749Z.json
    final match = RegExp(r'run_(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z')
        .firstMatch(filename);
    if (match != null) {
      return DateTime.utc(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    }
    return DateTime.now().toUtc();
  }

  @override
  void dispose() {
    _desktopDriver?.dispose();
    _http.close();
    super.dispose();
  }
}
