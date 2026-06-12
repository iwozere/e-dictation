/// Compile-time configuration values injected via --dart-define.
///
/// Web (Vercel): set SUPABASE_URL and SUPABASE_ANON_KEY as environment variables
/// and pass them through your build command:
///   flutter build web \
///     --dart-define=SUPABASE_URL=$SUPABASE_URL \
///     --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
///
/// Local development: create a `.env.local` and use a launch configuration or
/// run via:
///   flutter run -d chrome \
///     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=your-anon-key
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Throws [StateError] if required compile-time variables were not provided.
  ///
  /// Call this once in [main] before [Supabase.initialize] so misconfigured
  /// builds fail fast with a clear message rather than crashing silently later.
  static void validate() {
    if (supabaseUrl.isEmpty) {
      throw StateError(
        'SUPABASE_URL is not configured.\n'
        'Build / run with:\n'
        '  --dart-define=SUPABASE_URL=https://your-project.supabase.co\n'
        '  --dart-define=SUPABASE_ANON_KEY=your-anon-key',
      );
    }
    if (supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY is not configured.\n'
        'Build / run with:\n'
        '  --dart-define=SUPABASE_URL=https://your-project.supabase.co\n'
        '  --dart-define=SUPABASE_ANON_KEY=your-anon-key',
      );
    }
  }

  /// App version — keep in sync with pubspec.yaml.
  static const String version = '0.1.0';

  /// Maximum dictation length enforced client-side (Phase 1 hard limit).
  static const int maxDictationWords = 500;

  /// Supported playback speeds.
  static const List<double> playbackSpeeds = [0.5, 0.75, 1.0, 1.25];

  /// Supported pause durations between sentences (seconds).
  static const List<int> pauseDurations = [2, 5, 10];

  /// Public base URL used to build share links sent to students.
  static const String appBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://e-dictation.vercel.app',
  );
}
