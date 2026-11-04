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
    this.merchantMode = false,
    this.merchantServiceType = 'rescue',
  });

  final NearbyCall call;
  final Corrida corrida;
  final CorridaRepository repository;
  final bool merchantMode;
  final String merchantServiceType;

  @override
  State<RideRequestWaitScreen> createState() => _RideRequestWaitScreenState();
}

class _RideRequestWaitScreenState extends State<RideRequestWaitScreen> {
  StreamSubscription<Corrida>? _subscription;
  Timer? _autoReturnTimer;
  late Corrida _corrida = widget.corrida;
  String? _error;
  int _selectedStars = 0;
  bool _savingRating = false;
  bool _ratingSubmitted = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.repository
        .watch(widget.corrida.id)
        .listen(
          _updateRide,
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _error = error is CorridaFailure
                  ? error.message
                  : CorridaFailure.syncMessage;
            });
          },
        );
    if (widget.merchantMode) _scheduleAutomaticReturn();
  }

  void _updateRide(Corrida corrida) {
    if (!mounted) return;
    setState(() {
      _corrida = corrida;
      _error = null;
    });
    if (widget.merchantMode && corrida.status == RideStatus.concluida) {
      _scheduleAutomaticReturn();
    }
  }

  void _scheduleAutomaticReturn() {
    if (_autoReturnTimer != null) return;
    _autoReturnTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _returnHome();
    });
  }

  @override
  void dispose() {
    _autoReturnTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_savingRating || _ratingSubmitted || _selectedStars == 0) return;
    setState(() {
      _savingRating = true;
      _error = null;
    });
    try {
      await widget.repository.rateCompletedDriver(
        rideId: _corrida.id,
        stars: _selectedStars,
      );
      if (!mounted) return;
      setState(() => _ratingSubmitted = true);
    } on CorridaFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = CorridaFailure.syncMessage);
    } finally {
      if (mounted) setState(() => _savingRating = false);
    }
  }

  void _returnHome() {
    final navigator = Navigator.of(context);
    if (widget.merchantMode) {
      navigator.popUntil(
        (route) => route.settings.name == '/merchant-portal' || route.isFirst,
      );
    } else {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message =
        widget.merchantMode && widget.merchantServiceType == 'delivery'
        ? switch (_corrida.status) {
            RideStatus.buscandoPrestadores || RideStatus.procurandoMotoboy =>
              'Buscando um motoboy para esta entrega...',
            RideStatus.motoboyACaminho =>
              'O motoboy aceitou e está a caminho para retirar o pedido.',
            RideStatus.aCaminhoDoCliente =>
              'O pedido foi retirado e está a caminho do destino.',
            RideStatus.aguardandoValidacaoEmbarque =>
              'Aguardando confirmação da retirada do pedido.',
            RideStatus.conduzindoDestino => 'A entrega está em andamento.',
            RideStatus.emAndamento => 'A entrega está em andamento.',
            RideStatus.concluida => 'Entrega concluída.',
          }
        : switch (_corrida.status) {
            RideStatus.buscandoPrestadores =>
              'Buscando prestadores para sua corrida...',
            RideStatus.procurandoMotoboy =>
              'Motorista encontrado. Aguardando um motoboy para o resgate...',
            RideStatus.motoboyACaminho =>
              'Um motoboy aceitou o resgate e está a caminho do motorista.',
            RideStatus.aCaminhoDoCliente =>
              'Motorista resgatado. A caminho do ponto de embarque do cliente.',
            RideStatus.aguardandoValidacaoEmbarque =>
              'Motorista chegou ao ponto de embarque. Aguardando validação.',
            RideStatus.conduzindoDestino =>
              'Motorista chegou ao cliente. Aguardando início da corrida.',
            RideStatus.emAndamento => 'Sua corrida está em andamento.',
            RideStatus.concluida => 'Corrida concluída.',
          };
    final completed = _corrida.status == RideStatus.concluida;
    final searching =
        _corrida.status == RideStatus.buscandoPrestadores ||
        _corrida.status == RideStatus.procurandoMotoboy;
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('ride_request_wait_screen'),
        backgroundColor: AppTheme.graphite,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            widget.merchantMode ? 'Chamado do estabelecimento' : 'Sua corrida',
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!completed)
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
                      message,
                      key: const Key('ride_request_status'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: searching ? null : AppTheme.amber,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${widget.call.origin} → ${widget.call.destination}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                    if (widget.merchantMode) ...[
                      const SizedBox(height: 24),
                      _MerchantRideProgress(
                        status: _corrida.status,
                        delivery: widget.merchantServiceType == 'delivery',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Voltando ao painel para novos chamados...',
                        key: Key('merchant_auto_return_message'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                    if (completed && !widget.merchantMode) ...[
                      const SizedBox(height: 28),
                      Text(
                        _ratingSubmitted
                            ? 'Obrigado por avaliar o motorista!'
                            : 'Como foi sua experiência com o motorista?',
                        key: const Key('driver_rating_prompt'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        key: const Key('driver_rating_stars'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var star = 1; star <= 5; star++)
                            IconButton(
                              key: Key('driver_rating_star_$star'),
                              tooltip: '$star estrela${star == 1 ? '' : 's'}',
                              onPressed: _ratingSubmitted || _savingRating
                                  ? null
                                  : () => setState(() => _selectedStars = star),
                              icon: Icon(
                                star <= _selectedStars
                                    ? Icons.star
                                    : Icons.star_border,
                                color: AppTheme.amber,
                                size: 34,
                              ),
                            ),
                        ],
                      ),
                      if (!_ratingSubmitted) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const Key('submit_driver_rating'),
                            onPressed: _selectedStars == 0 || _savingRating
                                ? null
                                : _submitRating,
                            child: _savingRating
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Enviar avaliação'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                    if (completed) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          key: const Key('return_home_after_ride'),
                          onPressed: _returnHome,
                          child: Text(
                            widget.merchantMode
                                ? 'Voltar ao painel'
                                : 'Voltar ao início',
                          ),
                        ),
                      ),
                    ],
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

class _MerchantRideProgress extends StatelessWidget {
  const _MerchantRideProgress({required this.status, required this.delivery});

  final RideStatus status;
  final bool delivery;

  static const _rescueSteps = [
    (RideStatus.buscandoPrestadores, 'Buscando motorista', Icons.search),
    (RideStatus.procurandoMotoboy, 'Buscando motoboy', Icons.two_wheeler),
    (RideStatus.motoboyACaminho, 'Motoboy a caminho', Icons.two_wheeler),
    (RideStatus.aCaminhoDoCliente, 'Resgate em andamento', Icons.route),
    (
      RideStatus.aguardandoValidacaoEmbarque,
      'Aguardando confirmação',
      Icons.fact_check_outlined,
    ),
    (RideStatus.conduzindoDestino, 'A caminho do destino', Icons.navigation),
    (RideStatus.emAndamento, 'Corrida em andamento', Icons.directions_car),
    (RideStatus.concluida, 'Chamado concluído', Icons.check_circle_outline),
  ];

  static const _deliverySteps = [
    (RideStatus.procurandoMotoboy, 'Buscando motoboy', Icons.search),
    (
      RideStatus.motoboyACaminho,
      'Motoboy a caminho da coleta',
      Icons.two_wheeler,
    ),
    (RideStatus.aCaminhoDoCliente, 'Pedido coletado', Icons.inventory_2),
    (RideStatus.conduzindoDestino, 'Entrega em andamento', Icons.route),
    (RideStatus.concluida, 'Entrega concluída', Icons.check_circle_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final steps = delivery ? _deliverySteps : _rescueSteps;
    final currentIndex = steps.indexWhere((step) => step.$1 == status);
    final activeIndex = currentIndex < 0 ? 0 : currentIndex;
    return Column(
      key: const Key('merchant_ride_progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < steps.length; index++)
          _MerchantRideProgressStep(
            key: ValueKey('merchant_ride_progress_$index'),
            label: steps[index].$2,
            icon: steps[index].$3,
            complete: index < activeIndex,
            active: index == activeIndex,
          ),
      ],
    );
  }
}

class _MerchantRideProgressStep extends StatelessWidget {
  const _MerchantRideProgressStep({
    super.key,
    required this.label,
    required this.icon,
    required this.complete,
    required this.active,
  });

  final String label;
  final IconData icon;
  final bool complete;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = complete
        ? Colors.greenAccent
        : active
        ? AppTheme.amber
        : Colors.white38;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: active
            ? AppTheme.amber.withValues(alpha: 0.1)
            : AppTheme.graphiteSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? AppTheme.amber : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (complete)
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18)
          else if (active)
            const Icon(Icons.more_horiz, color: AppTheme.amber, size: 20),
        ],
      ),
    );
  }
}
