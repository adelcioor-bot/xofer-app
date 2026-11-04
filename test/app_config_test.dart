import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/core/config/app_config.dart';

void main() {
  group('local Supabase host selection', () {
    test('localhost web uses local Supabase in any build mode', () {
      expect(
        AppConfig.shouldUseLocalSupabaseFor(
          forceLocal: false,
          isWeb: true,
          host: 'localhost',
        ),
        isTrue,
      );
    });

    test('loopback web addresses use local Supabase', () {
      for (final host in ['127.0.0.1', '::1']) {
        expect(
          AppConfig.shouldUseLocalSupabaseFor(
            forceLocal: false,
            isWeb: true,
            host: host,
          ),
          isTrue,
        );
      }
    });

    test('non-local web hosts use the remote Supabase', () {
      expect(
        AppConfig.shouldUseLocalSupabaseFor(
          forceLocal: false,
          isWeb: true,
          host: 'app.example.com',
        ),
        isFalse,
      );
    });

    test('local can still be explicitly forced outside web', () {
      expect(
        AppConfig.shouldUseLocalSupabaseFor(
          forceLocal: true,
          isWeb: false,
          host: 'app.example.com',
        ),
        isTrue,
      );
    });
  });
}
