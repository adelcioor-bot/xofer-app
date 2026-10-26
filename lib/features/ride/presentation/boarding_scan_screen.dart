import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/ride/presentation/boarding_scanner.dart';

class MobileBoardingScanner implements BoardingScanner {
  const MobileBoardingScanner();

  @override
  Future<BoardingScanResult?> scan(
    BuildContext context, {
    required Future<String?> Function(String code) confirmReserveCode,
  }) {
    return Navigator.of(context).push<BoardingScanResult>(
      MaterialPageRoute(
        builder: (context) =>
            BoardingScanScreen(confirmReserveCode: confirmReserveCode),
      ),
    );
  }
}

class BoardingScanScreen extends StatefulWidget {
  const BoardingScanScreen({super.key, required this.confirmReserveCode});

  final Future<String?> Function(String code) confirmReserveCode;

  @override
  State<BoardingScanScreen> createState() => _BoardingScanScreenState();
}

class _BoardingScanScreenState extends State<BoardingScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final TextEditingController _reserveCodeController = TextEditingController();
  bool _done = false;
  bool _manualEntry = false;
  bool _isConfirmingReserveCode = false;

  @override
  void dispose() {
    _controller.dispose();
    _reserveCodeController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    String? value;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        value = raw;
        break;
      }
    }
    if (value == null) return;
    _done = true;
    Navigator.of(context).pop(BoardingScanResult.qr(value));
  }

  Future<void> _confirmReserveCode() async {
    final code = _reserveCodeController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(code) || _isConfirmingReserveCode) {
      return;
    }

    setState(() => _isConfirmingReserveCode = true);
    try {
      final error = await widget.confirmReserveCode(code);
      if (!mounted) return;
      if (error != null) {
        _reserveCodeController.clear();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        return;
      }

      _done = true;
      Navigator.of(context).pop(BoardingScanResult.reserveCode(code));
    } catch (_) {
      if (!mounted) return;
      _reserveCodeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível confirmar o código. Tente novamente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isConfirmingReserveCode = false);
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível alternar a lanterna.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('boarding_scan_screen'),
      backgroundColor: AppTheme.graphite,
      appBar: AppBar(title: const Text('Escanear QR Code')),
      body: _manualEntry ? _buildManualEntry() : _buildCamera(),
    );
  }

  Widget _buildCamera() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Positioned(
          right: 20,
          top: 20,
          child: SafeArea(
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                final isAvailable =
                    state.isInitialized &&
                    state.isRunning &&
                    state.torchState != TorchState.unavailable;
                final isOn = state.torchState == TorchState.on;
                final icon = state.torchState == TorchState.unavailable
                    ? Icons.no_flash
                    : isOn
                    ? Icons.flash_on
                    : Icons.flash_off;

                return FloatingActionButton.small(
                  key: const Key('toggle_torch_button'),
                  heroTag: 'boarding_scan_torch',
                  tooltip: isAvailable
                      ? (isOn ? 'Desligar lanterna' : 'Ligar lanterna')
                      : 'Lanterna indisponível',
                  onPressed: isAvailable ? _toggleTorch : null,
                  backgroundColor: AppTheme.graphiteSurface,
                  foregroundColor: AppTheme.amber,
                  child: Icon(icon),
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 20,
          child: SafeArea(
            child: TextButton(
              key: const Key('manual_reserve_code_button'),
              onPressed: () => setState(() => _manualEntry = true),
              style: TextButton.styleFrom(
                backgroundColor: AppTheme.graphiteSurface.withValues(
                  alpha: 0.9,
                ),
              ),
              child: const Text(
                'Não consigo escanear? Digitar código manual',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualEntry() {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pin_outlined, size: 52, color: AppTheme.amber),
                const SizedBox(height: 16),
                Text(
                  'Digite o código reserva de 4 dígitos',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('reserve_code_field'),
                  controller: _reserveCodeController,
                  autofocus: true,
                  enabled: !_isConfirmingReserveCode,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 4,
                  onChanged: (_) => setState(() {}),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: AppTheme.amber,
                    letterSpacing: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '••••',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const Key('confirm_reserve_code_button'),
                    onPressed:
                        !_isConfirmingReserveCode &&
                            RegExp(r'^\d{4}$')
                                .hasMatch(_reserveCodeController.text)
                        ? _confirmReserveCode
                        : null,
                    child: _isConfirmingReserveCode
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirmar Código'),
                  ),
                ),
                TextButton(
                  key: const Key('back_to_qr_button'),
                  onPressed: _isConfirmingReserveCode
                      ? null
                      : () => setState(() => _manualEntry = false),
                  child: const Text('Voltar ao leitor QR'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
