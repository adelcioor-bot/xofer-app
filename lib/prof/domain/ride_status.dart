import 'package:xofer/prof/domain/partner_role.dart';

enum RideStatus {
  buscandoPrestadores('buscando_prestadores'),
  procurandoMotoboy('procurando_motoboy'),
  motoboyACaminho('motoboy_a_caminho'),
  aCaminhoDoCliente('a_caminho_do_cliente'),
  aguardandoValidacaoEmbarque('aguardando_validacao_embarque'),
  emAndamento('em_andamento'),
  conduzindoDestino('conduzindo_destino'),
  concluida('concluida');

  const RideStatus(this.wire);

  final String wire;

  static RideStatus? tryParse(String raw) {
    for (final status in RideStatus.values) {
      if (status.wire == raw) return status;
    }
    return null;
  }
}

class RescuePhaseMachine {
  const RescuePhaseMachine._();

  static RideStatus? next(RideStatus current, PartnerRole role) {
    if (role == PartnerRole.courier) {
      return switch (current) {
        RideStatus.motoboyACaminho => RideStatus.aCaminhoDoCliente,
        RideStatus.aCaminhoDoCliente => RideStatus.conduzindoDestino,
        _ => null,
      };
    }
    return switch (current) {
      RideStatus.emAndamento => RideStatus.concluida,
      RideStatus.conduzindoDestino => RideStatus.concluida,
      _ => null,
    };
  }

  static String? actionLabel(RideStatus current, PartnerRole role) {
    return switch (next(current, role)) {
      RideStatus.aCaminhoDoCliente => 'Cheguei ao Motorista',
      RideStatus.conduzindoDestino => 'Motorista Entregue no Cliente',
      RideStatus.concluida => 'Finalizar Corrida',
      _ => null,
    };
  }
}
