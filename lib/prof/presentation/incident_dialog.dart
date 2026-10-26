import 'package:flutter/material.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/incident_report.dart';
import 'package:xofer/prof/domain/provider_account.dart';

class IncidentDraft {
  const IncidentDraft({required this.reason, required this.photo});

  final IncidentReason reason;
  final CapturedDocument photo;
}

Future<IncidentDraft?> showIncidentDialog({
  required BuildContext context,
  required DocumentCapture? documentCapture,
}) {
  return showDialog<IncidentDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _IncidentDialog(documentCapture: documentCapture),
  );
}

class _IncidentDialog extends StatefulWidget {
  const _IncidentDialog({required this.documentCapture});

  final DocumentCapture? documentCapture;

  @override
  State<_IncidentDialog> createState() => _IncidentDialogState();
}

class _IncidentDialogState extends State<_IncidentDialog> {
  IncidentReason? _reason;
  CapturedDocument? _photo;
  String? _message;
  bool _openingCamera = false;

  bool get _canConfirm => _reason != null && _photo != null && !_openingCamera;

  Future<void> _takePhoto() async {
    final capture = widget.documentCapture;
    if (capture == null) {
      setState(() => _message = 'A câmara do telemóvel não está disponível.');
      return;
    }
    setState(() {
      _openingCamera = true;
      _message = null;
    });
    try {
      final photo = await capture.pick(DocumentSource.camera);
      if (!mounted) return;
      setState(() {
        if (photo == null) {
          _message = 'Tire uma foto da via ou da moto para confirmar.';
        } else {
          _photo = photo;
          _message = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Não foi possível abrir a câmara.');
    } finally {
      if (mounted) setState(() => _openingCamera = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('incident_modal'),
      backgroundColor: AppTheme.graphiteSurface,
      title: const Text('Reportar imprevisto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final reason in IncidentReason.values)
              ListTile(
                key: Key('incident_reason_${reason.wire}'),
                contentPadding: EdgeInsets.zero,
                selected: _reason == reason,
                selectedColor: AppTheme.amber,
                leading: Icon(
                  _reason == reason
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: AppTheme.amber,
                ),
                title: Text(reason.label),
                onTap: () => setState(() => _reason = reason),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('incident_camera_button'),
              onPressed: _openingCamera ? null : _takePhoto,
              icon: const Icon(Icons.photo_camera, color: AppTheme.amber),
              label: Text(_photo == null ? 'Tirar foto' : 'Tirar outra foto'),
            ),
            if (_photo != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Foto pronta para envio.',
                key: Key('incident_photo_ready'),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                key: const Key('incident_dialog_error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('incident_back_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Voltar ao resgate'),
        ),
        ElevatedButton(
          key: const Key('confirm_incident_button'),
          onPressed: _canConfirm
              ? () => Navigator.of(context).pop(
                    IncidentDraft(reason: _reason!, photo: _photo!),
                  )
              : null,
          child: const Text('Confirmar Imprevisto'),
        ),
      ],
    );
  }
}
