import 'merchant_profile.dart';

abstract interface class MerchantRepository {
  Future<MerchantProfile?> fetchCurrent();

  Future<MerchantProfile> register({
    required String businessName,
    required String document,
    required String phone,
    required String address,
    required String legalName,
    required String postalCode,
    required String street,
    required String buildingNumber,
    required String district,
    required String city,
    required String state,
    required String? openingTime,
    required String? closingTime,
    required List<String> operatingDays,
    required String socialLinks,
  });

  Stream<List<MerchantRide>> watchRides();
}

class MerchantFailure implements Exception {
  const MerchantFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
