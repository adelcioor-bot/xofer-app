class MerchantProfile {
  const MerchantProfile({
    required this.userId,
    required this.businessName,
    required this.document,
    required this.phone,
    required this.address,
    required this.status,
    this.legalName = '',
    this.postalCode = '',
    this.street = '',
    this.buildingNumber = '',
    this.district = '',
    this.city = '',
    this.state = '',
    this.openingTime,
    this.closingTime,
    this.operatingDays = const [],
    this.socialLinks,
  });

  final String userId;
  final String businessName;
  final String document;
  final String phone;
  final String address;
  final String status;
  final String legalName;
  final String postalCode;
  final String street;
  final String buildingNumber;
  final String district;
  final String city;
  final String state;
  final String? openingTime;
  final String? closingTime;
  final List<String> operatingDays;
  final String? socialLinks;

  factory MerchantProfile.fromMap(Map<String, dynamic> data) {
    return MerchantProfile(
      userId: '${data['user_id']}',
      businessName: '${data['business_name'] ?? ''}',
      document: '${data['document'] ?? ''}',
      phone: '${data['phone'] ?? ''}',
      address: '${data['address'] ?? ''}',
      status: '${data['status'] ?? ''}',
      legalName: '${data['legal_name'] ?? data['business_name'] ?? ''}',
      postalCode: '${data['postal_code'] ?? ''}',
      street: '${data['street'] ?? ''}',
      buildingNumber: '${data['building_number'] ?? ''}',
      district: '${data['district'] ?? ''}',
      city: '${data['city'] ?? ''}',
      state: '${data['state'] ?? ''}',
      openingTime: data['opening_time'] as String?,
      closingTime: data['closing_time'] as String?,
      operatingDays: data['operating_days'] is List
          ? (data['operating_days'] as List).whereType<String>().toList()
          : const [],
      socialLinks: data['social_links'] as String?,
    );
  }
}

class MerchantRide {
  const MerchantRide({
    required this.id,
    required this.callId,
    required this.serviceType,
    required this.status,
    required this.origin,
    required this.destination,
    required this.createdAt,
    required this.paymentStatus,
    this.customerName,
    this.customerPhone,
    this.driverId,
    this.driverName,
    this.driverRole,
    this.etaMinutes,
  });

  final String id;
  final String callId;
  final String serviceType;
  final String status;
  final String origin;
  final String destination;
  final DateTime? createdAt;
  final String? paymentStatus;
  final String? customerName;
  final String? customerPhone;
  final String? driverId;
  final String? driverName;
  final String? driverRole;
  final int? etaMinutes;

  bool get isTerminalError =>
      status.toLowerCase().contains('cancel') ||
      status.toLowerCase().contains('erro') ||
      status.toLowerCase().contains('falha');

  String get driverDescription {
    final name = driverName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final id = driverId;
    if (id == null) return 'Aguardando vínculo';
    final role = driverRole == 'courier' ? 'Motoboy' : 'Motorista';
    return '$role ${id.substring(0, id.length > 8 ? 8 : id.length)}';
  }

  factory MerchantRide.fromMap(Map<String, dynamic> data) {
    return MerchantRide(
      id: '${data['id']}',
      callId: '${data['call_id'] ?? ''}',
      serviceType: '${data['service_type'] ?? 'rescue'}',
      status: '${data['status_corrida'] ?? ''}',
      origin: '${data['origin'] ?? ''}',
      destination: '${data['destination'] ?? ''}',
      createdAt: DateTime.tryParse('${data['created_at'] ?? ''}')?.toLocal(),
      paymentStatus: data['payment_status'] as String?,
      customerName: _optionalText(data['cliente_nome']),
      customerPhone: _optionalText(data['cliente_telefone']),
      driverId: _optionalText(
        data['accepted_by'] ?? data['motorista_id'] ?? data['motoboy_id'],
      ),
      driverName: _optionalText(data['motoboy_nome'] ?? data['driver_label']),
      driverRole: _optionalText(data['accepted_role']),
      etaMinutes: _optionalInt(data['eta_minutos']),
    );
  }
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value');
}
