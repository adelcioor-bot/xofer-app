abstract class AuthRepository {
  Future<void> sendOtp(String phoneNumber);

  Future<void> verifyOtp({required String phoneNumber, required String code});

  Future<void> signOut();

  String? get currentPhone => null;

  /// Número de teste da sessão autenticada, quando aplicável.
  String? get testPhone => null;
}
