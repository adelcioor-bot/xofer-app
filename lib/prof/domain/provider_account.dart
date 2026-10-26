import 'package:xofer/prof/domain/partner_role.dart';

enum ProviderStatus { analise, ativo, recusado }

ProviderStatus providerStatusFromWire(String raw) {
  return switch (raw) {
    'ativo' => ProviderStatus.ativo,
    'recusado' => ProviderStatus.recusado,
    _ => ProviderStatus.analise,
  };
}

extension ProviderStatusWire on ProviderStatus {
  String get wire => switch (this) {
    ProviderStatus.analise => 'analise',
    ProviderStatus.ativo => 'ativo',
    ProviderStatus.recusado => 'recusado',
  };
}

class ProviderAccount {
  const ProviderAccount({
    required this.id,
    required this.role,
    required this.fullName,
    required this.document,
    required this.phone,
    required this.email,
    required this.status,
  });

  final String id;
  final PartnerRole role;
  final String fullName;
  final String document;
  final String phone;
  final String email;
  final ProviderStatus status;

  bool get canReceiveCalls => status == ProviderStatus.ativo;
}

class CapturedDocument {
  const CapturedDocument({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

class ProviderApplication {
  const ProviderApplication({
    required this.role,
    required this.fullName,
    required this.document,
    required this.phone,
    required this.email,
    required this.cnh,
    required this.criminalRecord,
    required this.selfie,
    this.crlv,
  });

  final PartnerRole role;
  final String fullName;
  final String document;
  final String phone;
  final String email;
  final CapturedDocument cnh;
  final CapturedDocument criminalRecord;
  final CapturedDocument selfie;
  final CapturedDocument? crlv;
}
