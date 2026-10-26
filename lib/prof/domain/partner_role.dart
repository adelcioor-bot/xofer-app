enum PartnerRole { driver, courier }

extension PartnerRoleWire on PartnerRole {
  String get wire => switch (this) {
    PartnerRole.driver => 'driver',
    PartnerRole.courier => 'courier',
  };

  String get title => switch (this) {
    PartnerRole.driver => 'Motorista (Xofer)',
    PartnerRole.courier => 'Motoboy (Resgatador)',
  };
}
