import 'package:flutter/material.dart';
import 'package:xofer/app.dart';
import 'package:xofer/core/config/app_config.dart';
import 'package:xofer/core/config/app_bootstrap.dart';
import 'package:xofer/features/auth/data/supabase_auth_repository.dart';
import 'package:xofer/features/location/data/geolocator_location_repository.dart';
import 'package:xofer/features/places/data/nominatim_place_search_repository.dart';
import 'package:xofer/features/profile/data/supabase_profile_repository.dart';
import 'package:xofer/prof/data/supabase_corrida_repository.dart';

Future<void> main() async {
  await AppBootstrap.init();

  final authRepository = SupabaseAuthRepository();
  final profileRepository = SupabaseProfileRepository();
  const locationRepository = GeolocatorLocationRepository();
  final placeSearchRepository = NominatimPlaceSearchRepository();

  runApp(
    XoferApp(
      authRepository: authRepository,
      profileRepository: profileRepository,
      locationRepository: locationRepository,
      placeSearchRepository: placeSearchRepository,
      corridaRepository: SupabaseCorridaRepository(),
      testProfileSeed: AppConfig.testProfileSeed,
    ),
  );
}
