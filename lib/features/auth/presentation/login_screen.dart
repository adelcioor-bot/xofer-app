import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xofer/core/config/app_config.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/data/phone_number.dart';
import 'package:xofer/features/auth/domain/auth_failure.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
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

  String get _countryCode => AppConfig.defaultCountryCode;

  Future<void> _sendOtp() async {
    final l10n = AppLocalizations.of(context);
    final phone = PhoneNumber.normalize(
      _phoneController.text,
      countryCode: _countryCode,
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    final l10n = AppLocalizations.of(context);
    final code = _otpController.text.trim();
    final phone = _normalizedPhone;

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
    } on AuthFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = l10n.genericError);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _resetToPhoneStep() {
    setState(() {
      _otpSent = false;
      _normalizedPhone = null;
      _otpController.clear();
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      'XOFER',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: AppTheme.amber,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.loginTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _otpSent && _normalizedPhone != null
                          ? l10n.otpSentTo(_normalizedPhone!)
                          : l10n.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (!_otpSent) ...[
                      TextFormField(
                        key: const Key('phone_field'),
                        controller: _phoneController,
                        enabled: !_isLoading,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
                        ],
                        onFieldSubmitted: (_) {
                          if (!_isLoading) _sendOtp();
                        },
                        decoration: InputDecoration(
                          labelText: l10n.phoneLabel,
                          hintText: l10n.phoneHint,
                          prefixText: '$_countryCode  ',
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('send_otp_button'),
                        onPressed: _isLoading ? null : _sendOtp,
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.black,
                                ),
                              )
                            : Text(l10n.sendOtp),
                      ),
                    ] else ...[
                      TextFormField(
                        key: const Key('otp_field'),
                        controller: _otpController,
                        enabled: !_isLoading,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onFieldSubmitted: (_) {
                          if (!_isLoading) _verifyOtp();
                        },
                        decoration: InputDecoration(
                          labelText: l10n.otpLabel,
                          hintText: l10n.otpHint,
                          counterText: '',
                          prefixIcon: const Icon(
                            Icons.sms_outlined,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('verify_otp_button'),
                        onPressed: _isLoading ? null : _verifyOtp,
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.black,
                                ),
                              )
                            : Text(l10n.verifyOtp),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isLoading ? null : _sendOtp,
                        child: Text(l10n.resendOtp),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _resetToPhoneStep,
                        child: Text(l10n.changeNumber),
                      ),
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        key: const Key('auth_error'),
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
