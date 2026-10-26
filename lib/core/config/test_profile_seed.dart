class TestProfileSeed {
  const TestProfileSeed({
    required this.phoneDigits,
    required this.fullName,
    required this.document,
    required this.phone,
  });

  final String phoneDigits;
  final String fullName;
  final String document;
  final String phone;

  bool matchesPhone(String? phoneNumber) {
    if (phoneNumber == null) return false;
    return phoneNumber.replaceAll(RegExp(r'\D'), '') == phoneDigits;
  }
}
