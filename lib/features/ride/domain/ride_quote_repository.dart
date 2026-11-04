import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';

abstract interface class RideQuoteRepository {
  Future<RideQuote> generate({
    required Place origin,
    required Place destination,
    String requesterType = 'customer',
  });
}

class RideQuoteFailure implements Exception {
  const RideQuoteFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
