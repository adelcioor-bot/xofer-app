enum IncidentReason {
  mechanical('problema_mecanico', 'Problema Mecânico / Acidente'),
  traffic('transito_bloqueio', 'Trânsito Parado / Bloqueio'),
  other('outro', 'Outro');

  const IncidentReason(this.wire, this.label);

  final String wire;
  final String label;
}

class IncidentReport {
  const IncidentReport({
    required this.corridaId,
    required this.motoboyId,
    required this.reason,
    required this.photoBytes,
    required this.acceptedAt,
    required this.penalized,
  });

  final String corridaId;
  final String motoboyId;
  final IncidentReason reason;
  final List<int> photoBytes;
  final DateTime acceptedAt;
  final bool penalized;
}
