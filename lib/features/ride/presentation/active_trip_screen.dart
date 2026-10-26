import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/ride/domain/boarding_confirmation.dart';
import 'package:xofer/features/ride/domain/boarding_token.dart';
import 'package:xofer/features/ride/domain/payment_method.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';
import 'package:xofer/features/ride/domain/trip_track.dart';
import 'package:xofer/features/ride/presentation/boarding_scan_screen.dart';
import 'package:xofer/features/ride/presentation/boarding_scanner.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';

class ActiveTripScreen extends StatefulWidget {
  const ActiveTripScreen({
    super.key,
    required this.origin,
    required this.destination,
    required this.quote,
    required this.payment,
    this.stepInterval = const Duration(seconds: 2),
    this.pickupSteps = 6,
    this.rideSteps = 8,
    this.boarding,
    this.scanner,
  });

  final Place origin;
  final Place destination;
  final RideQuote quote;
  final PaymentMethod payment;
  final Duration stepInterval;
  final int pickupSteps;
  final int rideSteps;
  final BoardingConfirmation? boarding;
  final BoardingScanner? scanner;

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late final TripTrack _track = TripTrack.fromPlaces(
    origin: widget.origin,
    destination: widget.destination,
    pickupSteps: widget.pickupSteps,
    rideSteps: widget.rideSteps,
  );
  late final AnimationController _glide;
  Timer? _timer;
  int _segment = 0;
  bool _follow = true;
  bool _mapReady = false;
  bool _scanning = false;
  bool _rideReleased = false;

  LatLng get _vehiclePoint => _track.glide(_segment, _glide.value);

  TripPhase get _phase => _track.phaseAt(_segment);

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(vsync: this, duration: widget.stepInterval)
      ..addListener(_onGlide);
    _glide.forward();
    _timer = Timer.periodic(widget.stepInterval, (_) => _advance());
  }

  void _onGlide() {
    if (!mounted) return;
    setState(() {});
    _focusCamera();
  }

  void _advance() {
    if (!mounted) return;
    final next = _segment + 1;
    if (next >= _track.lastStep) {
      _timer?.cancel();
      _timer = null;
      _glide.value = 1;
      setState(() => _segment = _track.lastStep);
      _focusCamera();
      return;
    }
    setState(() => _segment = next);
    _glide.forward(from: 0);
  }

  void _focusCamera() {
    if (!_follow || !_mapReady || !mounted) return;
    _mapController.move(_vehiclePoint, _mapController.camera.zoom);
  }

  void _onMapEvent(MapEvent event) {
    final userMoved =
        event.source == MapEventSource.dragStart ||
        event.source == MapEventSource.multiFingerGestureStart;
    if (!userMoved || !_follow) return;
    setState(() => _follow = false);
  }

  void _startRideNavigation() {
    _timer?.cancel();
    setState(() {
      _rideReleased = true;
      _segment = _track.pickupSteps;
    });
    _glide.forward(from: 0);
    _timer = Timer.periodic(widget.stepInterval, (_) => _advance());
  }

  Future<void> _scanDriverQr() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final boarding =
          widget.boarding ?? RepositoryBoardingConfirmation.remote();
      final scanner = widget.scanner ?? const MobileBoardingScanner();
      final result = await scanner.scan(
        context,
        confirmReserveCode: (code) async {
          try {
            await boarding.confirmReserveCode(code);
            return null;
          } on CorridaFailure catch (error) {
            return error.message;
          } catch (_) {
            return CorridaFailure.syncMessage;
          }
        },
      );
      if (result == null || !mounted) return;
      if (!result.isReserveCode) {
        await boarding.confirm(result.value);
      }
      if (!mounted) return;
      _startRideNavigation();
    } on CorridaFailure catch (error) {
      if (!mounted) return;
      await _showBoardingAlert(error.message);
    } catch (_) {
      if (!mounted) return;
      await _showBoardingAlert(invalidBoardingQrMessage);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _showBoardingAlert(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const Key('invalid_qr_alert'),
          backgroundColor: AppTheme.graphiteSurface,
          title: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _resumeFollow() {
    setState(() => _follow = true);
    _focusCamera();
  }

  String _status(AppLocalizations l10n) {
    return switch (_phase) {
      TripPhase.pickup => l10n.driverOnTheWay,
      TripPhase.ride => l10n.headingToDestination,
      TripPhase.arrived => l10n.tripArrived,
    };
  }

  String _placeText(Place place) {
    final description = place.description.trim();
    return description.isNotEmpty ? description : place.label;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _glide
      ..removeListener(_onGlide)
      ..dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vehicle = _vehiclePoint;
    final paymentLabel = widget.payment == PaymentMethod.creditCard
        ? l10n.savedCard
        : l10n.pix;

    return Scaffold(
      backgroundColor: AppTheme.graphite,
      appBar: AppBar(title: Text(l10n.activeTripTitle)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _track.driverStart,
              initialZoom: 15,
              onMapReady: () {
                _mapReady = true;
                _focusCamera();
              },
              onMapEvent: _onMapEvent,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.xofer.app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [
                      _track.driverStart,
                      _track.pickup,
                      _track.destination,
                    ],
                    color: AppTheme.amber.withValues(alpha: 0.85),
                    strokeWidth: 4,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    key: const Key('trip_origin_marker'),
                    point: _track.pickup,
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.trip_origin,
                      color: AppTheme.amber,
                      size: 28,
                    ),
                  ),
                  Marker(
                    key: const Key('trip_destination_marker'),
                    point: _track.destination,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      color: AppTheme.amber,
                      size: 40,
                    ),
                  ),
                  Marker(
                    key: const Key('trip_vehicle_marker'),
                    point: vehicle,
                    width: 36,
                    height: 36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.graphite,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.amber, width: 2),
                      ),
                      child: Icon(
                        _phase == TripPhase.pickup
                            ? Icons.person
                            : Icons.directions_car,
                        key: const Key('trip_vehicle_icon'),
                        color: AppTheme.amber,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!_follow)
            Positioned(
              right: 16,
              bottom: 228,
              child: Material(
                color: AppTheme.graphiteSurface,
                shape: const CircleBorder(),
                elevation: 4,
                child: IconButton(
                  key: const Key('follow_trip_button'),
                  tooltip: l10n.followRoute,
                  onPressed: _resumeFollow,
                  icon: const Icon(Icons.my_location, color: AppTheme.amber),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Material(
                  key: const Key('active_trip_screen'),
                  color: AppTheme.graphiteSurface,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _status(l10n),
                          key: const Key('trip_status'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppTheme.amber,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.assignedDriver,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          l10n.assignedVehicle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _placeText(widget.origin),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _placeText(widget.destination),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_phase == TripPhase.pickup && !_rideReleased) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              key: const Key('scan_driver_qr_button'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.amber,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: _scanning ? null : _scanDriverQr,
                              child: const Text(
                                'Escanear QR Code do Motorista',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                paymentLabel,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              formatBrl(widget.quote.price),
                              key: const Key('active_trip_price'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.amber,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
