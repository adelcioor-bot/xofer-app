import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xofer/core/config/test_profile_seed.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/auth/presentation/login_screen.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/places/domain/place_search_repository.dart';
import 'package:xofer/features/profile/domain/profile_repository.dart';
import 'package:xofer/features/profile/presentation/profile_gate.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authRepository,
    required this.profileRepository,
    required this.locationRepository,
    required this.placeSearchRepository,
    this.corridaRepository,
    this.authStateStream,
    this.currentSession,
    this.testProfileSeed,
  });

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final LocationRepository locationRepository;
  final PlaceSearchRepository placeSearchRepository;
  final CorridaRepository? corridaRepository;
  final Stream<AuthState>? authStateStream;
  final Session? currentSession;
  final TestProfileSeed? testProfileSeed;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
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
      stream: widget.authStateStream ?? _liveAuthStateStream(),
      builder: (context, snapshot) {
        final session = snapshot.hasData
            ? snapshot.data!.session ?? _liveSession()
            : widget.currentSession ?? _liveSession();

        if (session != null && !session.user.isAnonymous) {
          return ProfileGate(
            authRepository: widget.authRepository,
            profileRepository: widget.profileRepository,
            locationRepository: widget.locationRepository,
            placeSearchRepository: widget.placeSearchRepository,
            corridaRepository: widget.corridaRepository,
            testProfileSeed: widget.testProfileSeed,
          );
        }

        return LoginScreen(authRepository: widget.authRepository);
      },
    );
  }
}
