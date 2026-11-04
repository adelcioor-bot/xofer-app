import 'package:flutter/material.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/merchant/domain/merchant_repository.dart';
import 'package:xofer/features/merchant/presentation/merchant_portal_screen.dart';
import 'package:xofer/features/places/domain/place_search_repository.dart';
import 'package:xofer/features/ride/domain/ride_quote_repository.dart';
import 'package:xofer/features/home/presentation/home_screen.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/features/merchant/domain/merchant_auth_repository.dart';

class XoferMerchantApp extends StatelessWidget {
  const XoferMerchantApp({
    super.key,
    required this.authRepository,
    required this.merchantAuthRepository,
    required this.merchantRepository,
    required this.locationRepository,
    required this.placeSearchRepository,
    required this.corridaRepository,
    required this.rideQuoteRepository,
  });

  final AuthRepository authRepository;
  final MerchantAuthRepository merchantAuthRepository;
  final MerchantRepository merchantRepository;
  final LocationRepository locationRepository;
  final PlaceSearchRepository placeSearchRepository;
  final CorridaRepository corridaRepository;
  final RideQuoteRepository rideQuoteRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xofer Merchant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      locale: const Locale('pt'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: _MerchantPortalHost(
        authRepository: authRepository,
        merchantAuthRepository: merchantAuthRepository,
        merchantRepository: merchantRepository,
        locationRepository: locationRepository,
        placeSearchRepository: placeSearchRepository,
        corridaRepository: corridaRepository,
        rideQuoteRepository: rideQuoteRepository,
      ),
    );
  }
}

class _MerchantPortalHost extends StatelessWidget {
  const _MerchantPortalHost({
    required this.authRepository,
    required this.merchantAuthRepository,
    required this.merchantRepository,
    required this.locationRepository,
    required this.placeSearchRepository,
    required this.corridaRepository,
    required this.rideQuoteRepository,
  });

  final AuthRepository authRepository;
  final MerchantAuthRepository merchantAuthRepository;
  final MerchantRepository merchantRepository;
  final LocationRepository locationRepository;
  final PlaceSearchRepository placeSearchRepository;
  final CorridaRepository corridaRepository;
  final RideQuoteRepository rideQuoteRepository;

  void _openRequest(BuildContext context, String serviceType) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(
          authRepository: authRepository,
          locationRepository: locationRepository,
          placeSearchRepository: placeSearchRepository,
          corridaRepository: corridaRepository,
          rideQuoteRepository: rideQuoteRepository,
          requesterType: 'merchant',
          serviceType: serviceType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MerchantPortalScreen(
      authRepository: authRepository,
      merchantAuthRepository: merchantAuthRepository,
      merchantRepository: merchantRepository,
      onCreateDelivery: () => _openRequest(context, 'delivery'),
      onCreateRescue: () => _openRequest(context, 'rescue'),
    );
  }
}
