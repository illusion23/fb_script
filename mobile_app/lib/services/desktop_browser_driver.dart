import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Minimal abstraction for a scriptable browser session shared by both
/// mobile WebView and desktop Chrome DevTools Protocol (CDP) automation.
abstract class AutomationBrowserSession {
  Future<void> navigateAndWait(String url);
  Future<Object?> evalJs(String script);
}

/// Pure-Dart Chrome DevTools Protocol (CDP) driver for Windows (7 SP1 / 10 / 11),
/// Linux, and macOS. Launches the user's installed Chromium-based browser
/// (Chrome, Edge, Supermium, Brave, Chromium, Vivaldi, Opera) with an isolated
/// persistent profile so Facebook login/2FA cookies are preserved with zero Python
/// or Playwright installation required.
class DesktopBrowserDriver implements AutomationBrowserSession {
  DesktopBrowserDriver({
    this.customBrowserPath = '',
    this.profileDirectoryOverride,
    this.defaultSettleDelay = const Duration(seconds: 3),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String customBrowserPath;
  final String? profileDirectoryOverride;
  final Duration defaultSettleDelay;
  final http.Client _http;

  Process? _process;
  int? _debugPort;
  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  int _nextCommandId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  Completer<void>? _loadEventCompleter;

  bool get isConnected => _ws != null && _ws!.readyState == WebSocket.open;

  /// Locate an installed Chromium-based browser executable on the current OS.
  static String? findBrowserExecutable({String customPath = ''}) {
    final trimmedCustom = customPath.trim().replaceAll('"', '');
    if (trimmedCustom.isNotEmpty && File(trimmedCustom).existsSync()) {
      return trimmedCustom;
    }

    final candidates = <String>[];
    if (Platform.isWindows) {
      final env = Platform.environment;
      final pf = env['PROGRAMFILES'] ?? r'C:\Program Files';
      final pf86 = env['PROGRAMFILES(X86)'] ?? r'C:\Program Files (x86)';
      final localAppData = env['LOCALAPPDATA'] ?? '';

      final roots = <String>[
        pf,
        pf86,
        if (localAppData.isNotEmpty) localAppData,
      ];

      final relPaths = <String>[
        r'Google\Chrome\Application\chrome.exe',
        r'Microsoft\Edge\Application\msedge.exe',
        // Popular modern Chromium build actively maintained for Windows 7 SP1.
        r'Supermium\Application\chrome.exe',
        r'BraveSoftware\Brave-Browser\Application\brave.exe',
        r'Chromium\Application\chrome.exe',
        r'Vivaldi\Application\vivaldi.exe',
        r'Programs\Opera\opera.exe',
        r'Opera\opera.exe',
      ];

      for (final rel in relPaths) {
        for (final root in roots) {
          candidates.add('$root\\$rel');
        }
      }
    } else if (Platform.isLinux) {
      candidates.addAll(const [
        '/usr/bin/google-chrome',
        '/usr/bin/google-chrome-stable',
        '/usr/bin/chromium',
        '/usr/bin/chromium-browser',
        '/snap/bin/chromium',
        '/usr/bin/microsoft-edge',
        '/usr/bin/brave-browser',
      ]);
    } else if (Platform.isMacOS) {
      candidates.addAll(const [
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
        '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
      ]);
    }

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// Resolve the persistent browser profile directory where Facebook session
  /// cookies and 2FA trust state are stored across runs.
  static String resolveProfileDirectory({String? override}) {
    if (override != null && override.trim().isNotEmpty) {
      return override.trim();
    }
    final env = Platform.environment;
    if (Platform.isWindows) {
      final base = env['APPDATA'] ??
          env['LOCALAPPDATA'] ??
          Directory.systemTemp.path;
      return '$base\\FBGroupPoster\\chrome_profile';
    }
    final home = env['HOME'] ?? Directory.systemTemp.path;
    return '$home/.fb_group_poster/chrome_profile';
  }

  /// Attach directly to an already-running CDP WebSocket URL (useful for tests
  /// or re-attaching to a running browser target).
  Future<void> attachToWebSocket(String wsUrl) async {
    await _detachSocket();
    final socket = await WebSocket.connect(wsUrl)
        .timeout(const Duration(seconds: 10));
    _ws = socket;
    _wsSub = socket.listen(
      _handleSocketMessage,
      onDone: _handleSocketClosed,
      onError: (_) => _handleSocketClosed(),
      cancelOnError: true,
    );
    await sendCommand('Page.enable');
    await sendCommand('Runtime.enable');
  }

  /// Ensure a desktop browser window is running and connected over CDP.
  Future<void> ensureConnected({
    void Function(String log)? onLog,
  }) async {
    if (isConnected) {
      try {
        await sendCommand(
          'Runtime.evaluate',
          {'expression': '1', 'returnByValue': true},
          const Duration(seconds: 3),
        );
        return;
      } catch (_) {
        await _detachSocket();
      }
    }

    // If our process is still alive on _debugPort, try re-attaching to a tab.
    if (_debugPort != null) {
      final wsUrl = await _fetchPageWebSocketUrl(_debugPort!);
      if (wsUrl != null) {
        await attachToWebSocket(wsUrl);
        return;
      }
    }

    final executable = findBrowserExecutable(customPath: customBrowserPath);
    if (executable == null) {
      throw StateError(
        'No Chromium-based browser (Google Chrome, Microsoft Edge, Supermium, '
        'or Brave) was found on this PC. Install Chrome/Edge (or Supermium on '
        'Windows 7) or set a custom browser path in Script Options.',
      );
    }

    final profileDir =
        resolveProfileDirectory(override: profileDirectoryOverride);
    Directory(profileDir).createSync(recursive: true);

    final port = await _findFreePort();
    onLog?.call('[INFO] Launching desktop browser: $executable');

    final args = <String>[
      '--remote-debugging-port=$port',
      // Required by Chrome 111+; harmlessly ignored by Chrome 109 on Windows 7.
      '--remote-allow-origins=*',
      '--user-data-dir=$profileDir',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-notifications',
      '--window-size=1280,900',
      'about:blank',
    ];

    _process = await Process.start(
      executable,
      args,
      mode: ProcessStartMode.normal,
    );
    _debugPort = port;

    // Drain stdio so the child process never blocks on full OS pipes.
    _process!.stdout.drain<void>();
    _process!.stderr.drain<void>();

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    String? wsUrl;
    while (DateTime.now().isBefore(deadline)) {
      wsUrl = await _fetchPageWebSocketUrl(port);
      if (wsUrl != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    if (wsUrl == null) {
      await close();
      throw StateError(
        'Browser started but Chrome DevTools Protocol did not respond on '
        'port $port within 20 seconds. Close any stuck browser instance using '
        'the same profile and try again.',
      );
    }

    await attachToWebSocket(wsUrl);
    onLog?.call('[INFO] Connected to desktop browser (CDP port $port).');
  }

  /// Open a visible browser window directly to Facebook so the user can sign in
  /// or finish 2FA interactively. The browser stays open for subsequent runs.
  Future<void> openInteractiveLogin({void Function(String log)? onLog}) async {
    await ensureConnected(onLog: onLog);
    await sendCommand('Page.bringToFront').catchError((_) => <String, dynamic>{});
    await sendCommand('Page.navigate', {'url': 'https://www.facebook.com/'});
  }

  @override
  Future<void> navigateAndWait(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    Duration? settleDelay,
  }) async {
    if (!isConnected) {
      await ensureConnected();
    }
    _loadEventCompleter = Completer<void>();
    await sendCommand('Page.navigate', {'url': url});
    await _loadEventCompleter!.future.timeout(timeout, onTimeout: () {});
    _loadEventCompleter = null;
    final delay = settleDelay ?? defaultSettleDelay;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }

  @override
  Future<Object?> evalJs(String script) async {
    if (!isConnected) {
      throw StateError('Desktop browser session is not connected.');
    }
    final result = await sendCommand(
      'Runtime.evaluate',
      {
        'expression': script,
        'returnByValue': true,
        'userGesture': true,
      },
    );
    if (result['exceptionDetails'] != null) {
      final details = result['exceptionDetails'];
      throw StateError('Browser JS exception: $details');
    }
    final remoteObj = result['result'];
    if (remoteObj is Map<String, dynamic>) {
      return remoteObj['value'];
    }
    return null;
  }

  /// Send a raw Chrome DevTools Protocol JSON-RPC command and await its result.
  Future<Map<String, dynamic>> sendCommand(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  ]) async {
    final socket = _ws;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('CDP WebSocket is not open.');
    }
    final id = _nextCommandId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final payload = <String, dynamic>{
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };
    socket.add(jsonEncode(payload));

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('CDP command "$method" timed out.');
      },
    );
  }

