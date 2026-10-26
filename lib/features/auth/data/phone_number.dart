class PhoneNumber {
  const PhoneNumber._();

  static String normalize(String input, {required String countryCode}) {
    final trimmed = input.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');

    if (trimmed.startsWith('+')) {
      return '+$digits';
    }

    final prefixDigits = countryCode.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith(prefixDigits)) {
      return '+$digits';
    }

    return '$countryCode$digits';
  }

  static bool isValid(String e164PhoneNumber) {
    final digits = e164PhoneNumber.replaceAll(RegExp(r'\D'), '');
    return e164PhoneNumber.startsWith('+') && digits.length >= 10;
  }
}
