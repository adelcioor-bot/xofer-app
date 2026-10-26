import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';
import 'package:xofer/features/ride/presentation/boarding_qr_screen.dart';
import 'package:xofer/prof/domain/corrida.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/incident_report.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/rescue_offer.dart';
import 'package:xofer/prof/domain/rescue_simulation.dart';
import 'package:xofer/prof/domain/ride_status.dart';
import 'package:xofer/prof/presentation/incident_dialog.dart';

class ActiveRescueScreen extends StatefulWidget {
  const ActiveRescueScreen({
    super.key,
    required this.role,
    required this.driver,
    required this.call,
    this.corridaRepository,
    this.motoboyName,
    this.etaMinutes,
    this.motoboyOrigin,
    this.motoboyId = '',
    this.motoboyTarget,
    this.acceptedAt,
    this.tolerance = const Duration(minutes: 3),
    this.now,
    this.documentCapture,
    this.stepInterval = const Duration(seconds: 2),
    this.approachSteps = 4,
    this.clientSteps = 4,
    this.destinationSteps = 6,
  });

  final PartnerRole role;
  final LatLng driver;
  final NearbyCall call;
  final CorridaRepository? corridaRepository;
  final String? motoboyName;
  final int? etaMinutes;
  final LatLng? motoboyOrigin;
  final String motoboyId;
  final LatLng? motoboyTarget;
  final DateTime? acceptedAt;
  final Duration tolerance;
  final DateTime Function()? now;
  final DocumentCapture? documentCapture;
  final Duration stepInterval;
  final int approachSteps;
  final int clientSteps;
  final int destinationSteps;

  @override
  State<ActiveRescueScreen> createState() => _ActiveRescueScreenState();
}

