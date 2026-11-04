import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/features/merchant/domain/cnpj.dart';

void main() {
  test('validates CNPJ check digits', () {
    expect(Cnpj.isValid('11.222.333/0001-81'), isTrue);
    expect(Cnpj.isValid('11.222.333/0001-80'), isFalse);
    expect(Cnpj.isValid('00.000.000/0000-00'), isFalse);
  });
}
