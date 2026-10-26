import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/features/profile/data/cpf.dart';
import 'package:xofer/features/profile/domain/user_profile.dart';

void main() {
  test('valida CPF verdadeiro e rejeita sequências', () {
    expect(Cpf.isValid('529.982.247-25'), isTrue);
    expect(Cpf.isValid('52998224725'), isTrue);
    expect(Cpf.isValid('11111111111'), isFalse);
    expect(Cpf.isValid('123'), isFalse);
  });

  test('perfil só está completo com nome e documento', () {
    expect(const UserProfile(id: '1').isComplete, isFalse);
    expect(
      const UserProfile(id: '1', fullName: 'Ana').isComplete,
      isFalse,
    );
    expect(
      const UserProfile(
        id: '1',
        fullName: 'Ana Costa',
        document: '52998224725',
      ).isComplete,
      isTrue,
    );
  });
}
