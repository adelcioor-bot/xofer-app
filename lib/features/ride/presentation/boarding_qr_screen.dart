import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/ride/domain/boarding_token.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/corrida.dart';
import 'package:xofer/prof/domain/ride_status.dart';

class BoardingQrScreen extends StatefulWidget {
  const BoardingQrScreen({
    super.key,
    required this.token,
    this.reserveCode,
    this.corridaId,
    this.repository,
  });

  final String token;
  final String? reserveCode;
  final String? corridaId;
  final CorridaRepository? repository;

  @override
  State<BoardingQrScreen> createState() => _BoardingQrScreenState();
}

class _BoardingQrScreenState extends State<BoardingQrScreen> {
  StreamSubscription<Corrida>? _watch;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    final id = widget.corridaId;
    if (repository == null || id == null) return;
    _watch = repository.watch(id).listen((corrida) {
      if (!mounted || _closed) return;
      if (corrida.status == RideStatus.emAndamento ||
          corrida.status == RideStatus.conduzindoDestino) {
        _closed = true;
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('boarding_qr_screen'),
      backgroundColor: AppTheme.graphite,
      appBar: AppBar(title: const Text('Validação de embarque')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.amber, width: 3),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: QrImageView(
                        key: const Key('boarding_qr'),
                        data: widget.token,
                        size: 240,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  if (widget.reserveCode != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Código Reserva: ${widget.reserveCode}',
                      key: const Key('boarding_reserve_code'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: AppTheme.amber,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    boardingQrInstruction,
                    key: const Key('boarding_qr_instruction'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      height: 1.35,
                    ),
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
