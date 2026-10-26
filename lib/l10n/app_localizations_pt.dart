// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Xofer';

  @override
  String get loginTitle => 'Entrar';

  @override
  String get loginSubtitle =>
      'Informe o número do Celular para receber um código de verificação.';

  @override
  String get phoneLabel => 'Número do Celular';

  @override
  String get phoneHint => '912 345 678';

  @override
  String get sendOtp => 'Enviar código';

  @override
  String otpSentTo(String phone) {
    return 'Código enviado para $phone';
  }

  @override
  String get otpLabel => 'Código OTP';

  @override
  String get otpHint => '000000';

  @override
  String get verifyOtp => 'Verificar e entrar';

  @override
  String get changeNumber => 'Alterar número';

  @override
  String get resendOtp => 'Reenviar código';

  @override
  String get invalidPhone => 'Informe um número de Celular válido.';

  @override
  String get invalidOtp => 'Informe o código de 6 dígitos.';

  @override
  String get homeWelcome => 'Para onde vamos?';

  @override
  String get signOut => 'Terminar sessão';

  @override
  String get genericError =>
      'Não foi possível concluir o pedido. Tente novamente.';

  @override
  String get completeProfileTitle => 'Complete o cadastro';

  @override
  String get completeProfileSubtitle =>
      'Informe seu nome e documento para continuar.';

  @override
  String get fullNameLabel => 'Nome completo';

  @override
  String get fullNameHint => 'Como no documento';

  @override
  String get documentLabel => 'CPF';

  @override
  String get documentHint => '000.000.000-00';

  @override
  String get saveProfile => 'Salvar e continuar';

  @override
  String get invalidFullName => 'Informe o nome completo.';

  @override
  String get invalidDocument => 'Informe um CPF válido.';

  @override
  String get checkingProfile => 'A verificar o cadastro...';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get myLocation => 'Minha localização';

  @override
  String get locationServiceDisabled =>
      'O GPS está desativado. Ative a localização do aparelho para vermos onde você está.';

  @override
  String get locationPermissionDenied =>
      'Sem a permissão de localização não conseguimos centralizar o mapa. Permita o acesso e tente de novo.';

  @override
  String get locationPermissionDeniedForever =>
      'A localização está bloqueada para o Xofer. Ative a permissão nas configurações do aparelho.';

  @override
  String get locationUnavailable =>
      'Não foi possível obter a sua posição. Tente novamente.';

  @override
  String get openLocationSettings => 'Ativar GPS';

  @override
  String get openAppSettings => 'Abrir configurações';

  @override
  String get noAddressResults => 'Nenhum endereço encontrado.';

  @override
  String get addressSearchError =>
      'Não foi possível buscar endereços. Tente novamente.';

  @override
  String get clearSearch => 'Limpar busca';

  @override
  String get originLabel => 'Origem';

  @override
  String get destinationLabel => 'Destino';

  @override
  String get locatingOrigin => 'Obtendo seu endereço...';

  @override
  String get originUnavailable => 'Localização atual';

  @override
  String get rideSummaryTitle => 'Resumo da corrida';

  @override
  String get estimatedPrice => 'Preço estimado';

  @override
  String get paymentMethod => 'Pagamento';

  @override
  String get creditCard => 'Cartão de Crédito';

  @override
  String get savedCard => 'Visa •••• 4242';

  @override
  String get pix => 'PIX';

  @override
  String get pixCopyPaste => 'Copia e cola';

  @override
  String get copyPixCode => 'Copiar código';

  @override
  String get pixCopied => 'Código copiado';

  @override
  String get confirmDriver => 'Confirmar Motorista + Resgate';

  @override
  String get activeTripTitle => 'Rastreamento ativo';

  @override
  String get driverOnTheWay => 'Motorista a caminho do resgate';

  @override
  String get headingToDestination => 'A caminho do destino';

  @override
  String get tripArrived => 'Você chegou ao destino';

  @override
  String get followRoute => 'Acompanhar trajeto';

  @override
  String get assignedDriver => 'Ana Costa';

  @override
  String get assignedVehicle => 'Honda Civic · ABC-1D23';
}
