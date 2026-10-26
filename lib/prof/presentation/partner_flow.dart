import 'package:flutter/material.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/data/test_phone_login.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/provider_account.dart';
import 'package:xofer/prof/domain/provider_failure.dart';
import 'package:xofer/prof/domain/provider_repository.dart';
import 'package:xofer/prof/presentation/partner_auth_screen.dart';
import 'package:xofer/prof/presentation/radar_screen.dart';
import 'package:xofer/prof/presentation/registration_screen.dart';

class PartnerFlow extends StatefulWidget {
  const PartnerFlow({
    super.key,
    required this.role,
    required this.authRepository,
    required this.providerRepository,
    this.corridaRepository,
    required this.locationRepository,
    required this.documentCapture,
    this.initialPhone,
    this.authenticatedSession = false,
  });

  final PartnerRole role;
  final AuthRepository authRepository;
  final ProviderRepository providerRepository;
  final CorridaRepository? corridaRepository;
  final LocationRepository locationRepository;
  final DocumentCapture documentCapture;
  final String? initialPhone;
  final bool authenticatedSession;

  @override
  State<PartnerFlow> createState() => _PartnerFlowState();
}

class _PartnerFlowState extends State<PartnerFlow> {
  String? _phone;
  ProviderAccount? _account;
  bool _checking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.authenticatedSession) {
      final phone = widget.initialPhone ?? widget.authRepository.currentPhone;
      _phone = phone ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolve(_phone!);
      });
    }
  }

  Future<void> _resolve(String phone) async {
    setState(() {
      _phone = phone;
      _checking = true;
      _errorMessage = null;
      _account = null;
    });

    final testPhone = TestPhoneLogin.canonical(phone);
    final roleTestPhone = switch (widget.role) {
      PartnerRole.driver => TestPhoneLogin.driverStoredDigits,
      PartnerRole.courier => TestPhoneLogin.courierStoredDigits,
    };

    try {
      var account = await widget.providerRepository.findCurrent(widget.role);
      if (testPhone == roleTestPhone && !(account?.canReceiveCalls ?? false)) {
        account = await widget.providerRepository.ensureActiveTestPartner(
          role: widget.role,
          phone: roleTestPhone,
        );
      }
      if (!mounted) return;
      setState(() {
        _account = account;
        _checking = false;
      });
    } on ProviderFailure catch (error) {
      if (!mounted) return;
      if (testPhone == roleTestPhone && error.isMissingTable) {
        _ensureTestPartner(roleTestPhone);
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível validar o cadastro de parceiro.';
        _checking = false;
      });
    }
  }

  Future<void> _ensureTestPartner(String phone) async {
    try {
      final account = await widget.providerRepository.ensureActiveTestPartner(
        role: widget.role,
        phone: phone,
      );
      if (!mounted) return;
      setState(() {
        _account = account;
        _checking = false;
      });
    } on ProviderFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível validar o cadastro de parceiro.';
        _checking = false;
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
    final phone = _phone;
    if (phone == null) {
      return PartnerAuthScreen(
        role: widget.role,
        authRepository: widget.authRepository,
        onVerified: _resolve,
      );
    }

    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.role.title)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _errorMessage!,
                  key: const Key('partner_lookup_error'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _resolve(phone),
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final account = _account;
    if (account == null) {
      return RegistrationScreen(
        role: widget.role,
        phone: phone,
        documentCapture: widget.documentCapture,
        onSubmit: widget.providerRepository.saveApplication,
        onCompleted: (saved) => setState(() => _account = saved),
      );
    }

    if (account.canReceiveCalls) {
      return RadarScreen(
        role: widget.role,
        locationRepository: widget.locationRepository,
        corridaRepository: widget.corridaRepository,
        partnerId: account.id,
        partnerName: account.fullName,
        documentCapture: widget.documentCapture,
        onSignOut: _signOut,
      );
    }

    return _ReviewStatus(
      account: account,
      onSignOut: _signOut,
      onRetry: account.status == ProviderStatus.recusado
          ? () => setState(() => _account = null)
          : null,
    );
  }
}

class _ReviewStatus extends StatelessWidget {
  const _ReviewStatus({
    required this.account,
    required this.onSignOut,
    required this.onRetry,
  });

  final ProviderAccount account;
  final Future<void> Function() onSignOut;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final refused = account.status == ProviderStatus.recusado;
    return Scaffold(
      appBar: AppBar(title: Text(account.role.title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  refused ? Icons.highlight_off : Icons.hourglass_top,
                  color: AppTheme.amber,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  refused ? 'Cadastro recusado' : 'Cadastro em análise',
                  key: const Key('provider_review_status'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  refused
                      ? 'A foto ficou ilegível ou os dados não conferiram. Envie os documentos novamente.'
                      : 'Os documentos seguem para leitura automática e consulta do CPF. Quando a aprovação for concluída, o status fica ativo e as chamadas aparecem no radar.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                if (onRetry != null)
                  ElevatedButton(
                    key: const Key('provider_retry_registration'),
                    onPressed: onRetry,
                    child: const Text('Refazer envio'),
                  ),
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('Terminar sessão'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
