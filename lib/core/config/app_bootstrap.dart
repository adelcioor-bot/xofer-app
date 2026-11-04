import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

class AppBootstrap {
  static Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();

    final useLocalSupabase = AppConfig.shouldUseLocalSupabase;
    final url = useLocalSupabase
        ? AppConfig.localSupabaseUrl
        : AppConfig.supabaseUrl;
    final key = useLocalSupabase
        ? AppConfig.localSupabaseAnonKey
        : AppConfig.supabaseAnonKey;
    if (useLocalSupabase && key.isEmpty) {
      throw StateError(
        'Defina SUPABASE_LOCAL_ANON_KEY com a ANON_KEY legada (JWT) do '
        'Supabase local, não com a PUBLISHABLE_KEY sb_publishable_.',
      );
    }
    if (useLocalSupabase && key.startsWith('sb_publishable_')) {
      throw StateError(
        'A PUBLISHABLE_KEY sb_publishable_ não autentica o Realtime local. '
        'Use a ANON_KEY legada (JWT) exibida por supabase status -o env.',
      );
    }

    await Supabase.initialize(
      url: url,
      publishableKey: key.isEmpty ? 'public-anon-key-not-configured' : key,
      authOptions: const FlutterAuthClientOptions(persistSession: true),
    );
  }
}
