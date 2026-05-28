import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provides the [SupabaseClient] singleton initialised in [main].
final supabaseClientProvider = Provider<SupabaseClient>(
  (_) => Supabase.instance.client,
  name: 'supabaseClientProvider',
);
