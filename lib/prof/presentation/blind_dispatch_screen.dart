import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/dispatch_attempt.dart';
import 'package:xofer/prof/domain/dispatch_repository.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/data/supabase_dispatch_repository.dart';
import 'package:xofer/prof/presentation/active_rescue_screen.dart';

class BlindDispatchScreen extends StatefulWidget {
  const BlindDispatchScreen({
    super.key,
    this.role = PartnerRole.driver,
    required this.partnerId,
    required this.locationRepository,
    required this.corridaRepository,
    required this.onSignOut,
    this.dispatchRepository,
    this.documentCapture,
    this.now,
  });

  final PartnerRole role;
  final String partnerId;
  final LocationRepository locationRepository;
  final CorridaRepository? corridaRepository;
  final DispatchRepository? dispatchRepository;
  final Future<void> Function() onSignOut;
  final DocumentCapture? documentCapture;
  final DateTime Function()? now;

  @override
  State<BlindDispatchScreen> createState() => _BlindDispatchScreenState();
}

class _BlindDispatchScreenState extends State<BlindDispatchScreen> {
  late final DispatchRepository _dispatchRepository =
      widget.dispatchRepository ?? SupabaseDispatchRepository();
  StreamSubscription<DispatchAttempt>? _attemptSubscription;
  Timer? _presenceTimer;
  LatLng? _location;
  String? _connectionError;
  bool _updatingLocation = true;
  bool _dialogOpen = false;
  bool _signingOut = false;
  bool _refreshingPresence = false;
  bool _missionActive = false;
  String? _acceptedRideId;
  bool _openingAcceptedRide = false;

