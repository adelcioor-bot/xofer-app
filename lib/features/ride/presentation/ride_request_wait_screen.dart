import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/prof/domain/corrida.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/ride_status.dart';

class RideRequestWaitScreen extends StatefulWidget {
  const RideRequestWaitScreen({
    super.key,
    required this.call,
    required this.corrida,
    required this.repository,
  });

  final NearbyCall call;
  final Corrida corrida;
  final CorridaRepository repository;

  @override
  State<RideRequestWaitScreen> createState() => _RideRequestWaitScreenState();
}

class _RideRequestWaitScreenState extends State<RideRequestWaitScreen> {
  StreamSubscription<Corrida>? _subscription;
  late Corrida _corrida = widget.corrida;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.repository
        .watch(widget.corrida.id)
        .listen(
          (corrida) {
            if (!mounted) return;
            setState(() {
              _corrida = corrida;
              _error = null;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _error = error is CorridaFailure
                  ? error.message
                  : CorridaFailure.syncMessage;
            });
          },
        );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waitingForMotoboy =
        _corrida.motoboyId == null &&
        (_corrida.status == RideStatus.procurandoMotoboy ||
            _corrida.acceptedBy != null);
    final accepted = _corrida.acceptedBy != null || _corrida.motoboyId != null;
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('ride_request_wait_screen'),
        backgroundColor: AppTheme.graphite,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Sua corrida'),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!accepted || waitingForMotoboy)
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(color: AppTheme.amber),
                      )
                    else
                      const Icon(
                        Icons.check_circle_outline,
                        color: AppTheme.amber,
                        size: 40,
                      ),
                    const SizedBox(height: 24),
                    Text(
                      waitingForMotoboy
                          ? 'Motorista encontrado. Aguardando um motoboy para o resgate...'
                          : _corrida.motoboyId != null
                          ? 'Um motoboy aceitou o resgate.'
                          : accepted
                          ? 'Um motorista aceitou sua corrida.'
                          : 'Buscando prestadores para sua corrida...',
                      key: const Key('ride_request_status'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${widget.call.origin} → ${widget.call.destination}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        key: const Key('ride_request_sync_error'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Colors.white70),
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
