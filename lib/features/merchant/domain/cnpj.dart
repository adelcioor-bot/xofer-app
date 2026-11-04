class Cnpj {
  const Cnpj._();

  static String digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

  static bool isValid(String input) {
    final digits = digitsOnly(input);
    if (digits.length != 14 || RegExp(r'^(\d)\1{13}$').hasMatch(digits)) {
      return false;
    }

    final firstDigit = _checkDigit(digits.substring(0, 12), const [
      5,
      4,
      3,
      2,
      9,
      8,
      7,
      6,
      5,
      4,
      3,
      2,
    ]);
    if (firstDigit != int.parse(digits[12])) return false;

    final secondDigit = _checkDigit(digits.substring(0, 13), const [
      6,
      5,
      4,
      3,
      2,
      9,
      8,
      7,
      6,
      5,
      4,
      3,
      2,
    ]);
    return secondDigit == int.parse(digits[13]);
  }

  static int _checkDigit(String digits, List<int> weights) {
    var sum = 0;
    for (var index = 0; index < weights.length; index++) {
      sum += int.parse(digits[index]) * weights[index];
    }
    final remainder = sum % 11;
    return remainder < 2 ? 0 : 11 - remainder;
  }
}
