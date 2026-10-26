class ProfileFailure implements Exception {
  const ProfileFailure(this.message);

  final String message;

  bool get isDuplicateKey {
    final normalized = message.toLowerCase();
    return normalized.contains('duplicate key') ||
        normalized.contains('unique constraint') ||
        normalized.contains('23505');
  }

  @override
  String toString() => message;
}
