import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xofer/core/config/app_config.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/data/phone_number.dart';
import 'package:xofer/features/auth/domain/auth_failure.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/partner_role.dart';

class PartnerAuthScreen extends StatefulWidget {
  const PartnerAuthScreen({
    super.key,
    required this.role,
    required this.authRepository,
    required this.onVerified,
  });

  final PartnerRole role;
  final AuthRepository authRepository;
  final ValueChanged<String> onVerified;

  @override
  State<PartnerAuthScreen> createState() => _PartnerAuthScreenState();
}

class _PartnerAuthScreenState extends State<PartnerAuthScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _normalizedPhone;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final l10n = AppLocalizations.of(context);
    final phone = PhoneNumber.normalize(
      _phoneController.text,
      countryCode: AppConfig.defaultCountryCode,
    );
    if (!PhoneNumber.isValid(phone)) {
      setState(() => _errorMessage = l10n.invalidPhone);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.authRepository.sendOtp(phone);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _normalizedPhone = phone;
        _otpController.clear();
      });
    } on AuthFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.genericError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final l10n = AppLocalizations.of(context);
    final phone = _normalizedPhone;
    final code = _otpController.text.trim();
    if (phone == null || code.length != 6) {
      setState(() => _errorMessage = l10n.invalidOtp);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.authRepository.verifyOtp(phoneNumber: phone, code: code);
      if (!mounted) return;
      widget.onVerified(phone);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.genericError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.role.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'XOFER PROF',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: AppTheme.amber,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Informe o celular cadastrado como parceiro.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('partner_phone_field'),
                    controller: _phoneController,
                    enabled: !_otpSent && !_isLoading,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Celular',
                      prefixText: '+55 ',
                    ),
                  ),
                  if (_otpSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('partner_otp_field'),
                      controller: _otpController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Código',
                        counterText: '',
                      ),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      key: const Key('partner_auth_error'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    key: Key(_otpSent ? 'partner_verify_otp' : 'partner_send_otp'),
                    onPressed: _isLoading
                        ? null
                        : (_otpSent ? _verifyOtp : _sendOtp),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(_otpSent ? 'Validar código' : 'Receber código'),
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
