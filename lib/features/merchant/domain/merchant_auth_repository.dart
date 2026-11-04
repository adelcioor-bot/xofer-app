abstract interface class MerchantAuthRepository {
  Future<void> signIn({required String identifier, required String password});

  Future<bool> signUp({
    required String businessName,
    required String email,
    required String document,
    required String phone,
    required String password,
  });

  Future<void> resetPassword(String email);
}
