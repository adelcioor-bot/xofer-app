import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/places/domain/place.dart';
import 'package:xofer/features/ride/domain/payment_method.dart';
import 'package:xofer/features/ride/domain/ride_quote.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/corrida_repository.dart';
import 'package:xofer/prof/domain/nearby_call.dart';
import 'package:xofer/features/ride/presentation/ride_request_wait_screen.dart';

class RideSummaryScreen extends StatefulWidget {
  const RideSummaryScreen({
    super.key,
    required this.origin,
    required this.destination,
    this.corridaRepository,
  });

  final Place origin;
  final Place destination;
  final CorridaRepository? corridaRepository;

  @override
  State<RideSummaryScreen> createState() => _RideSummaryScreenState();
}

class _RideSummaryScreenState extends State<RideSummaryScreen> {
  late final RideQuote _quote = RideQuote.between(
    widget.origin,
    widget.destination,
  );
  PaymentMethod _payment = PaymentMethod.creditCard;
  bool _pixCopied = false;
  bool _requesting = false;
  String? _requestError;

  String _placeText(Place place) {
    final description = place.description.trim();
    return description.isNotEmpty ? description : place.label;
  }

  Future<void> _copyPix() async {
    setState(() => _pixCopied = true);
    await Clipboard.setData(ClipboardData(text: pixCopyPaste(_quote)));
  }

  Future<void> _confirm() async {
    final repository = widget.corridaRepository;
    if (repository == null) {
      setState(() => _requestError = CorridaFailure.syncMessage);
      return;
    }
    setState(() {
      _requesting = true;
      _requestError = null;
    });
    final random = Random.secure();
    final callId = List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final call = NearbyCall(
      id: 'ride-$callId',
      origin: _placeText(widget.origin),
      destination: _placeText(widget.destination),
      client: LatLng(widget.origin.latitude, widget.origin.longitude),
      dropoff: LatLng(
        widget.destination.latitude,
        widget.destination.longitude,
      ),
      distanceKm: _quote.distanceKm,
      driverFare: _quote.price,
    );
    try {
      final corrida = await repository.requestRide(call: call);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => RideRequestWaitScreen(
            call: call,
            corrida: corrida,
            repository: repository,
          ),
        ),
      );
    } on CorridaFailure catch (error) {
      if (mounted) setState(() => _requestError = error.message);
    } catch (_) {
      if (mounted) setState(() => _requestError = CorridaFailure.syncMessage);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rideSummaryTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Material(
                    color: AppTheme.graphiteSurface,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _RouteStop(
                            icon: Icons.trip_origin,
                            label: l10n.originLabel,
                            value: _placeText(widget.origin),
                            valueKey: const Key('summary_origin'),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 9),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 2,
                                height: 18,
                                color: AppTheme.amber.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                          _RouteStop(
                            icon: Icons.location_on,
                            label: l10n.destinationLabel,
                            value: _placeText(widget.destination),
                            valueKey: const Key('summary_destination'),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatKilometers(_quote.distanceKm),
                              key: const Key('summary_distance'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: AppTheme.graphiteSurface,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: [
                          Text(
                            l10n.estimatedPrice,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            formatBrl(_quote.price),
                            key: const Key('ride_price'),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: AppTheme.amber,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.paymentMethod,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PaymentOption(
                    optionKey: const Key('payment_credit'),
                    selected: _payment == PaymentMethod.creditCard,
                    icon: Icons.credit_card,
                    title: l10n.creditCard,
                    subtitle: l10n.savedCard,
                    onTap: () => setState(() {
                      _payment = PaymentMethod.creditCard;
                      _pixCopied = false;
                    }),
                  ),
                  const SizedBox(height: 8),
                  _PaymentOption(
                    optionKey: const Key('payment_pix'),
                    selected: _payment == PaymentMethod.pix,
                    icon: Icons.qr_code_2,
                    title: l10n.pix,
                    subtitle: l10n.pixCopyPaste,
                    onTap: () => setState(() => _payment = PaymentMethod.pix),
                  ),
                  if (_payment == PaymentMethod.pix) ...[
                    const SizedBox(height: 8),
                    Material(
                      color: AppTheme.graphiteSurface,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              pixCopyPaste(_quote),
                              key: const Key('pix_code'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              key: const Key('pix_copy_button'),
                              onPressed: _copyPix,
                              child: Text(
                                _pixCopied ? l10n.pixCopied : l10n.copyPixCode,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_requestError != null) ...[
                    Text(
                      _requestError!,
                      key: const Key('ride_request_error'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ElevatedButton(
                    key: const Key('confirm_ride_button'),
                    onPressed: _requesting ? null : _confirm,
                    child: _requesting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(l10n.confirmDriver),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteStop extends StatelessWidget {
  const _RouteStop({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.amber, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppTheme.amber,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(value, key: valueKey, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.optionKey,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key optionKey;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.graphiteSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: optionKey,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.amber
                  : Colors.white.withValues(alpha: 0.08),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: AppTheme.amber,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
