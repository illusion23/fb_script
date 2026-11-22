import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/fb_account.dart';
import '../models/post_template.dart';
import '../models/run_history.dart';

/// Persists account credentials, post templates, default post selection,
/// group/run settings, and execution history using SharedPreferences.
class StorageService {
  StorageService(this._prefs);

  static const _keyAccount = 'fb_poster.account';
  static const _keyPosts = 'fb_poster.posts';
  static const _keyDefaultPostId = 'fb_poster.default_post_id';
  static const _keySettings = 'fb_poster.settings';
  static const _keyHistory = 'fb_poster.history';
  static const _keyDefaultGroupsSeeded = 'fb_poster.default_groups_v1_seeded';

  final SharedPreferences _prefs;

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  FbAccount loadAccount() {
    final raw = _prefs.getString(_keyAccount);
    if (raw == null || raw.isEmpty) return const FbAccount();
    try {
      return FbAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const FbAccount();
    }
  }

  Future<void> saveAccount(FbAccount account) async {
    await _prefs.setString(_keyAccount, jsonEncode(account.toJson()));
  }

  List<PostTemplate> loadPosts() {
    final raw = _prefs.getString(_keyPosts);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(PostTemplate.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePosts(List<PostTemplate> posts) async {
    await _prefs.setString(
      _keyPosts,
      jsonEncode(posts.map((p) => p.toJson()).toList()),
    );
  }

  String? loadDefaultPostId() => _prefs.getString(_keyDefaultPostId);

  Future<void> saveDefaultPostId(String? postId) async {
    if (postId == null || postId.isEmpty) {
      await _prefs.remove(_keyDefaultPostId);
    } else {
      await _prefs.setString(_keyDefaultPostId, postId);
    }
  }

  AppSettings loadSettings() {
    final raw = _prefs.getString(_keySettings);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setString(_keySettings, jsonEncode(settings.toJson()));
  }

  bool hasSeededDefaultGroups() =>
      _prefs.getBool(_keyDefaultGroupsSeeded) ?? false;

  Future<void> markDefaultGroupsSeeded() async {
    await _prefs.setBool(_keyDefaultGroupsSeeded, true);
  }

  List<RunHistoryEntry> loadHistory() {
    final raw = _prefs.getString(_keyHistory);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(RunHistoryEntry.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveHistory(List<RunHistoryEntry> entries) async {
    final trimmed = entries.take(100).toList();
    await _prefs.setString(
      _keyHistory,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }
}
