import 'user_profile.dart';

abstract class ProfileRepository {
  Future<UserProfile?> fetchCurrent();

  Future<UserProfile> save({
    required String fullName,
    required String document,
    String? phone,
  });
}