  @override
  void initState() {
    super.initState();
    _listenForAttempts();
    unawaited(_refreshPresence());
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshPresence()),
    );
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _attemptSubscription?.cancel();
    unawaited(
      _dispatchRepository
          .updatePresence(
            role: widget.role,
            location: _location,
            isAvailable: false,
          )
          .catchError((Object error) {
            debugPrint('Could not mark driver unavailable: $error');
          }),
    );
    super.dispose();
  }

  void _listenForAttempts() {
    try {
      _attemptSubscription = _dispatchRepository
          .watchAttempts(providerId: widget.partnerId, role: widget.role)
          .listen(
            _onAttempt,
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('Dispatch listener failed: $error');
              if (mounted) {
                setState(
                  () => _connectionError = error is CorridaFailure
                      ? error.message
                      : 'Não foi possível conectar ao despacho. Tente novamente.',
                );
              }
            },
          );
    } catch (error, stackTrace) {
      debugPrint('Could not subscribe to dispatch attempts: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(
          () => _connectionError =
              'Não foi possível conectar ao despacho. Tente novamente.',
        );
      }
    }
  }

  void _onAttempt(DispatchAttempt attempt) {
    if (!mounted) return;
    if (attempt.providerRole != widget.role.wire ||
        attempt.status != 'offered' ||
        !attempt.expiresAt.isAfter(DateTime.now())) {
      return;
    }
    setState(() => _connectionError = null);
    if (_dialogOpen) return;
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showMission(attempt));
    });
  }

  Future<void> _showMission(DispatchAttempt attempt) async {
    final response = await showDialog<MissionResponse>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BlindMissionDialog(
        attempt: attempt,
        idleBalanceAtRisk: widget.role == PartnerRole.driver,
        now: widget.now,
        onRespond: (response) => _dispatchRepository.respondToMission(
          attemptId: attempt.id,
          providerId: widget.partnerId,
          response: response,
        ),
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;
    if (response?.status == 'expired' &&
        widget.role == PartnerRole.driver) {
      _showIdleResetNotice();
      return;
    }
    if (response?.status != 'accepted') return;
    final rideId = response?.rideId;
    if (rideId == null) {
      _showError('A missão foi aceita, mas não foi possível abrir a corrida.');
      return;
    }
    _missionActive = true;
    setState(() => _acceptedRideId = rideId);
    await _openAcceptedRide(rideId);
  }

  Future<void> _openAcceptedRide(String rideId) async {
    if (_openingAcceptedRide) return;
    _openingAcceptedRide = true;
    try {
      final call = await _dispatchRepository.loadAcceptedRide(
        rideId,
        role: widget.role,
      );
      final location = _location;
      if (location == null) {
        throw const CorridaFailure(
          'Sua localização não está disponível para iniciar a navegação.',
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ActiveRescueScreen(
            role: widget.role,
            driver: location,
            call: call,
            corridaRepository: widget.corridaRepository,
            blindDispatch: true,
            motoboyOrigin: widget.role == PartnerRole.courier ? location : null,
            motoboyTarget: call.meetingPoint,
            acceptedAt: DateTime.now(),
            documentCapture: widget.documentCapture,
          ),
        ),
      );
      if (mounted) {
        _missionActive = false;
        setState(() => _acceptedRideId = null);
        await _refreshPresence();
      }
    } on CorridaFailure catch (error) {
      if (mounted) _showError(error.message);
    } catch (error, stackTrace) {
      debugPrint('Could not open accepted mission: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _showError(CorridaFailure.syncMessage);
    } finally {
      _openingAcceptedRide = false;
    }
  }

  Future<void> _refreshPresence() async {
    if (_refreshingPresence || _missionActive) return;
    _refreshingPresence = true;
    try {
      final location = await widget.locationRepository.currentLocation();
      final point = LatLng(location.latitude, location.longitude);
      await _dispatchRepository.updatePresence(
        role: widget.role,
        location: point,
        isAvailable: true,
      );
      if (!mounted) return;
      setState(() {
        _location = point;
        _updatingLocation = false;
        _connectionError = null;
      });
    } on LocationFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _updatingLocation = false;
        _connectionError = _locationFailureMessage(error.reason);
      });
    } on CorridaFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _updatingLocation = false;
        _connectionError = error.message;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not update driver presence: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _updatingLocation = false;
          _connectionError = 'Não foi possível atualizar sua localização.';
        });
      }
    } finally {
      _refreshingPresence = false;
    }
  }

  String _locationFailureMessage(LocationFailureReason reason) {
    return switch (reason) {
      LocationFailureReason.serviceDisabled =>
        'Ative o serviço de localização para receber missões.',
      LocationFailureReason.permissionDenied ||
      LocationFailureReason.permissionDeniedForever =>
        'Permita o acesso à localização para receber missões.',
      LocationFailureReason.unavailable =>
        'Não foi possível obter sua localização.',
    };
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await _dispatchRepository.updatePresence(
        role: widget.role,
        location: _location,
        isAvailable: false,
      );
      await widget.onSignOut();
    } on CorridaFailure catch (error) {
      _showError(error.message);
    } catch (error, stackTrace) {
      debugPrint('Could not sign driver out: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showError('Não foi possível encerrar a sessão. Tente novamente.');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showIdleResetNotice() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'O saldo de espera foi zerado por inatividade.',
            key: Key('idle_reset_snackbar'),
          ),
        ),
      );
  }

  Future<void> _retryConnection() async {
    await _attemptSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _connectionError = null;
      _updatingLocation = true;
    });
    _listenForAttempts();
    await _refreshPresence();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acceptedRideId = _acceptedRideId;
    return Scaffold(
      key: const Key('blind_dispatch_screen'),
      appBar: AppBar(
        title: Text(
          widget.role == PartnerRole.driver
              ? 'Área do motorista'
              : 'Área do resgatador',
        ),
        actions: [
          IconButton(
            key: const Key('partner_sign_out'),
            tooltip: 'Terminar sessão',
            onPressed: _signingOut ? null : _signOut,
            icon: _signingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                acceptedRideId == null
                    ? Icons.notifications_active_outlined
                    : Icons.check_circle_outline,
                size: 56,
              ),
              const SizedBox(height: 20),
              Text(
                acceptedRideId == null
                    ? 'Aguardando nova missão'
                    : 'Missão aceita',
                key: Key(
                  acceptedRideId == null
                      ? 'dispatch_waiting_title'
                      : 'dispatch_accepted_title',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (acceptedRideId != null)
                Column(
                  children: [
                    const Text('Abrindo a navegação da corrida.'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const Key('retry_open_accepted_ride'),
                      onPressed: _openingAcceptedRide
                          ? null
                          : () => _openAcceptedRide(acceptedRideId),
                      child: _openingAcceptedRide
                          ? const CircularProgressIndicator()
                          : const Text('Abrir corrida'),
                    ),
                  ],
                )
              else if (_updatingLocation)
                const CircularProgressIndicator()
              else
                Text(
                  _connectionError == null
                      ? 'Você receberá uma notificação quando houver uma missão.'
                      : _connectionError!,
                  key: const Key('dispatch_connection_status'),
                  textAlign: TextAlign.center,
                ),
              if (_connectionError != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _retryConnection,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class BlindMissionDialog extends StatefulWidget {
  const BlindMissionDialog({
    super.key,
    required this.attempt,
    required this.onRespond,
    this.idleBalanceAtRisk = false,
    this.now,
  });

  static const offerSeconds = 45;
  static const graceSeconds = 15;
  static const idleWarning =
      'Atenção: Recusar ou ignorar este chamado zerará o saldo acumulado nesta janela de espera.';

  final DispatchAttempt attempt;
  final Future<MissionResponse> Function(String response) onRespond;
  final bool idleBalanceAtRisk;
  final DateTime Function()? now;

  @override
  State<BlindMissionDialog> createState() => _BlindMissionDialogState();
}

class _BlindMissionDialogState extends State<BlindMissionDialog>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _pulse;
  String? _respondingTo;
  String? _errorMessage;
  int _remainingSeconds = 0;
  bool _closed = false;

  bool get _responding => _respondingTo != null;

  bool get _inNetworkGrace =>
      _remainingSeconds <= BlindMissionDialog.graceSeconds;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _updateCountdown();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _closed) return;
      setState(_updateCountdown);
      if (_remainingSeconds == 0 && !_responding) _closeAsExpired();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _updateCountdown() {
    final milliseconds = widget.attempt.expiresAt
        .difference(_now)
        .inMilliseconds;
    final seconds = (milliseconds / 1000).ceil();
    _remainingSeconds = math.min(
      BlindMissionDialog.offerSeconds,
      math.max(0, seconds),
    );
  }

  void _closeAsExpired() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(const MissionResponse(status: 'expired'));
  }

  Future<void> _respond(String response) async {
    if (_responding || _remainingSeconds == 0) return;
    setState(() {
      _respondingTo = response;
      _errorMessage = null;
    });
    try {
      final result = await widget.onRespond(response);
      if (mounted) Navigator.of(context).pop(result);
    } catch (error, stackTrace) {
      debugPrint('Could not respond to blind mission: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      if (widget.attempt.expiresAt.isAfter(_now)) {
        setState(() {
          _respondingTo = null;
          _errorMessage = error is CorridaFailure
              ? error.message
              : 'Não foi possível responder. Tente novamente.';
        });
      } else {
        _closeAsExpired();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remainingSeconds / BlindMissionDialog.offerSeconds;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('blind_mission_dialog'),
        title: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final emphasis = _inNetworkGrace
                ? Colors.redAccent.withValues(
                    alpha: 0.45 + (0.55 * _pulse.value),
                  )
                : null;
            return Text(
              'Novo Chamado Disponível',
              key: const Key('blind_mission_title'),
              textAlign: TextAlign.center,
              style: emphasis == null
                  ? null
                  : TextStyle(color: emphasis, fontWeight: FontWeight.w700),
            );
          },
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final color = _inNetworkGrace
                      ? Colors.redAccent.withValues(
                          alpha: 0.45 + (0.55 * _pulse.value),
                        )
                      : AppTheme.amber;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        key: const Key('blind_mission_timer'),
                        value: progress,
                        strokeWidth: 7,
                        color: color,
                      ),
                      Text(
                        '$_remainingSeconds',
                        key: const Key('blind_mission_countdown'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: _inNetworkGrace ? color : null,
                              fontWeight: _inNetworkGrace
                                  ? FontWeight.w700
                                  : null,
                            ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (widget.idleBalanceAtRisk) ...[
              const SizedBox(height: 16),
              const Text(
                BlindMissionDialog.idleWarning,
                key: Key('idle_reset_warning'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                key: const Key('blind_mission_error'),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            key: const Key('decline_mission'),
            onPressed: _responding ? null : () => _respond('declined'),
            child: _respondingTo == 'declined'
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Recusar'),
          ),
          FilledButton(
            key: const Key('accept_mission'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            onPressed: _responding ? null : () => _respond('accepted'),
            child: _respondingTo == 'accepted'
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Aceitar'),
          ),
        ],
      ),
    );
  }
}
