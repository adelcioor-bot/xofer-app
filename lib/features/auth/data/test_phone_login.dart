class TestPhoneLogin {
  const TestPhoneLogin._();

  static const localDigits = '4141994141';
  static const storedDigits = '554141994141';
  static const driverLocalDigits = '4141004141';
  static const driverStoredDigits = '554141004141';
  static const courierLocalDigits = '4141014141';
  static const courierStoredDigits = '554141014141';

  static const _canonical = <String, String>{
    localDigits: storedDigits,
    storedDigits: storedDigits,
    driverLocalDigits: driverStoredDigits,
    driverStoredDigits: driverStoredDigits,
    courierLocalDigits: courierStoredDigits,
    courierStoredDigits: courierStoredDigits,
  };

  static String? canonical(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    return _canonical[digits];
  }

  static bool matches(String phoneNumber) => canonical(phoneNumber) != null;
}
