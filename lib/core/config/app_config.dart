import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:xofer/core/config/test_profile_seed.dart';

class AppConfig {
  static const appEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  static const useLocalSupabase = bool.fromEnvironment(
    'USE_LOCAL_SUPABASE',
    defaultValue: false,
  );

  static const localSupabaseUrl = 'http://127.0.0.1:54321';
  static const localTestOtp = '123456';

  static const localLoopbackHosts = {'localhost', '127.0.0.1', '::1'};

  static bool isLoopbackHost(String host) => localLoopbackHosts.contains(host);

  static bool get shouldUseLocalSupabase {
    return shouldUseLocalSupabaseFor(
      forceLocal: useLocalSupabase,
      isWeb: kIsWeb,
      host: Uri.base.host,
    );
  }

  static bool shouldUseLocalSupabaseFor({
    required bool forceLocal,
    required bool isWeb,
    required String host,
  }) => forceLocal || (isWeb && isLoopbackHost(host));

  static bool get shouldSimulateLocalOtp => shouldUseLocalSupabase;

  static const localSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_LOCAL_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
  );

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zfijlubukhzijrskwirx.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_9vo-_RZaF1kWyNAHyiv3nw_76-hsJkA',
  );

  static const defaultCountryCode = String.fromEnvironment(
    'DEFAULT_COUNTRY_CODE',
    defaultValue: '+55',
  );

  static const makePenaltyWebhookUrl = String.fromEnvironment(
    'MAKE_PENALTY_WEBHOOK_URL',
    defaultValue: '',
  );

  static const testProfileSeed = TestProfileSeed(
    phoneDigits: '554141994141',
    fullName: 'Teste Xofer',
    document: '123456789',
    phone: '554141994141',
  );
}
