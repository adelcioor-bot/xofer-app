import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_failure.dart';
import 'package:xofer/features/merchant/domain/cnpj.dart';
import 'package:xofer/features/merchant/domain/merchant_auth_repository.dart';

class MerchantLoginScreen extends StatefulWidget {
  const MerchantLoginScreen({super.key, required this.authRepository});

  final MerchantAuthRepository authRepository;

  @override
  State<MerchantLoginScreen> createState() => _MerchantLoginScreenState();
}

class _MerchantLoginScreenState extends State<MerchantLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _businessName = TextEditingController();
  final _document = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirmation = TextEditingController();
  bool _creatingAccount = false;
  bool _loading = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _identifier.dispose();
    _businessName.dispose();
    _document.dispose();
    _phone.dispose();
    _password.dispose();
    _passwordConfirmation.dispose();
    super.dispose();
  }

  String? _validateIdentifier(String? value) {
    final identifier = value?.trim() ?? '';
    if (identifier.isEmpty) return 'Informe seu e-mail ou CNPJ.';
    if (_creatingAccount && !_looksLikeEmail(identifier)) {
      return 'Informe um e-mail válido para criar a conta.';
    }
    if (!_creatingAccount &&
        !_looksLikeEmail(identifier) &&
        identifier.replaceAll(RegExp(r'\D'), '').length != 14) {
      return 'Informe um e-mail válido ou um CNPJ com 14 dígitos.';
    }
    return null;
  }

  String? _validateDocument(String? value) {
    if (!_creatingAccount) return null;
    if (!Cnpj.isValid(value ?? '')) {
      return 'Informe um CNPJ válido.';
    }
    return null;
  }

  String? _validateRequired(String? value, String message, int minLength) {
    if ((value ?? '').trim().length < minLength) return message;
    return null;
  }

  bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    return at > 0 && value.indexOf('.', at) > at + 1;
  }

  Future<void> _submit() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });

    try {
      if (_creatingAccount) {
        final hasSession = await widget.authRepository.signUp(
          businessName: _businessName.text,
          email: _identifier.text,
          document: _document.text,
          phone: _phone.text,
          password: _password.text,
        );
        if (mounted && !hasSession) {
          setState(() {
            _message =
                'Cadastro criado. Confirme seu e-mail para acessar o painel.';
          });
        }
      } else {
        await widget.authRepository.signIn(
          identifier: _identifier.text,
          password: _password.text,
        );
      }
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível concluir a operação.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recoverPassword() async {
    final email = _identifier.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() {
        _error = 'Informe seu e-mail para recuperar a senha.';
        _message = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.authRepository.resetPassword(email);
      if (mounted) {
        setState(() {
          _message =
              'Se o e-mail estiver cadastrado, enviaremos as instruções.';
        });
      }
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _creatingAccount = !_creatingAccount;
      _error = null;
      _message = null;
      _password.clear();
      _passwordConfirmation.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
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
                      _creatingAccount
                          ? 'Criar conta do estabelecimento'
                          : 'Acesso do estabelecimento',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _creatingAccount
                          ? 'Informe os dados do estabelecimento e crie seu acesso.'
                          : 'Entre com seu e-mail ou CNPJ e senha.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      key: const Key('merchant_identifier_field'),
                      controller: _identifier,
                      enabled: !_loading,
                      keyboardType: _creatingAccount
                          ? TextInputType.emailAddress
                          : TextInputType.text,
                      textInputAction: TextInputAction.next,
                      autofillHints: _creatingAccount
                          ? const [AutofillHints.email]
                          : const [AutofillHints.username],
                      validator: _validateIdentifier,
                      inputFormatters: _creatingAccount
                          ? const []
                          : [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z0-9@._+/-]'),
                              ),
                            ],
                      decoration: InputDecoration(
                        labelText: _creatingAccount
                            ? 'E-mail'
                            : 'E-mail ou CNPJ',
                        hintText: _creatingAccount
                            ? 'nome@empresa.com.br'
                            : 'nome@empresa.com.br ou 00.000.000/0000-00',
                        prefixIcon: const Icon(
                          Icons.storefront_outlined,
                          color: AppTheme.amber,
                        ),
                      ),
                    ),
                    if (_creatingAccount) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('merchant_signup_business_name_field'),
                        controller: _businessName,
                        enabled: !_loading,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        validator: (value) => _validateRequired(
                          value,
                          'Informe o nome do estabelecimento.',
                          3,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Nome do estabelecimento',
                          prefixIcon: Icon(
                            Icons.storefront_outlined,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('merchant_signup_cnpj_field'),
                        controller: _document,
                        enabled: !_loading,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(14),
                        ],
                        validator: _validateDocument,
                        decoration: const InputDecoration(
                          labelText: 'CNPJ',
                          hintText: '14 dígitos',
                          prefixIcon: Icon(
                            Icons.badge_outlined,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('merchant_signup_phone_field'),
                        controller: _phone,
                        enabled: !_loading,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        validator: (value) => _validateRequired(
                          value,
                          'Informe um telefone válido.',
                          8,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Telefone do estabelecimento',
                          prefixIcon: Icon(
                            Icons.phone_outlined,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('merchant_password_field'),
                      controller: _password,
                      enabled: !_loading,
                      obscureText: true,
                      textInputAction: _creatingAccount
                          ? TextInputAction.next
                          : TextInputAction.done,
                      autofillHints: [
                        _creatingAccount
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      validator: (value) {
                        if ((value ?? '').length < 8) {
                          return 'A senha deve ter pelo menos 8 caracteres.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) {
                        if (!_creatingAccount && !_loading) _submit();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color: AppTheme.amber,
                        ),
                      ),
                    ),
                    if (_creatingAccount) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('merchant_password_confirmation_field'),
                        controller: _passwordConfirmation,
                        enabled: !_loading,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        validator: (value) {
                          if (value != _password.text) {
                            return 'As senhas não conferem.';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) {
                          if (!_loading) _submit();
                        },
                        decoration: const InputDecoration(
                          labelText: 'Confirmar senha',
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      key: const Key('merchant_submit_button'),
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.black,
                              ),
                            )
                          : Text(_creatingAccount ? 'Criar conta' : 'Entrar'),
                    ),
                    if (!_creatingAccount)
                      TextButton(
                        onPressed: _loading ? null : _recoverPassword,
                        child: const Text('Esqueci minha senha'),
                      ),
                    TextButton(
                      onPressed: _loading ? null : _toggleMode,
                      child: Text(
                        _creatingAccount
                            ? 'Já tenho uma conta'
                            : 'Criar conta do estabelecimento',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        key: const Key('merchant_auth_error'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _message!,
                        key: const Key('merchant_auth_message'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.lightGreenAccent,
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
