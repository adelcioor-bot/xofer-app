import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/auth/domain/auth_repository.dart';
import 'package:xofer/features/location/domain/location_failure.dart';
import 'package:xofer/features/location/domain/location_repository.dart';
import 'package:xofer/features/location/domain/user_location.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/places/domain/place_search_failure.dart';
import 'package:xofer/features/places/domain/place_search_repository.dart';
import 'package:xofer/features/places/presentation/destination_search_bar.dart';
import 'package:xofer/features/ride/presentation/ride_summary_screen.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.authRepository,
    required this.locationRepository,
    required this.placeSearchRepository,
    this.corridaRepository,
    this.mapController,
    this.onAdvance,
  });

  final AuthRepository authRepository;
  final LocationRepository locationRepository;
  final PlaceSearchRepository placeSearchRepository;
  final CorridaRepository? corridaRepository;
  final MapController? mapController;
  final void Function(Place origin, Place destination)? onAdvance;

  static const fallbackCenter = LatLng(-23.5505, -46.6333);
  static const userZoom = 16.0;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MapController _mapController;
  late final bool _ownsController;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  UserLocation? _location;
  Place? _origin;
  bool _resolvingOrigin = false;
  LocationFailureReason? _locationError;
  bool _isLocating = false;
  bool _mapReady = false;

  Place? _destination;
  List<Place> _results = const [];
  bool _isSearching = false;
  bool _showEmpty = false;
  bool _searchFailed = false;
  Timer? _debounce;
  int _searchRequest = 0;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.mapController == null;
    _mapController = widget.mapController ?? MapController();
    _isLocating = true;
    _loadLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.dispose();
    _searchController.dispose();
    if (_ownsController) {
      _mapController.dispose();
    }
    super.dispose();
  }

  Future<void> _locate() async {
    if (_isLocating) return;

    setState(() {
      _isLocating = true;
      _locationError = null;
    });
    await _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final location = await widget.locationRepository.currentLocation();
      if (!mounted) return;
      setState(() {
        _location = location;
        _locationError = null;
        _isLocating = false;
      });
      _centerOn(location);
      await _resolveOrigin(location);
    } on LocationFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _locationError = error.reason;
        _isLocating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationError = LocationFailureReason.unavailable;
        _isLocating = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.authRepository.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _centerOn(UserLocation location) {
    if (_destination != null) return;
    _moveCamera(LatLng(location.latitude, location.longitude));
  }

  void _moveCamera(LatLng point) {
    if (!_mapReady) return;
    _mapController.move(point, HomeScreen.userZoom);
  }

  Future<void> _resolveOrigin(UserLocation location) async {
    if (mounted) setState(() => _resolvingOrigin = true);
    Place? origin;
    try {
      origin = await widget.placeSearchRepository.reverse(location);
    } catch (_) {
      origin = null;
    }
    if (!mounted) return;
    setState(() {
      _origin = origin;
      _resolvingOrigin = false;
    });
  }

  String _formatted(Place place) {
    final description = place.description.trim();
    return description.isNotEmpty ? description : place.label;
  }

  void _frameRoute(LatLng origin, LatLng destination) {
    if (!_mapReady) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([origin, destination]),
          padding: const EdgeInsets.fromLTRB(48, 240, 48, 160),
          maxZoom: HomeScreen.userZoom,
        ),
      );
    } catch (_) {
      _moveCamera(destination);
    }
  }

  bool _suppressQuery = false;
  bool _openingSummary = false;

  void _onQueryChanged(String value) {
    if (_suppressQuery) return;
    _scheduleSearch(value);
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (_destination != null && query != _formatted(_destination!)) {
      _destination = null;
    }
    if (query.length < 3) {
      _searchRequest++;
      setState(() {
        _results = const [];
        _isSearching = false;
        _showEmpty = false;
        _searchFailed = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showEmpty = false;
      _searchFailed = false;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(query);
    });
  }

  void _submitQuery(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      _scheduleSearch(value);
      return;
    }
    setState(() {
      _isSearching = true;
      _showEmpty = false;
      _searchFailed = false;
    });
    _search(query);
  }

  Future<void> _search(String query) async {
    final request = ++_searchRequest;
    try {
      final results = await widget.placeSearchRepository.search(
        query,
        near: _location,
      );
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _results = results;
        _isSearching = false;
        _showEmpty = results.isEmpty;
        _searchFailed = false;
      });
    } on PlaceSearchFailure {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _results = const [];
        _isSearching = false;
        _showEmpty = false;
        _searchFailed = true;
      });
    } catch (_) {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _results = const [];
        _isSearching = false;
        _showEmpty = false;
        _searchFailed = true;
      });
    }
  }

  void _selectPlace(Place place) {
    if (_openingSummary) return;
    _debounce?.cancel();
    _searchRequest++;
    final formatted = _formatted(place);
    _suppressQuery = true;
    _searchController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _suppressQuery = false;
    final target = LatLng(place.latitude, place.longitude);
    setState(() {
      _destination = place;
      _results = const [];
      _isSearching = false;
      _showEmpty = false;
      _searchFailed = false;
    });
    _searchFocus.unfocus();
    final originPoint = _location == null
        ? null
        : LatLng(_location!.latitude, _location!.longitude);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _destination != place) return;
      if (originPoint == null) {
        _moveCamera(target);
      } else {
        _frameRoute(originPoint, target);
      }
    });
    _openSummary(place);
  }

  Place _originPlace(AppLocalizations l10n) {
    if (_origin != null) return _origin!;
    final location = _location;
    final point = location == null
        ? HomeScreen.fallbackCenter
        : LatLng(location.latitude, location.longitude);
    return Place(
      id: 'gps',
      label: l10n.originUnavailable,
      description: l10n.originUnavailable,
      latitude: point.latitude,
      longitude: point.longitude,
    );
  }

  void _openSummary(Place destination) {
    _openingSummary = true;
    final origin = _originPlace(AppLocalizations.of(context));
    final advance = widget.onAdvance;
    if (advance != null) {
      advance(origin, destination);
      _openingSummary = false;
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (context) => RideSummaryScreen(
              origin: origin,
              destination: destination,
              corridaRepository: widget.corridaRepository,
            ),
          ),
        )
        .whenComplete(() {
          if (!mounted) return;
          setState(() => _openingSummary = false);
        });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchRequest++;
    _suppressQuery = true;
    _searchController.clear();
    _suppressQuery = false;
    setState(() {
      _destination = null;
      _results = const [];
      _isSearching = false;
      _showEmpty = false;
      _searchFailed = false;
    });
  }

  String _messageFor(AppLocalizations l10n, LocationFailureReason reason) {
    switch (reason) {
      case LocationFailureReason.serviceDisabled:
        return l10n.locationServiceDisabled;
      case LocationFailureReason.permissionDenied:
        return l10n.locationPermissionDenied;
      case LocationFailureReason.permissionDeniedForever:
        return l10n.locationPermissionDeniedForever;
      case LocationFailureReason.unavailable:
        return l10n.locationUnavailable;
    }
  }

  bool get _canOpenSettings {
    return _locationError == LocationFailureReason.serviceDisabled ||
        _locationError == LocationFailureReason.permissionDeniedForever;
  }

  Future<void> _openSettings() async {
    final reason = _locationError;
    if (reason == null) return;
    await widget.locationRepository.openSettings(reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final location = _location;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: HomeScreen.fallbackCenter,
              initialZoom: 13,
              onMapReady: () {
                _mapReady = true;
                final destination = _destination;
                if (destination != null) {
                  final current = _location;
                  if (current == null) {
                    _moveCamera(
                      LatLng(destination.latitude, destination.longitude),
                    );
                  } else {
                    _frameRoute(
                      LatLng(current.latitude, current.longitude),
                      LatLng(destination.latitude, destination.longitude),
                    );
                  }
                  return;
                }
                final current = _location;
                if (current != null) _centerOn(current);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.xofer.app',
              ),
              if (location != null && _destination != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        LatLng(location.latitude, location.longitude),
                        LatLng(_destination!.latitude, _destination!.longitude),
                      ],
                      color: AppTheme.amber,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              if (location != null || _destination != null)
                MarkerLayer(
                  markers: [
                    if (location != null)
                      Marker(
                        key: const Key('user_location_marker'),
                        point: LatLng(location.latitude, location.longitude),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.my_location,
                          color: AppTheme.amber,
                          size: 36,
                        ),
                      ),
                    if (_destination != null)
                      Marker(
                        key: const Key('destination_marker'),
                        point: LatLng(
                          _destination!.latitude,
                          _destination!.longitude,
                        ),
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        child: const Icon(
                          Icons.location_on,
                          color: AppTheme.amber,
                          size: 48,
                        ),
                      ),
                  ],
                ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: DestinationSearchBar(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      originLabel: l10n.originLabel,
                      originText: _origin == null
                          ? l10n.originUnavailable
                          : _formatted(_origin!),
                      originLoading: _resolvingOrigin && _origin == null,
                      destinationLabel: l10n.destinationLabel,
                      hintText: l10n.homeWelcome,
                      clearTooltip: l10n.clearSearch,
                      emptyText: l10n.noAddressResults,
                      errorText: _searchFailed ? l10n.addressSearchError : null,
                      isSearching: _isSearching,
                      showEmpty: _showEmpty,
                      results: _results,
                      onChanged: _onQueryChanged,
                      onSubmitted: _submitQuery,
                      onSelected: _selectPlace,
                      onClear: _clearSearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppTheme.graphiteSurface,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: IconButton(
                      tooltip: l10n.signOut,
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout, color: AppTheme.amber),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_locationError != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 96,
              child: Material(
                color: AppTheme.graphiteSurface,
                borderRadius: BorderRadius.circular(12),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_off, color: AppTheme.amber),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              key: const Key('location_error'),
                              _messageFor(l10n, _locationError!),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          TextButton(
                            key: const Key('location_retry_button'),
                            onPressed: _isLocating ? null : _locate,
                            child: Text(l10n.retry),
                          ),
                          if (_canOpenSettings)
                            TextButton(
                              key: const Key('location_settings_button'),
                              onPressed: _isLocating ? null : _openSettings,
                              child: Text(
                                _locationError ==
                                        LocationFailureReason.serviceDisabled
                                    ? l10n.openLocationSettings
                                    : l10n.openAppSettings,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 24,
            child: Material(
              color: AppTheme.graphiteSurface,
              shape: const CircleBorder(),
              elevation: 4,
              child: IconButton(
                key: const Key('my_location_button'),
                tooltip: l10n.myLocation,
                onPressed: _isLocating ? null : _locate,
                icon: _isLocating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.my_location, color: AppTheme.amber),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