class _ActiveRescueScreenState extends State<ActiveRescueScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late final RescueSimulation _simulation = RescueSimulation.forRole(
    role: widget.role,
    partner: widget.driver,
    client: widget.call.client,
    dropoff: widget.call.dropoff,
    approachSteps: widget.approachSteps,
    clientSteps: widget.clientSteps,
    destinationSteps: widget.destinationSteps,
    motoboyOrigin: widget.motoboyOrigin,
    motoboyTarget: widget.motoboyTarget,
  );
  late final AnimationController _glide;
  late final Future<void> _ready;
  Timer? _timer;
  StreamSubscription<Corrida>? _watch;
  int _segment = 0;
  bool _mapReady = false;
  bool _advancing = false;
  String? _corridaId;
  String? _validationToken;
  String? _reserveCode;
  bool _qrVisible = false;
  String? _syncMessage;
  bool _allowExit = false;
  late final DateTime _acceptedAt = widget.acceptedAt ?? DateTime.now();
  RideStatus _status = RideStatus.procurandoMotoboy;
  String? _motoboyId;
  LatLng? _remoteMotoboyPoint;

  RescueStage get _stage {
    if (_courier &&
        (_status == RideStatus.conduzindoDestino ||
            _status == RideStatus.concluida)) {
      return RescueStage.finished;
    }
    return switch (_status) {
      RideStatus.buscandoPrestadores => RescueStage.motoboyToDriver,
      RideStatus.procurandoMotoboy => RescueStage.motoboyToDriver,
      RideStatus.motoboyACaminho => RescueStage.motoboyToDriver,
      RideStatus.aCaminhoDoCliente => RescueStage.toClientCar,
      RideStatus.aguardandoValidacaoEmbarque => RescueStage.toClientCar,
      RideStatus.emAndamento => RescueStage.toDestination,
      RideStatus.conduzindoDestino => RescueStage.toDestination,
      RideStatus.concluida => RescueStage.finished,
    };
  }

  RescueSpan? get _span {
    if (_stage == RescueStage.finished || !_courier) return null;
    return _simulation.spanFor(_stage);
  }

  LatLng get _moving {
    final span = _span;
    if (span == null) {
      return _courier ? _simulation.client : _simulation.dropoff;
    }
    if (_segment >= span.end) return _simulation.pointAt(span.end);
    return _simulation.glide(_segment, _glide.value);
  }

  String? get _actionLabel =>
      RescuePhaseMachine.actionLabel(_status, widget.role);

  bool get _courier => widget.role == PartnerRole.courier;

  bool get _awaitingMotoboy => !_courier && _motoboyId == null;

  @override
  void initState() {
    super.initState();
    _status = _courier
        ? RideStatus.motoboyACaminho
        : RideStatus.procurandoMotoboy;
    _motoboyId = _courier && widget.motoboyId.isNotEmpty
        ? widget.motoboyId
        : null;
    _glide = AnimationController(vsync: this, duration: widget.stepInterval)
      ..addListener(_onGlide);
    _armTimer();
    _ready = _openCorrida();
  }

  Future<void> _openCorrida() async {
    final repository = widget.corridaRepository;
    if (repository == null) return;
    try {
      final corrida = await repository.open(
        call: widget.call,
        role: widget.role,
        partner: widget.driver,
      );
      if (!mounted) return;
      _corridaId = corrida.id;
      _watch = repository
          .watch(corrida.id)
          .listen(
            _onRemote,
            onError: (Object error) {
              if (!mounted) return;
              setState(() => _syncMessage = _syncText(error));
            },
          );
      _onRemote(corrida);
    } on CorridaFailure catch (error) {
      if (!mounted) return;
      setState(() => _syncMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _syncMessage = CorridaFailure.syncMessage);
    }
  }

  void _onRemote(Corrida corrida) {
    if (!mounted) return;
    _validationToken = corrida.validationToken ?? _validationToken;
    _reserveCode = corrida.reserveCode ?? _reserveCode;
    _motoboyId =
        corrida.motoboyId ??
        (_courier && widget.motoboyId.isNotEmpty ? widget.motoboyId : null);
    _remoteMotoboyPoint =
        corrida.motoboyLatitude != null && corrida.motoboyLongitude != null
        ? LatLng(corrida.motoboyLatitude!, corrida.motoboyLongitude!)
        : null;
    final waiting =
        corrida.status == RideStatus.aguardandoValidacaoEmbarque &&
        _status != RideStatus.aguardandoValidacaoEmbarque;
    if (corrida.status == _status) {
      setState(() {});
    }
    _apply(corrida.status);
    _focus();
    if (waiting) _openQr();
  }

  Future<void> _openQr() async {
    final token = _validationToken;
    if (_qrVisible || token == null || !mounted) return;
    if (_status != RideStatus.aguardandoValidacaoEmbarque) return;
    _qrVisible = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => BoardingQrScreen(
          token: token,
          reserveCode: _reserveCode,
          corridaId: _corridaId,
          repository: widget.corridaRepository,
        ),
      ),
    );
    if (mounted) setState(() => _qrVisible = false);
  }

  Future<void> _arriveAtMeetingPoint() async {
    if (_advancing) return;
    setState(() {
      _advancing = true;
      _syncMessage = null;
    });
    try {
      await _ready;
      final repository = widget.corridaRepository;
      final id = _corridaId;
      if (repository != null && id != null) {
        await repository.beginBoardingValidation(id);
      } else {
        _apply(RideStatus.aguardandoValidacaoEmbarque);
      }
    } on CorridaFailure catch (error) {
      if (!mounted) return;
      setState(() => _syncMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _syncMessage = CorridaFailure.syncMessage);
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  void _apply(RideStatus status) {
    if (status == _status) return;
    _status = status;
    _armTimer();
    if (mounted) setState(() {});
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_courier) return;
    final span = _span;
    if (span == null) return;
    _segment = span.start;
    if (span.start >= span.end) return;
    _glide.forward(from: 0);
    _timer = Timer.periodic(widget.stepInterval, (_) => _tick(span.end));
  }

  void _tick(int end) {
    if (!mounted) return;
    final next = _segment + 1;
    if (next >= end) {
      _timer?.cancel();
      _timer = null;
      _glide.value = 1;
      setState(() => _segment = end);
      _focus();
      return;
    }
    setState(() => _segment = next);
    _glide.forward(from: 0);
  }

  Future<void> _advancePhase() async {
    final next = RescuePhaseMachine.next(_status, widget.role);
    if (next == null || _advancing) return;
    setState(() {
      _advancing = true;
      _syncMessage = null;
    });
    try {
      await _ready;
      final repository = widget.corridaRepository;
      final id = _corridaId;
      if (repository != null && id != null) {
        final updated = await repository.advance(id, next);
        _apply(updated.status);
      } else {
        _apply(next);
      }
    } on CorridaFailure catch (error) {
      if (!mounted) return;
      setState(() => _syncMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _syncMessage = CorridaFailure.syncMessage);
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  String _syncText(Object error) {
    if (error is CorridaFailure) return error.message;
    return CorridaFailure.syncMessage;
  }

  bool get _withinTolerance {
    final elapsed = (widget.now ?? DateTime.now)().difference(_acceptedAt);
    return elapsed <= widget.tolerance;
  }

  Future<void> _reportIncident() async {
    if (_advancing) return;
    if (_withinTolerance) {
      await _releaseWithoutPenalty();
      return;
    }
    final draft = await showIncidentDialog(
      context: context,
      documentCapture: widget.documentCapture,
    );
    if (draft == null || !mounted) return;
    setState(() {
      _advancing = true;
      _syncMessage = null;
    });
    try {
      await _ready;
      final repository = widget.corridaRepository;
      final id = _corridaId;
      if (repository != null && id != null) {
        await repository.reportIncident(
          IncidentReport(
            corridaId: id,
            motoboyId: widget.motoboyId,
            reason: draft.reason,
            photoBytes: draft.photo.bytes,
            acceptedAt: _acceptedAt,
            penalized: true,
          ),
        );
      }
      _exitToRadar();
    } on CorridaFailure catch (error) {
      if (!mounted) return;
      setState(() => _syncMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _syncMessage = CorridaFailure.syncMessage);
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Future<void> _releaseWithoutPenalty() async {
    setState(() {
      _advancing = true;
      _syncMessage = null;
    });
    try {
      await _ready;
      final repository = widget.corridaRepository;
      final id = _corridaId;
      if (repository != null && id != null) {
        await repository.releaseToQueue(id);
      }
      _exitToRadar();
    } on CorridaFailure catch (error) {
      if (!mounted) return;
      setState(() => _syncMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _syncMessage = CorridaFailure.syncMessage);
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  void _exitToRadar() {
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    });
  }

  void _onGlide() {
    if (!mounted) return;
    setState(() {});
    _focus();
  }

  void _focus() {
    if (!_mapReady || !mounted) return;
    if (_courier) {
      if (_stage == RescueStage.finished) return;
      _mapController.move(_moving, _mapController.camera.zoom);
      return;
    }
    _mapController.move(
      _remoteMotoboyPoint ?? widget.driver,
      _mapController.camera.zoom,
    );
  }

  String _phaseLabel() {
    if (_awaitingMotoboy) {
      return 'Aguardando um Motoboy para resgate...';
    }
    if (_courier) {
      return switch (_stage) {
        RescueStage.motoboyToDriver => 'Indo ao encontro do motorista',
        RescueStage.toClientCar => 'Levando o motorista até o carro do cliente',
        RescueStage.finished => 'Missão concluída',
        RescueStage.toDestination => 'Missão concluída',
      };
    }
    final assigned = widget.motoboyName;
    final eta = widget.etaMinutes;
    return switch (_stage) {
      RescueStage.motoboyToDriver when assigned != null && eta != null =>
        assignedMotoboyMessage(assigned, eta),
      RescueStage.motoboyToDriver => 'Motoboy a caminho do seu encontro',
      RescueStage.toClientCar => 'A caminho do carro do cliente',
      RescueStage.toDestination => 'Navegação até o destino',
      RescueStage.finished => 'Corrida concluída',
    };
  }

  @override
  void dispose() {
    _watch?.cancel();
    _timer?.cancel();
    _glide
      ..removeListener(_onGlide)
      ..dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_courier && _stage == RescueStage.finished) {
      return _MissionComplete(origin: widget.call.origin);
    }

    final theme = Theme.of(context);
    final showMotoboy =
        _courier || (_motoboyId != null && _remoteMotoboyPoint != null);
    final motoboyPoint = _courier ? _moving : _remoteMotoboyPoint;
    final driverPoint = _courier
        ? (_stage == RescueStage.motoboyToDriver
              ? _simulation.partner
              : _moving)
        : widget.driver;
    final driverIcon =
        !_courier &&
            (_stage == RescueStage.toDestination ||
                _stage == RescueStage.finished)
        ? Icons.directions_car
        : Icons.person;
    final route = _courier
        ? (_span == null
              ? _simulation.routePoints
              : _simulation.pointsFor(_stage))
        : showMotoboy
        ? [motoboyPoint!, widget.driver]
        : const <LatLng>[];

    return PopScope(
      canPop: !_courier || _allowExit,
      child: Scaffold(
        backgroundColor: AppTheme.graphite,
        appBar: AppBar(
          automaticallyImplyLeading: !_courier,
          title: Text(_courier ? 'Resgate ativo' : 'Corrida ativa'),
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.driver,
                initialZoom: 15,
                onMapReady: () {
                  _mapReady = true;
                  _focus();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.xofer.prof',
                ),
                if (route.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route,
                        color: AppTheme.amber,
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      key: const Key('client_car_marker'),
                      point: widget.call.client,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.directions_car_filled,
                        color: AppTheme.amber,
                        size: 28,
                      ),
                    ),
                    if (!_courier)
                      Marker(
                        key: const Key('dropoff_marker'),
                        point: widget.call.dropoff,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(
                          Icons.location_on,
                          color: AppTheme.amber,
                          size: 36,
                        ),
                      ),
                    if (showMotoboy)
                      Marker(
                        key: const Key('rescue_motoboy_marker'),
                        point: motoboyPoint!,
                        width: 36,
                        height: 36,
                        child: _ActorPin(
                          icon: Icons.two_wheeler,
                          iconKey: const Key('rescue_motoboy_icon'),
                        ),
                      ),
                    Marker(
                      key: const Key('rescue_driver_marker'),
                      point: _courier && _stage != RescueStage.motoboyToDriver
                          ? LatLng(
                              driverPoint.latitude + 0.0008,
                              driverPoint.longitude + 0.0008,
                            )
                          : driverPoint,
                      width: 36,
                      height: 36,
                      child: _ActorPin(
                        icon: driverIcon,
                        iconKey: const Key('rescue_driver_icon'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Material(
                    key: const Key('active_rescue_screen'),
                    color: AppTheme.graphiteSurface,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _phaseLabel(),
                            key: const Key('rescue_status'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppTheme.amber,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_courier || _motoboyId != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.two_wheeler,
                                  key: Key('legend_motoboy'),
                                  color: AppTheme.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                const Text('Motoboy'),
                                const SizedBox(width: 16),
                                Icon(
                                  driverIcon,
                                  key: const Key('legend_driver'),
                                  color: AppTheme.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                const Text('Motorista'),
                              ],
                            ),
                          if (_awaitingMotoboy) ...[
                            const SizedBox(height: 12),
                            const Row(
                              key: Key('rescue_search_active'),
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.amber,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(child: Text('Busca de resgate ativa')),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(widget.call.origin),
                          if (!_courier)
                            Text(
                              widget.call.destination,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          if (!_courier &&
                              _status == RideStatus.conduzindoDestino) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Siga com o carro do cliente até ${widget.call.destination}.',
                              key: const Key('navigation_hint'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                          if (_syncMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _syncMessage!,
                              key: const Key('corrida_sync_error'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            formatBrl(widget.call.driverFare),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (_actionLabel != null) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                key: const Key('advance_phase_button'),
                                onPressed: _advancing ? null : _advancePhase,
                                child: Text(_actionLabel!),
                              ),
                            ),
                          ],
                          if (!_courier &&
                              _status == RideStatus.aCaminhoDoCliente) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                key: const Key('arrived_meeting_point_button'),
                                onPressed: _advancing
                                    ? null
                                    : _arriveAtMeetingPoint,
                                child: const Text(
                                  'Cheguei ao Ponto de Encontro',
                                ),
                              ),
                            ),
                          ],
                          if (_courier) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                key: const Key('report_incident_button'),
                                onPressed: _advancing ? null : _reportIncident,
                                child: const Text('Reportar Imprevisto'),
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
          ],
        ),
      ),
    );
  }
}

class _ActorPin extends StatelessWidget {
  const _ActorPin({required this.icon, required this.iconKey});

  final IconData icon;
  final Key iconKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.graphite,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.amber, width: 2),
      ),
      child: Icon(icon, key: iconKey, color: AppTheme.amber, size: 18),
    );
  }
}

class _MissionComplete extends StatelessWidget {
  const _MissionComplete({required this.origin});

  final String origin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('mission_complete_screen'),
      backgroundColor: AppTheme.graphite,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppTheme.amber,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Missão concluída',
                    key: const Key('rescue_status'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: AppTheme.amber,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Você deixou o motorista no carro do cliente em $origin.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    key: const Key('back_to_radar_button'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Voltar ao radar'),
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
