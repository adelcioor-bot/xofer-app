import 'package:flutter/widgets.dart';
import 'package:xofer/core/config/app_bootstrap.dart';
import 'package:xofer/features/auth/data/supabase_auth_repository.dart';
import 'package:xofer/features/location/data/geolocator_location_repository.dart';
import 'package:xofer/prof/data/image_picker_document_capture.dart';
import 'package:xofer/prof/data/supabase_corrida_repository.dart';
import 'package:xofer/prof/data/supabase_provider_repository.dart';
import 'package:xofer/prof/prof_app.dart';

Future<void> main() async {
  await AppBootstrap.init();
  runApp(
    XoferProfApp(
      authRepository: SupabaseAuthRepository(),
      providerRepository: SupabaseProviderRepository(),
      corridaRepository: SupabaseCorridaRepository(),
      locationRepository: const GeolocatorLocationRepository(),
      documentCapture: ImagePickerDocumentCapture(),
    ),
  );
}
