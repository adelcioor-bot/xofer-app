import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/provider_repository.dart';
import 'package:xofer/prof/presentation/partner_flow.dart';
import 'package:xofer/prof/presentation/role_selection_screen.dart';

class XoferProfApp extends StatelessWidget {
  const XoferProfApp({
    super.key,
    required this.authRepository,
    required this.providerRepository,
    this.corridaRepository,
    required this.locationRepository,
    required this.documentCapture,
    this.authStateStream,
    this.currentSession,
  });

  final AuthRepository authRepository;
  final ProviderRepository providerRepository;
  final CorridaRepository? corridaRepository;
  final LocationRepository locationRepository;
  final DocumentCapture documentCapture;
  final Stream<AuthState>? authStateStream;
  final Session? currentSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xofer Prof',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      locale: const Locale('pt'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: _ProfAuthGate(
        authRepository: authRepository,
        providerRepository: providerRepository,
        corridaRepository: corridaRepository,
        locationRepository: locationRepository,
        documentCapture: documentCapture,
        authStateStream: authStateStream,
        currentSession: currentSession,
      ),
    );
  }
}

class _ProfAuthGate extends StatelessWidget {
  const _ProfAuthGate({
    required this.authRepository,
    required this.providerRepository,
    required this.corridaRepository,
    required this.locationRepository,
    required this.documentCapture,
    this.authStateStream,
    this.currentSession,
  });

  final AuthRepository authRepository;
  final ProviderRepository providerRepository;
  final CorridaRepository? corridaRepository;
  final LocationRepository locationRepository;
  final DocumentCapture documentCapture;
  final Stream<AuthState>? authStateStream;
  final Session? currentSession;

  Session? _liveSession() {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  Stream<AuthState> _liveAuthStateStream() {
    try {
      return Supabase.instance.client.auth.onAuthStateChange;
    } catch (_) {
      return const Stream<AuthState>.empty();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: authStateStream ?? _liveAuthStateStream(),
      builder: (context, snapshot) {
        final session = snapshot.hasData
            ? snapshot.data!.session ?? _liveSession()
            : currentSession ?? _liveSession();
        if (session == null || session.user.isAnonymous) {
          return RoleSelectionScreen(
            authRepository: authRepository,
            providerRepository: providerRepository,
            corridaRepository: corridaRepository,
            locationRepository: locationRepository,
            documentCapture: documentCapture,
          );
        }

        return _AuthenticatedProfEntry(
          key: ValueKey(session.user.id),
          authRepository: authRepository,
          providerRepository: providerRepository,
          corridaRepository: corridaRepository,
          locationRepository: locationRepository,
          documentCapture: documentCapture,
        );
      },
    );
  }
}

class _AuthenticatedProfEntry extends StatelessWidget {
  _AuthenticatedProfEntry({
    super.key,
    required this.authRepository,
    required this.providerRepository,
    required this.corridaRepository,
    required this.locationRepository,
    required this.documentCapture,
  });

  final AuthRepository authRepository;
  final ProviderRepository providerRepository;
  final CorridaRepository? corridaRepository;
  final LocationRepository locationRepository;
  final DocumentCapture documentCapture;

  late final Future<PartnerRole?> _existingRole = _findExistingRole();

  Future<PartnerRole?> _findExistingRole() async {
    final driver = await providerRepository.findCurrent(PartnerRole.driver);
    if (driver != null) return PartnerRole.driver;
    final courier = await providerRepository.findCurrent(PartnerRole.courier);
    if (courier != null) return PartnerRole.courier;
    return null;
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await authRepository.signOut();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PartnerRole?>(
      future: _existingRole,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Não foi possível restaurar o acesso do parceiro.',
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _signOut(context),
                      child: const Text('Sair'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data;
        if (role == null) {
          return RoleSelectionScreen(
            authRepository: authRepository,
            providerRepository: providerRepository,
            corridaRepository: corridaRepository,
            locationRepository: locationRepository,
            documentCapture: documentCapture,
            initialPhone: authRepository.currentPhone,
            authenticatedSession: true,
          );
        }
        return PartnerFlow(
          role: role,
          authRepository: authRepository,
          providerRepository: providerRepository,
          corridaRepository: corridaRepository,
          locationRepository: locationRepository,
          documentCapture: documentCapture,
          initialPhone: authRepository.currentPhone,
          authenticatedSession: true,
        );
      },
    );
  }
}
