import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/rescue_offer.dart';
import 'package:xofer/prof/presentation/active_rescue_screen.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({
    super.key,
    required this.role,
    required this.locationRepository,
    this.corridaRepository,
    required this.onSignOut,
    required this.partnerId,
    this.partnerName = 'Motoboy',
    this.documentCapture,
  });

  final PartnerRole role;
  final LocationRepository locationRepository;
  final CorridaRepository? corridaRepository;
  final Future<void> Function() onSignOut;
  final String partnerId;
  final String partnerName;
  final DocumentCapture? documentCapture;

  static const fallback = LatLng(-23.5505, -46.6333);

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final MapController _mapController = MapController();
  LatLng _center = RadarScreen.fallback;
  bool _locating = true;
  String? _locationMessage;
  bool _mapReady = false;
  List<RescueOffer> _offers = const [];
  RescueOffer? _activeOffer;
  bool _claiming = false;
  String? _offerMessage;
  StreamSubscription<List<RescueOffer>>? _offerSub;

  @override
  void initState() {
    super.initState();
    _listenOffers();
    _locate();
  }

  @override
  void dispose() {
    _offerSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _listenOffers() {
    final repository = widget.corridaRepository;
    if (repository == null) return;
    _offerSub = repository
        .offers(role: widget.role)
        .listen(
          (remote) {
            if (!mounted) return;
            _showOffers(remote);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _offerMessage = _syncMessage(error));
          },
        );
    _loadRemoteOffers(repository);
  }

  Future<void> _loadRemoteOffers(CorridaRepository repository) async {
    try {
      final remote = await repository.loadOffers(role: widget.role);
      if (!mounted) return;
      _showOffers(remote);
    } on CorridaFailure catch (error) {
      if (mounted) setState(() => _offerMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _offerMessage = CorridaFailure.syncMessage);
      }
    }
  }

  void _showOffers(List<RescueOffer> offers) {
    _offers = widget.role == PartnerRole.courier
        ? offers.map((offer) => offer.forCourier(_center)).toList()
        : offers;
    _syncActiveOffer();
    if (mounted) setState(() {});
  }

  void _syncActiveOffer() {
    _activeOffer =
        widget.role == PartnerRole.courier &&
            (_locating || _locationMessage != null)
        ? null
        : _offers.isEmpty
        ? null
        : _offers.first;
  }

  Future<void> _acceptOffer() async {
    final offer = _activeOffer;
    if (offer == null || _claiming) return;
    setState(() {
      _claiming = true;
      _offerMessage = null;
    });
    final eta = etaMinutesBetween(_center, offer.driver);
    try {
      final repository = widget.corridaRepository;
      final corridaId = offer.corridaId;
      if (repository == null || corridaId == null) {
        throw const CorridaFailure(
          'Esta oferta não está vinculada a uma corrida real.',
        );
      }
      await repository.assignMotoboy(
        id: corridaId,
        motoboyId: widget.partnerId,
        motoboyNome: widget.partnerName,
        etaMinutos: eta,
        motoboy: _center,
        rescueDistanceKm: offer.rescueDistanceKm,
        rescueFare: offer.rescueFare,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ActiveRescueScreen(
            role: PartnerRole.courier,
            driver: _center,
            call: offer.call,
            corridaRepository: widget.corridaRepository,
            motoboyId: widget.partnerId,
            motoboyTarget: offer.driver,
            acceptedAt: DateTime.now(),
            documentCapture: widget.documentCapture,
          ),
        ),
      );
    } on CorridaFailure catch (error) {
      if (!mounted) return;
      setState(() => _offerMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _offerMessage = CorridaFailure.syncMessage);
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<void> _acceptCall(RescueOffer offer) async {
    final repository = widget.corridaRepository;
    final corridaId = offer.corridaId;
    if (repository == null || corridaId == null || _claiming) return;
    setState(() {
      _claiming = true;
      _offerMessage = null;
    });
    try {
      await repository.acceptCall(corridaId, driver: _center);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ActiveRescueScreen(
            role: PartnerRole.driver,
            driver: _center,
            call: offer.call,
            corridaRepository: repository,
            acceptedAt: DateTime.now(),
          ),
        ),
      );
    } on CorridaFailure catch (error) {
      if (mounted) setState(() => _offerMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _offerMessage = CorridaFailure.syncMessage);
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  String _syncMessage(Object error) {
    return error is CorridaFailure ? error.message : CorridaFailure.syncMessage;
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      final location = await widget.locationRepository.currentLocation();
      if (!mounted) return;
      final center = LatLng(location.latitude, location.longitude);
      setState(() {
        _center = center;
        _locationMessage = null;
        _locating = false;
      });
      if (widget.role == PartnerRole.courier) _showOffers(_offers);
      _move(center);
    } on LocationFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _locationMessage = _message(AppLocalizations.of(context), error.reason);
        _locating = false;
      });
      _syncActiveOffer();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationMessage = AppLocalizations.of(context).locationUnavailable;
        _locating = false;
      });
      _syncActiveOffer();
    }
  }

  String _message(AppLocalizations l10n, LocationFailureReason reason) {
    return switch (reason) {
      LocationFailureReason.serviceDisabled => l10n.locationServiceDisabled,
      LocationFailureReason.permissionDenied => l10n.locationPermissionDenied,
      LocationFailureReason.permissionDeniedForever =>
        l10n.locationPermissionDeniedForever,
      LocationFailureReason.unavailable => l10n.locationUnavailable,
    };
  }

  void _move(LatLng point) {
    if (!_mapReady) return;
    _mapController.move(point, 15);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('radar_screen'),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onMapReady: () {
                _mapReady = true;
                _move(_center);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.xofer.prof',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    key: const Key('partner_location_marker'),
                    point: _center,
                    width: 36,
                    height: 36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.graphite,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.amber, width: 2),
                      ),
                      child: const Icon(
                        Icons.navigation,
                        color: AppTheme.amber,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Material(
                      color: AppTheme.graphiteSurface,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          widget.role == PartnerRole.driver
                              ? 'Radar de corridas'
                              : 'Ofertas de resgate',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppTheme.graphiteSurface,
                    shape: const CircleBorder(),
                    child: IconButton(
                      key: const Key('partner_sign_out'),
                      tooltip: 'Terminar sessão',
                      onPressed: widget.onSignOut,
                      icon: const Icon(Icons.logout, color: AppTheme.amber),
                    ),
                  ),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: widget.role == PartnerRole.courier ? 0.72 : 0.42,
            minChildSize: 0.24,
            maxChildSize: 0.75,
            builder: (context, controller) {
              return Material(
                color: AppTheme.graphite,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.role == PartnerRole.driver
                          ? 'Chamadas próximas'
                          : 'Ofertas de resgate',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.amber,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_locationMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _locationMessage!,
                        key: const Key('radar_location_error'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                    if (_locating)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    const SizedBox(height: 12),
                    if (widget.role == PartnerRole.courier)
                      _OfferPanel(
                        offer: _activeOffer,
                        queueCount: _offers.length <= 1
                            ? 0
                            : _offers.length - 1,
                        claiming: _claiming,
                        message: _offerMessage,
                        onAccept: _acceptOffer,
                      )
                    else if (_offers.isEmpty)
                      Text(
                        _offerMessage ??
                            'Nenhuma chamada disponível no momento.',
                        key: const Key('calls_empty'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      )
                    else ...[
                      if (_offerMessage != null)
                        Text(
                          _offerMessage!,
                          key: const Key('call_accept_error'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      for (final offer in _offers)
                        _CallCard(
                          offer: offer,
                          claiming: _claiming,
                          onAccept: () => _acceptCall(offer),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OfferPanel extends StatelessWidget {
  const _OfferPanel({
    required this.offer,
    required this.queueCount,
    required this.claiming,
    required this.message,
    required this.onAccept,
  });

  final RescueOffer? offer;
  final int queueCount;
  final bool claiming;
  final String? message;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = offer;
    if (current == null) {
      return Text(
        message ?? 'Nenhuma oferta no momento',
        key: const Key('offer_empty'),
        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
      );
    }
    final open = !claiming;
    return Material(
      key: const Key('rescue_offer'),
      color: AppTheme.graphiteSurface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resgate disponível',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppTheme.amber,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              current.driverLabel,
              key: const Key('offer_driver_location'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Distância até o motorista: '
              '${formatKilometers(current.rescueDistanceKm)}',
              key: const Key('offer_rescue_distance'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ganho do resgate',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
            Text(
              formatBrl(current.rescueFare),
              key: const Key('offer_rescue_fare'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppTheme.amber,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            if (queueCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                queueCount == 1 ? '1 na fila' : '$queueCount na fila',
                key: const Key('offer_queue'),
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                key: const Key('offer_error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              key: const Key('accept_offer'),
              onPressed: open ? onAccept : null,
              child: Text(open ? 'Aceitar' : 'Processando...'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallCard extends StatelessWidget {
  const _CallCard({
    required this.offer,
    required this.claiming,
    required this.onAccept,
  });

  final RescueOffer offer;
  final bool claiming;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final call = offer.call;
    final id = offer.corridaId ?? call.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: Key('nearby_call_$id'),
        color: AppTheme.graphiteSurface,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(call.origin, style: theme.textTheme.titleSmall),
              Text(
                call.destination,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(formatKilometers(call.distanceKm))),
                  Text(
                    formatBrl(call.driverFare),
                    key: Key('call_fare_$id'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppTheme.amber,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                key: Key('accept_call_$id'),
                onPressed: claiming ? null : onAccept,
                child: Text(claiming ? 'Processando...' : 'Aceitar corrida'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
