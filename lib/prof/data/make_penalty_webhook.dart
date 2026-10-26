import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xofer/core/config/app_config.dart';
import 'package:xofer/prof/domain/corrida_failure.dart';
import 'package:xofer/prof/domain/penalty_webhook.dart';

class MakePenaltyWebhook implements PenaltyWebhook {
  MakePenaltyWebhook({http.Client? client, String? url})
    : _client = client ?? http.Client(),
      url = url ?? AppConfig.makePenaltyWebhookUrl;

  final http.Client _client;
  final String url;

  @override
  Future<bool> notifyPenalty(Map<String, Object?> payload) async {
    final endpoint = url.trim();
    if (endpoint.isEmpty) return false;
    try {
      final response = await _client.post(
        Uri.parse(endpoint),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const CorridaFailure(
          'Não foi possível enviar a penalidade para o Make.com.',
        );
      }
      return true;
    } on CorridaFailure {
      rethrow;
    } catch (_) {
      throw const CorridaFailure(
        'Não foi possível enviar a penalidade para o Make.com.',
      );
    }
  }
}
