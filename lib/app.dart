import 'package:flutter/material.dart';
import 'package:xofer/core/config/test_profile_seed.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/auth/presentation/auth_gate.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/places/domain/place_search_repository.dart';
import 'package:xofer/features/profile/domain/profile_repository.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';

class XoferApp extends StatelessWidget {
  const XoferApp({
    super.key,
    required this.authRepository,
    required this.profileRepository,
    required this.locationRepository,
    required this.placeSearchRepository,
    this.corridaRepository,
    this.testProfileSeed,
  });

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final LocationRepository locationRepository;
  final PlaceSearchRepository placeSearchRepository;
  final CorridaRepository? corridaRepository;
  final TestProfileSeed? testProfileSeed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      locale: const Locale('pt'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AuthGate(
        authRepository: authRepository,
        profileRepository: profileRepository,
        locationRepository: locationRepository,
        placeSearchRepository: placeSearchRepository,
        corridaRepository: corridaRepository,
        testProfileSeed: testProfileSeed,
      ),
    );
  }
}
