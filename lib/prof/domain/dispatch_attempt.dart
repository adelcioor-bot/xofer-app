class DispatchAttempt {
  const DispatchAttempt({
    required this.id,
    required this.providerRole,
    required this.status,
    required this.expiresAt,
  });

  final String id;
  final String providerRole;
  final String status;
  final DateTime expiresAt;

  factory DispatchAttempt.fromMap(Map<String, dynamic> data) {
    final id = data['id'];
    final providerRole = data['provider_role'];
    final status = data['status'];
    final expiresAt = DateTime.tryParse('${data['expires_at'] ?? ''}');
    if (id is! String ||
        providerRole is! String ||
        status is! String ||
        expiresAt == null) {
      throw const FormatException('Tentativa de missão inválida.');
    }
    return DispatchAttempt(
      id: id,
      providerRole: providerRole,
      status: status,
      expiresAt: expiresAt,
    );
  }
}
