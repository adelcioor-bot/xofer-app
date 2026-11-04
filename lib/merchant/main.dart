import 'package:flutter/widgets.dart';
import 'package:xofer/core/config/app_bootstrap.dart';
import 'package:xofer/features/auth/data/supabase_auth_repository.dart';
import 'package:xofer/features/location/data/geolocator_location_repository.dart';
import 'package:xofer/features/merchant/data/supabase_merchant_repository.dart';
import 'package:xofer/features/merchant/data/supabase_merchant_auth_repository.dart';
import 'package:xofer/features/merchant/merchant_app.dart';
import 'package:xofer/features/places/data/nominatim_place_search_repository.dart';
import 'package:xofer/features/ride/data/supabase_ride_quote_repository.dart';
import 'package:xofer/prof/data/supabase_corrida_repository.dart';

Future<void> main() async {
  await AppBootstrap.init();
  runApp(
    XoferMerchantApp(
      authRepository: SupabaseAuthRepository(),
      merchantAuthRepository: SupabaseMerchantAuthRepository(),
      merchantRepository: SupabaseMerchantRepository(),
      locationRepository: const GeolocatorLocationRepository(),
      placeSearchRepository: NominatimPlaceSearchRepository(),
      corridaRepository: SupabaseCorridaRepository(),
      rideQuoteRepository: SupabaseRideQuoteRepository(),
    ),
  );
}
