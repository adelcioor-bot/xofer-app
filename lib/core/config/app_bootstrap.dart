import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

class AppBootstrap {
  static Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();

    final key = AppConfig.supabaseAnonKey.isEmpty
        ? 'public-anon-key-not-configured'
        : AppConfig.supabaseAnonKey;

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: key,
      authOptions: const FlutterAuthClientOptions(persistSession: true),
    );
  }
}
