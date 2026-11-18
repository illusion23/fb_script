import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/poster_runner.dart';

/// Displays the live embedded WebView on Android/iOS so the user can watch
/// automated group posting or complete 2FA / security checkpoints interactively.
class LiveWebViewSheet extends StatelessWidget {
  const LiveWebViewSheet({
    super.key,
    required this.controller,
  });

  final AppStateController controller;

  static Future<void> show(
    BuildContext context,
    AppStateController controller,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: LiveWebViewSheet(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.isWebViewSupported) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.desktop_windows, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Embedded mobile WebView is available on Android and iOS devices.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    final webController = controller.ensureWebViewController();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.public, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Facebook Browser Session',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'Reload',
                icon: const Icon(Icons.refresh),
                onPressed: () => webController.reload(),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: WebViewWidget(controller: webController),
        ),
      ],
    );
  }
}
