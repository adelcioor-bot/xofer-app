class UserProfile {
  const UserProfile({
    required this.id,
    this.fullName,
    this.document,
    this.phone,
  });

  final String id;
  final String? fullName;
  final String? document;
  final String? phone;

  bool get isComplete {
    final name = fullName?.trim() ?? '';
    final doc = document?.trim() ?? '';
    return name.isNotEmpty && doc.isNotEmpty;
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      fullName: map['full_name'] as String?,
      document: map['document'] as String?,
      phone: map['phone'] as String?,
    );
  }
}
