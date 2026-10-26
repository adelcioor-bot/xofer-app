import 'package:xofer/core/config/test_profile_seed.dart';

class AppConfig {
  static const appEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
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
