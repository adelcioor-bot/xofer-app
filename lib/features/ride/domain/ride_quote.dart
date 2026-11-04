class RideQuote {
  const RideQuote({
    required this.id,
    required this.amountCents,
    required this.expiresAt,
  });

  final String id;
  final int amountCents;
  final DateTime expiresAt;

  double get price => amountCents / 100;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);
}

String formatBrlCents(int cents) {
  final negative = cents < 0;
  final absoluteCents = cents.abs();
  final whole = (absoluteCents ~/ 100).toString();
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    final remaining = whole.length - i;
    if (i > 0 && remaining % 3 == 0) buffer.write('.');
    buffer.write(whole[i]);
  }
  final sign = negative ? '-' : '';
  final remainder = (absoluteCents % 100).toString().padLeft(2, '0');
  return '${sign}R\$ $buffer,$remainder';
}

String formatBrl(double value) => formatBrlCents((value * 100).round());

String formatKilometers(double kilometers) {
  return '${kilometers.toStringAsFixed(1).replaceAll('.', ',')} km';
}

String pixCopyPaste(RideQuote quote) {
  final cents = quote.amountCents.toString().padLeft(4, '0');
  return '00020126580014br.gov.bcb.pix0136xofer@teste.xofer540$cents'
      '5802BR6304XOFR';
}
