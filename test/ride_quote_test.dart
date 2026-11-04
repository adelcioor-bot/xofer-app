import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';

void main() {
  test('converte centavos sem aplicar tarifa local', () {
    final quote = RideQuote(
      id: 'quote-1',
      amountCents: 123450,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );

    expect(quote.price, 1234.5);
    expect(formatBrlCents(quote.amountCents), r'R$ 1.234,50');
    expect(pixCopyPaste(quote), contains('br.gov.bcb.pix'));
  });

  test('a validade da cotação é determinada pela expiração do servidor', () {
    final now = DateTime.now();
    final quote = RideQuote(
      id: 'quote-2',
      amountCents: 1200,
      expiresAt: now.add(const Duration(minutes: 5)),
    );

    expect(quote.isExpiredAt(now), isFalse);
    expect(quote.isExpiredAt(now.add(const Duration(minutes: 5))), isTrue);
  });
}
