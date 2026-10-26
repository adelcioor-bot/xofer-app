import 'dart:math';

const invalidBoardingQrMessage = 'QR Code inválido para esta viagem';

const boardingQrInstruction =
    'Peça ao cliente ou ao parceiro do bar para escanear este QR Code para liberar o início da corrida.';

String createBoardingToken(String corridaId) {
  final random = Random.secure();
  final nonce = List<int>.generate(
    4,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final compact = corridaId.replaceAll('-', '');
  final head = compact.length >= 4 ? compact.substring(0, 4) : compact;
  return '${head.toUpperCase()}${nonce.toUpperCase()}';
}

String createReserveCode() {
  return Random.secure().nextInt(10000).toString().padLeft(4, '0');
}

bool boardingTokensMatch(String scanned, String? expected) {
  final code = scanned.trim();
  final token = expected?.trim() ?? '';
  return code.isNotEmpty && token.isNotEmpty && code == token;
}

bool reserveCodesMatch(String entered, String? expected) {
  final code = entered.trim();
  final reserveCode = expected?.trim() ?? '';
  return RegExp(r'^\d{4}$').hasMatch(code) && code == reserveCode;
}

const invalidBoardingReserveCodeMessage =
    'Código incorreto. Confirme o número na tela do motorista.';
