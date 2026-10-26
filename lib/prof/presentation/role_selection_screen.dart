import 'package:flutter/material.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/provider_repository.dart';
import 'package:xofer/prof/presentation/partner_flow.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({
    super.key,
    required this.authRepository,
    required this.providerRepository,
    this.corridaRepository,
    required this.locationRepository,
    required this.documentCapture,
    this.initialPhone,
    this.authenticatedSession = false,
  });

  final AuthRepository authRepository;
  final ProviderRepository providerRepository;
  final CorridaRepository? corridaRepository;
  final LocationRepository locationRepository;
  final DocumentCapture documentCapture;
  final String? initialPhone;
  final bool authenticatedSession;

  void _open(BuildContext context, PartnerRole role) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PartnerFlow(
          role: role,
          authRepository: authRepository,
          providerRepository: providerRepository,
          corridaRepository: corridaRepository,
          locationRepository: locationRepository,
          documentCapture: documentCapture,
          initialPhone: initialPhone,
          authenticatedSession: authenticatedSession,
        ),
      ),
    );
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: authenticatedSession
          ? AppBar(
              title: const Text('Xofer Prof'),
              actions: [
                IconButton(
                  key: const Key('prof_sign_out'),
                  tooltip: 'Terminar sessão',
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout, color: AppTheme.amber),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'XOFER PROF',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AppTheme.amber,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Como você quer atuar?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 28),
                  _RoleCard(
                    optionKey: const Key('role_driver'),
                    icon: Icons.directions_car,
                    title: PartnerRole.driver.title,
                    subtitle: 'Leva o carro do cliente até o destino.',
                    onTap: () => _open(context, PartnerRole.driver),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    optionKey: const Key('role_courier'),
                    icon: Icons.two_wheeler,
                    title: PartnerRole.courier.title,
                    subtitle: 'Vai de moto até o carro do cliente.',
                    onTap: () => _open(context, PartnerRole.courier),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.optionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key optionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.graphiteSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: optionKey,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.amber),
            ],
          ),
        ),
      ),
    );
  }
}
