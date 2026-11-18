/// Stored Facebook account credentials used when Facebook prompts for sign-in.
class FbAccount {
  const FbAccount({
    this.email = '',
    this.password = '',
  });

  final String email;
  final String password;

  bool get hasCredentials => email.trim().isNotEmpty && password.isNotEmpty;

  String get maskedEmail {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Not configured';
    final atIndex = trimmed.indexOf('@');
    if (atIndex <= 2) return trimmed;
    return '${trimmed.substring(0, 2)}***${trimmed.substring(atIndex)}';
  }

  FbAccount copyWith({
    String? email,
    String? password,
  }) {
    return FbAccount(
      email: email ?? this.email,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };

  factory FbAccount.fromJson(Map<String, dynamic> json) => FbAccount(
        email: (json['email'] as String? ?? '').trim(),
        password: json['password'] as String? ?? '',
      );
}
