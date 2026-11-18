/// A reusable Facebook group post template (message + optional images).
class PostTemplate {
  const PostTemplate({
    required this.id,
    required this.title,
    required this.message,
    this.imagePaths = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String message;
  final List<String> imagePaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isValid => message.trim().isNotEmpty || imagePaths.isNotEmpty;

  PostTemplate copyWith({
    String? id,
    String? title,
    String? message,
    List<String>? imagePaths,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostTemplate(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      imagePaths: imagePaths ?? this.imagePaths,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'imagePaths': imagePaths,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PostTemplate.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    return PostTemplate(
      id: json['id'] as String? ?? now.microsecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? 'Untitled Post',
      message: json['message'] as String? ?? '',
      imagePaths: (json['imagePaths'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }
}
