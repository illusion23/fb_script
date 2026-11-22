import 'package:flutter/material.dart';

import 'screens/account_screen.dart';
import 'screens/groups_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/options_screen.dart';
import 'screens/posts_screen.dart';
import 'services/poster_runner.dart';
import 'services/storage_service.dart';
import 'utils/compat_theme.dart';
import 'widgets/app_drawer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await StorageService.create();
  final controller = AppStateController(storage)..init();
  runApp(FbGroupPosterApp(controller: controller));
}

class FbGroupPosterApp extends StatelessWidget {
  const FbGroupPosterApp({super.key, required this.controller});

  final AppStateController controller;

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1877F2),
      brightness: brightness,
    );
    final isLight = brightness == Brightness.light;
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor:
          isLight ? const Color(0xFFF4F6FA) : colorScheme.surface,
      cardColor: isLight ? Colors.white : surfaceContainerLowCompat(colorScheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 1,
        backgroundColor:
            isLight ? Colors.white : surfaceContainerLowCompat(colorScheme),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? const Color(0xFFF8FAFC)
            : colorWithOpacity(
                surfaceContainerHighestCompat(colorScheme),
                0.4,
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: colorWithOpacity(colorScheme.outlineVariant, 0.8),
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FB Group Poster',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: MainShell(controller: controller),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.controller});

  final AppStateController controller;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  AppSection _section = AppSection.home;

  String get _title => switch (_section) {
        AppSection.home => 'FB Group Poster',
        AppSection.account => 'FB Account',
        AppSection.posts => 'Default Post',
        AppSection.groups => 'Target Groups',
        AppSection.options => 'Script Options',
        AppSection.history => 'Script History',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_title),
            actions: [
              if (_section != AppSection.home && widget.controller.isRunning)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Running'),
                    onPressed: () =>
                        setState(() => _section = AppSection.home),
                  ),
                ),
            ],
          ),
          drawer: AppDrawer(
            currentSection: _section,
            controller: widget.controller,
            onSelectSection: (section) => setState(() => _section = section),
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey(_section),
              child: switch (_section) {
                AppSection.home => HomeScreen(
                    controller: widget.controller,
                    onNavigate: (s) => setState(() => _section = s),
                  ),
                AppSection.account =>
                  AccountScreen(controller: widget.controller),
                AppSection.posts => PostsScreen(controller: widget.controller),
                AppSection.groups =>
                  GroupsScreen(controller: widget.controller),
                AppSection.options =>
                  OptionsScreen(controller: widget.controller),
                AppSection.history =>
                  HistoryScreen(controller: widget.controller),
              },
            ),
          ),
        );
      },
    );
  }
}