  /// Gracefully ask Chrome to flush cookies and exit, then clean up handles.
  Future<void> close({bool terminateBrowser = true}) async {
    if (terminateBrowser && isConnected) {
      try {
        await sendCommand(
          'Browser.close',
          null,
          const Duration(seconds: 3),
        );
      } catch (_) {
        // Fallback to process termination below if Browser.close fails.
      }
    }
    await _detachSocket();

    final proc = _process;
    _process = null;
    _debugPort = null;

    if (terminateBrowser && proc != null) {
      try {
        await proc.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        proc.kill();
      }
    }
  }

  void dispose() {
    _detachSocket();
    _http.close();
  }

  Future<void> _detachSocket() async {
    await _wsSub?.cancel();
    _wsSub = null;
    final socket = _ws;
    _ws = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _failPending('CDP socket closed');
  }

  void _handleSocketMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return;
    }

    final id = msg['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        if (msg['error'] != null) {
          completer.completeError(
            StateError('CDP error: ${jsonEncode(msg['error'])}'),
          );
        } else {
          final res = msg['result'];
          completer.complete(
            res is Map<String, dynamic> ? res : <String, dynamic>{},
          );
        }
      }
      return;
    }

    final method = msg['method'];
    if (method == 'Page.loadEventFired' ||
        method == 'Page.frameStoppedLoading') {
      if (_loadEventCompleter != null && !_loadEventCompleter!.isCompleted) {
        _loadEventCompleter!.complete();
      }
    }
  }

  void _handleSocketClosed() {
    _ws = null;
    _wsSub = null;
    if (_loadEventCompleter != null && !_loadEventCompleter!.isCompleted) {
      _loadEventCompleter!.complete();
    }
    _failPending('Desktop browser window was closed.');
  }

  void _failPending(String reason) {
    final entries = _pending.values.toList();
    _pending.clear();
    for (final c in entries) {
      if (!c.isCompleted) {
        c.completeError(StateError(reason));
      }
    }
  }

  Future<String?> _fetchPageWebSocketUrl(int port) async {
    try {
      final listUri = Uri.parse('http://127.0.0.1:$port/json/list');
      final resp =
          await _http.get(listUri).timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic> &&
                item['type'] == 'page' &&
                item['webSocketDebuggerUrl'] is String) {
              return item['webSocketDebuggerUrl'] as String;
            }
          }
        }
      }

      // If no page tab exists yet, ask Chrome to create one.
      final newUri = Uri.parse('http://127.0.0.1:$port/json/new?about:blank');
      http.Response newResp;
      try {
        newResp = await _http.put(newUri).timeout(const Duration(seconds: 2));
        if (newResp.statusCode == 405) {
          newResp = await _http.get(newUri).timeout(const Duration(seconds: 2));
        }
      } catch (_) {
        newResp = await _http.get(newUri).timeout(const Duration(seconds: 2));
      }
      if (newResp.statusCode == 200) {
        final target = jsonDecode(newResp.body);
        if (target is Map<String, dynamic> &&
            target['webSocketDebuggerUrl'] is String) {
          return target['webSocketDebuggerUrl'] as String;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}
