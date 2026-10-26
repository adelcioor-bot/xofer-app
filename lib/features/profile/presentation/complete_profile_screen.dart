import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/profile/data/cpf.dart';
import 'package:xofer/features/profile/domain/profile_failure.dart';
import 'package:xofer/features/profile/domain/profile_repository.dart';
import 'package:xofer/features/profile/domain/user_profile.dart';
import 'package:xofer/l10n/app_localizations.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({
    super.key,
    required this.profileRepository,
    required this.authRepository,
    required this.onCompleted,
  });

  final ProfileRepository profileRepository;
  final AuthRepository authRepository;
  final ValueChanged<UserProfile> onCompleted;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _documentController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _documentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await widget.profileRepository.save(
        fullName: _nameController.text,
        document: _documentController.text,
      );
      if (!mounted) return;
      widget.onCompleted(profile);
    } on ProfileFailure catch (error) {
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

  Future<void> _signOut() async {
    try {
      await widget.authRepository.signOut();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
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
                        l10n.completeProfileTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.completeProfileSubtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        key: const Key('full_name_field'),
                        controller: _nameController,
                        enabled: !_isLoading,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        validator: (value) {
                          if ((value ?? '').trim().length < 3) {
                            return l10n.invalidFullName;
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: l10n.fullNameLabel,
                          hintText: l10n.fullNameHint,
                          prefixIcon: const Icon(
                            Icons.person_outline,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('document_field'),
                        controller: _documentController,
                        enabled: !_isLoading,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          CpfInputFormatter(),
                        ],
                        onFieldSubmitted: (_) {
                          if (!_isLoading) _submit();
                        },
                        validator: (value) {
                          if (!Cpf.isValid(value ?? '')) {
                            return l10n.invalidDocument;
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: l10n.documentLabel,
                          hintText: l10n.documentHint,
                          prefixIcon: const Icon(
                            Icons.badge_outlined,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('save_profile_button'),
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.black,
                                ),
                              )
                            : Text(l10n.saveProfile),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          key: const Key('profile_error'),
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isLoading ? null : _signOut,
                        child: Text(l10n.signOut),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
