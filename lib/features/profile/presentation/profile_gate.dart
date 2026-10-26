import 'package:flutter/material.dart';
import 'package:xofer/core/config/test_profile_seed.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/home/presentation/home_screen.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/places/domain/place_search_repository.dart';
import 'package:xofer/features/profile/domain/profile_failure.dart';
import 'package:xofer/features/profile/domain/profile_repository.dart';
import 'package:xofer/features/profile/domain/user_profile.dart';
import 'package:xofer/features/profile/presentation/complete_profile_screen.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';

class ProfileGate extends StatefulWidget {
  const ProfileGate({
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
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  UserProfile? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  String? _phoneOrTestSession(String? profilePhone) {
    final stored = profilePhone?.trim() ?? '';
    if (stored.isNotEmpty) return stored;
    return widget.authRepository.testPhone;
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var profile = await widget.profileRepository.fetchCurrent();
      final seed = widget.testProfileSeed;
      final candidatePhone = _phoneOrTestSession(profile?.phone);
      if (seed != null &&
          seed.matchesPhone(candidatePhone) &&
          !(profile?.isComplete ?? false)) {
        try {
          profile = await widget.profileRepository.save(
            fullName: seed.fullName,
            document: seed.document,
            phone: seed.phone,
          );
        } on ProfileFailure catch (error) {
          if (!error.isDuplicateKey) rethrow;
          profile = UserProfile(
            id: profile?.id ?? '',
            fullName: seed.fullName,
            document: seed.document,
            phone: seed.phone,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } on ProfileFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context).genericError;
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.authRepository.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                l10n.checkingProfile,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppTheme.amber,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    key: const Key('retry_profile_button'),
                    onPressed: _loadProfile,
                    child: Text(l10n.retry),
                  ),
                  TextButton(onPressed: _signOut, child: Text(l10n.signOut)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_profile?.fullName?.trim().isNotEmpty ?? false) {
      return HomeScreen(
        authRepository: widget.authRepository,
        locationRepository: widget.locationRepository,
        placeSearchRepository: widget.placeSearchRepository,
        corridaRepository: widget.corridaRepository,
      );
    }

    return CompleteProfileScreen(
      profileRepository: widget.profileRepository,
      authRepository: widget.authRepository,
      onCompleted: (profile) {
        setState(() => _profile = profile);
      },
    );
  }
}
