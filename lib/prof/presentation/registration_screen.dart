import 'package:flutter/material.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/profile/data/cpf.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/provider_account.dart';
import 'package:xofer/prof/domain/provider_failure.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.role,
    required this.phone,
    required this.documentCapture,
    required this.onSubmit,
    required this.onCompleted,
  });

  final PartnerRole role;
  final String phone;
  final DocumentCapture documentCapture;
  final Future<ProviderAccount> Function(ProviderApplication application) onSubmit;
  final ValueChanged<ProviderAccount> onCompleted;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _nameController = TextEditingController();
  final _documentController = TextEditingController();
  final _emailController = TextEditingController();
  int _step = 0;
  bool _saving = false;
  String? _errorMessage;
  CapturedDocument? _cnh;
  CapturedDocument? _criminalRecord;
  CapturedDocument? _crlv;
  CapturedDocument? _selfie;

  bool get _needsCrlv => widget.role == PartnerRole.courier;

  @override
  void dispose() {
    _nameController.dispose();
    _documentController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _nextFromBasics() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.length < 5 || !email.contains('@') || !Cpf.isValid(_documentController.text)) {
      setState(() => _errorMessage = 'Informe nome, CPF válido e e-mail.');
      return;
    }
    setState(() {
      _errorMessage = null;
      _step = 1;
    });
  }

  void _nextFromDocuments() {
    if (_cnh == null || _criminalRecord == null || (_needsCrlv && _crlv == null)) {
      setState(() => _errorMessage = 'Anexe todos os documentos pedidos.');
      return;
    }
    setState(() {
      _errorMessage = null;
      _step = 2;
    });
  }

  Future<void> _capture(void Function(CapturedDocument file) assign) async {
    setState(() => _errorMessage = null);
    try {
      final file = await widget.documentCapture.pick(DocumentSource.camera);
      if (file == null || !mounted) return;
      setState(() => assign(file));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Não foi possível abrir a câmera.');
    }
  }

  Future<void> _submit() async {
    final cnh = _cnh;
    final criminalRecord = _criminalRecord;
    final selfie = _selfie;
    if (cnh == null || criminalRecord == null || selfie == null) {
      setState(() => _errorMessage = 'A selfie com a CNH é obrigatória.');
      return;
    }
    if (_needsCrlv && _crlv == null) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final saved = await widget.onSubmit(
        ProviderApplication(
          role: widget.role,
          fullName: _nameController.text.trim(),
          document: Cpf.digitsOnly(_documentController.text),
          phone: widget.phone,
          email: _emailController.text.trim(),
          cnh: cnh,
          criminalRecord: criminalRecord,
          crlv: _crlv,
          selfie: selfie,
        ),
      );
      if (!mounted) return;
      widget.onCompleted(saved);
    } on ProviderFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Não foi possível enviar o cadastro.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Cadastro ${widget.role.title}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Passo ${_step + 1} de 3',
              style: theme.textTheme.labelLarge?.copyWith(color: AppTheme.amber),
            ),
            const SizedBox(height: 12),
            if (_step == 0) ...[
              TextField(
                key: const Key('registration_name'),
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome completo'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('registration_document'),
                controller: _documentController,
                keyboardType: TextInputType.number,
                inputFormatters: [CpfInputFormatter()],
                decoration: const InputDecoration(labelText: 'CPF'),
              ),
              const SizedBox(height: 12),
              Text(
                'Telefone',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppTheme.amber,
                ),
              ),
              Text(
                widget.phone,
                key: const Key('registration_phone'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('registration_email'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
            ],
            if (_step == 1) ...[
              _DocumentTile(
                tileKey: const Key('document_cnh'),
                title: 'CNH',
                subtitle: widget.role == PartnerRole.driver
                    ? 'Com a observação EAR — Exerce Atividade Remunerada'
                    : 'Categoria A',
                fileName: _cnh?.name,
                onCapture: () => _capture((file) => _cnh = file),
              ),
              _DocumentTile(
                tileKey: const Key('document_criminal'),
                title: 'Certidão de antecedentes criminais',
                subtitle: 'Polícia Federal, em foto nítida',
                fileName: _criminalRecord?.name,
                onCapture: () => _capture((file) => _criminalRecord = file),
              ),
              if (_needsCrlv)
                _DocumentTile(
                  tileKey: const Key('document_crlv'),
                  title: 'CRLV da moto',
                  subtitle: 'Documento atualizado',
                  fileName: _crlv?.name,
                  onCapture: () => _capture((file) => _crlv = file),
                ),
            ],
            if (_step == 2)
              _DocumentTile(
                tileKey: const Key('document_selfie'),
                title: 'Selfie com a CNH',
                subtitle: 'Rosto ao lado do documento, com boa luz',
                fileName: _selfie?.name,
                onCapture: () => _capture((file) => _selfie = file),
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                key: const Key('registration_error'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.redAccent,
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              key: const Key('registration_continue'),
              onPressed: _saving
                  ? null
                  : switch (_step) {
                      0 => _nextFromBasics,
                      1 => _nextFromDocuments,
                      _ => _submit,
                    },
              child: Text(
                _step == 2 ? 'Enviar para análise' : 'Continuar',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.tileKey,
    required this.title,
    required this.subtitle,
    required this.fileName,
    required this.onCapture,
  });

  final Key tileKey;
  final String title;
  final String subtitle;
  final String? fileName;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final attached = fileName != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.graphiteSurface,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                attached ? fileName! : subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: tileKey,
                onPressed: onCapture,
                icon: Icon(
                  attached ? Icons.check_circle : Icons.photo_camera,
                  color: AppTheme.amber,
                ),
                label: Text(attached ? 'Trocar foto' : 'Abrir câmera'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
