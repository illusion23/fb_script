/// Validates and normalizes Facebook group URLs identically to fb_poster.py.
class GroupUrlValidator {
  static final RegExp _groupUrlPattern = RegExp(
    r'^https?://(www\.|m\.|mbasic\.)?facebook\.com/groups/[^/?#]+/?',
  );

  /// Normalizes [rawUrl] to `https://www.facebook.com/groups/<slug_or_id>/`.
  /// Throws [FormatException] if the URL is invalid or a placeholder.
  static String normalize(String rawUrl) {
    final url = rawUrl.trim();
    if (!_groupUrlPattern.hasMatch(url)) {
      throw FormatException(
        'Invalid Facebook group URL: "$rawUrl". '
        'Expected https://www.facebook.com/groups/<group_id_or_slug>/',
      );
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw FormatException('Could not parse URL: "$rawUrl"');
    }
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (parts.length < 2 || parts[0] != 'groups') {
      throw FormatException('Invalid Facebook group path in URL: "$rawUrl"');
    }
    if (parts[1].startsWith('YOUR_GROUP_ID')) {
      throw FormatException(
        'Placeholder group URL must be replaced with a real group URL: "$rawUrl"',
      );
    }
    return 'https://www.facebook.com/groups/${parts[1]}/';
  }

  /// Parses newline- or comma-separated group URLs, normalizing and deduplicating.
  static List<String> parseMany(String rawInput) {
    final seen = <String>{};
    final result = <String>[];
    final tokens = rawInput
        .split(RegExp(r'[\n,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    for (final token in tokens) {
      final normalized = normalize(token);
      if (seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }
}
