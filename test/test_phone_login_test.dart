import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/features/auth/data/test_phone_login.dart';

void main() {
  test('reconhece os telefones de teste com ou sem DDI', () {
    expect(TestPhoneLogin.matches('4141994141'), isTrue);
    expect(TestPhoneLogin.matches('+55 (41) 4199-4141'), isTrue);
    expect(TestPhoneLogin.matches('4141004141'), isTrue);
    expect(TestPhoneLogin.matches('4141014141'), isTrue);
    expect(
      TestPhoneLogin.canonical('4141004141'),
      TestPhoneLogin.driverStoredDigits,
    );
    expect(
      TestPhoneLogin.canonical('4141014141'),
      TestPhoneLogin.courierStoredDigits,
    );
    expect(TestPhoneLogin.matches('+5511988887777'), isFalse);
  });
}
