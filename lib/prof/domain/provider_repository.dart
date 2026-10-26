import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/provider_account.dart';

abstract class ProviderRepository {
  Future<ProviderAccount?> findCurrent(PartnerRole role);

  Future<ProviderAccount> saveApplication(ProviderApplication application);

  Future<ProviderAccount> ensureActiveTestPartner({
    required PartnerRole role,
    required String phone,
  });
}
