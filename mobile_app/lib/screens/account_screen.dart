import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/fb_account.dart';
import '../services/poster_runner.dart';
import '../widgets/live_webview_sheet.dart';

/// Side-menu screen for setting Facebook Email & Password, interactive 2FA
/// browser login, and optional Python bridge server configuration.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.controller});

  final AppStateController controller;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _bridgeUrlController;
  bool _obscurePassword = true;
  bool _testingBridge = false;

  @override
  void initState() {
    super.initState();
    _emailController =
        TextEditingController(text: widget.controller.account.email);
    _passwordController =
        TextEditingController(text: widget.controller.account.password);
    _bridgeUrlController =
        TextEditingController(text: widget.controller.settings.bridgeUrl);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _bridgeUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.controller.saveAccount(
      FbAccount(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
    final bridge = _bridgeUrlController.text.trim();
    if (bridge.isNotEmpty) {
      await widget.controller.updateSettings(
        widget.controller.settings.copyWith(bridgeUrl: bridge),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Facebook account settings saved.')),
    );
  }

  Future<void> _clear() async {
    _emailController.clear();
    _passwordController.clear();
    await widget.controller.clearAccount();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved Facebook credentials cleared.')),
    );
  }

  Future<void> _interactiveLogin() async {
    try {
      await widget.controller.openInteractiveLoginPage();
      if (!mounted) return;
      if (widget.controller.isWebViewSupported) {
        await LiveWebViewSheet.show(context, widget.controller);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opened interactive Facebook login via Python Bridge.'),
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login error: $err'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _testBridge() async {
    var base = _bridgeUrlController.text.trim();
    if (base.isEmpty) return;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    setState(() => _testingBridge = true);
    try {
      final resp = await http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        await widget.controller.updateSettings(
          widget.controller.settings.copyWith(bridgeUrl: base),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bridge connected and saved.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bridge responded HTTP ${resp.statusCode}.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not reach bridge: $err'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _testingBridge = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasCreds = widget.controller.account.hasCredentials;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        // Status Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (hasCreds ? Colors.green : Colors.orange)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (hasCreds ? Colors.green : Colors.orange)
                  .withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasCreds
                    ? Icons.verified_user_rounded
                    : Icons.account_circle_outlined,
                color: hasCreds ? Colors.green.shade700 : Colors.orange.shade800,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasCreds
                          ? 'Credentials Configured'
                          : 'No Account Saved Yet',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      hasCreds
                          ? widget.controller.account.maskedEmail
                          : 'Enter your Facebook email & password below or use interactive 2FA sign-in.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Credentials Form Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_person_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Facebook Account Credentials',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Stored locally on this device and filled automatically if Facebook prompts for login.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('fb_email_field'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Facebook Email or Phone',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      final trimmed = (value ?? '').trim();
                      final pass = _passwordController.text;
                      if (pass.isNotEmpty && trimmed.isEmpty) {
                        return 'Please enter your Facebook email or phone';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('fb_password_field'),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Facebook Password',
                      prefixIcon: const Icon(Icons.password_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('save_account_button'),
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save Account'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _clear,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2FA Interactive Login Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '2FA / Manual Session Sign-In',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Recommended if your account uses 2-factor authentication. Sign in once in the browser to keep cookies active.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _interactiveLogin,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.login),
                  label: const Text('Open Interactive Facebook Login'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Optional Bridge Server Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Python Bridge Server (Optional)',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Point to bridge_server.py on your PC if running Playwright remotely (e.g. http://192.168.1.10:8765).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bridgeUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Bridge Server URL',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testingBridge ? null : _testBridge,
                      icon: _testingBridge
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('Test & Save'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _save,
                      child: const Text('Save URL'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
