import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/app_settings.dart';
import '../services/poster_runner.dart';
import '../utils/compat_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/live_webview_sheet.dart';

/// Minimalist centered runner homepage with a circular progress dial and
/// Start / Stop controls in the middle. All configuration screens live in the
/// side menu.
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
  Future<void> _handleStart() async {
    try {
      await widget.controller.startScript();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.toString()),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Setup',
            textColor: Colors.white,
            onPressed: () {
              if (widget.controller.defaultPost == null) {
                widget.onNavigate(AppSection.posts);
              } else if (widget.controller.settings.groups.isEmpty) {
                widget.onNavigate(AppSection.groups);
              }
            },
          ),
        ),
      );
    }
  }

  void _showLogsSheet(BuildContext context) {
    final ctrl = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ListenableBuilder(
        listenable: ctrl,
        builder: (ctx, _) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.terminal_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Execution Logs',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (ctrl.logs.isNotEmpty)
                      IconButton(
                        tooltip: 'Copy logs',
                        icon: const Icon(Icons.copy_all_outlined),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: ctrl.logs.join('\n')),
                          );
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Logs copied.')),
                          );
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ctrl.logs.isEmpty
                    ? const Center(
                        child: Text('No logs yet. Press Start to begin.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(14),
                        reverse: true,
                        itemCount: ctrl.logs.length,
                        itemBuilder: (_, idx) {
                          final line = ctrl.logs[ctrl.logs.length - 1 - idx];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: SelectableText(
                              line,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final settings = ctrl.settings;
    final defaultPost = ctrl.defaultPost;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final total =
        ctrl.isRunning ? ctrl.totalGroups : settings.groups.length;
    final current = ctrl.isRunning ? ctrl.currentGroupIndex : 0;
    final progress = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;

    final centerValue = ctrl.countdownSeconds > 0
        ? '${ctrl.countdownSeconds}s'
        : total > 0
            ? '$current / $total'
            : (ctrl.isRunning ? '...' : 'READY');

    final centerSubtitle = ctrl.isStopping
        ? 'STOPPING'
        : ctrl.countdownSeconds > 0
            ? 'WAITING NEXT'
            : ctrl.isRunning
                ? 'POSTING'
                : ctrl.statusMessage.toUpperCase();

    final summaryText = [
      defaultPost != null ? defaultPost.title : 'No Post',
      '${settings.groups.length} group(s)',
      switch (settings.anonymousPolicy) {
        AnonymousPolicy.preferAnonymous => 'Auto Anon',
        AnonymousPolicy.strictAnonymous => 'Strict Anon',
        AnonymousPolicy.publicOnly => 'Public',
      },
    ].join('  •  ');

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - 32),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Subtle quick-status pill at top
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () {
                    if (defaultPost == null) {
                      widget.onNavigate(AppSection.posts);
                    } else if (settings.groups.isEmpty) {
                      widget.onNavigate(AppSection.groups);
                    } else {
                      widget.onNavigate(AppSection.options);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorWithOpacity(
                        surfaceContainerHighestCompat(scheme),
                        isDark ? 0.45 : 0.7,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: colorWithOpacity(scheme.outlineVariant, 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (defaultPost != null &&
                                    settings.groups.isNotEmpty)
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            summaryText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Centered Circular Dial Control
                SizedBox(
                  width: 236,
                  height: 236,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(236, 236),
                        painter: _DialRingPainter(
                          progress: ctrl.isRunning
                              ? (progress == 0 ? 0.12 : progress)
                              : (defaultPost != null &&
                                      settings.groups.isNotEmpty
                                  ? 1.0
                                  : 0.0),
                          isRunning: ctrl.isRunning,
                          trackColor: isDark
                              ? const Color(0xFF2B2E45)
                              : surfaceContainerHighestCompat(scheme),
                          startColor: const Color(0xFF7B61FF),
                          endColor: const Color(0xFF1877F2),
                        ),
                      ),
                      Container(
                        width: 162,
                        height: 162,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF23263A)
                              : Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: colorWithOpacity(
                                Colors.black,
                                isDark ? 0.35 : 0.08,
                              ),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              centerValue,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              centerSubtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.1,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Centered Start & Stop Controls
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('start_script_button'),
                          onPressed: ctrl.isRunning ? null : _handleStart,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
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
                      const SizedBox(width: 14),
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('stop_script_button'),
                          onPressed: ctrl.isRunning && !ctrl.isStopping
                              ? ctrl.stopScript
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
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
                ),
                const SizedBox(height: 18),

                // Quiet footer shortcuts for Logs & Live Browser
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showLogsSheet(context),
                      icon: const Icon(Icons.terminal_rounded, size: 18),
                      label: Text(
                        ctrl.logs.isEmpty
                            ? 'Logs'
                            : 'Logs (${ctrl.logs.length})',
                      ),
                    ),
                    if (ctrl.isWebViewSupported)
                      TextButton.icon(
                        onPressed: () => LiveWebViewSheet.show(context, ctrl),
                        icon: const Icon(Icons.public, size: 18),
                        label: const Text('Browser'),
                      ),
                  ],
                ),

                if (ctrl.needsManualAuth &&
                    (ctrl.isWebViewSupported ||
                        settings.executionMode ==
                            ExecutionMode.desktopBrowser)) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await ctrl.openInteractiveLoginPage();
                      if (context.mounted &&
                          ctrl.isWebViewSupported &&
                          settings.executionMode == ExecutionMode.webView) {
                        await LiveWebViewSheet.show(context, ctrl);
                      }
                    },
                    icon: const Icon(Icons.security),
                    label: const Text('Complete Facebook Login / 2FA'),
                  ),
                ],

                // Keep Android WebView mounted with non-zero layout bounds while active.
                if (ctrl.isWebViewSupported &&
                    ctrl.webViewController != null &&
                    ((ctrl.isRunning &&
                            settings.executionMode == ExecutionMode.webView) ||
                        ctrl.needsManualAuth)) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: WebViewWidget(controller: ctrl.webViewController!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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

class _DialRingPainter extends CustomPainter {
  _DialRingPainter({
    required this.progress,
    required this.isRunning,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
  });

  final double progress;
  final bool isRunning;
  final Color trackColor;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 16;
    const strokeWidth = 10.0;

    // Outer soft aura ring
    final auraPaint = Paint()
      ..color = colorWithOpacity(trackColor, 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22;
    canvas.drawCircle(center, radius, auraPaint);

    // Base circular track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final glowPaint = Paint()
      ..color = colorWithOpacity(startColor, isRunning ? 0.45 : 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);

    final arcPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [startColor, endColor, startColor],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle, false, arcPaint);

    // Glowing indicator dot at the tip of the arc
    final tipAngle = startAngle + sweepAngle;
    final tipOffset = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    canvas.drawCircle(
      tipOffset,
      8,
      Paint()..color = colorWithOpacity(startColor, 0.45),
    );
    canvas.drawCircle(
      tipOffset,
      4.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _DialRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isRunning != isRunning ||
        oldDelegate.trackColor != trackColor;
  }
}
