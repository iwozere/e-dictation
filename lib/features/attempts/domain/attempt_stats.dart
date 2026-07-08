import 'package:flutter/foundation.dart';

/// Aggregated attempt statistics for a single dictation.
///
/// Powers the tries badge on the teacher dashboard cards without loading
/// full attempt rows.
@immutable
class AttemptStats {
  const AttemptStats({
    required this.totalTries,
    required this.latestTryAt,
  });

  /// Total number of submitted attempts for the dictation.
  final int totalTries;

  /// Completion time of the most recent attempt, or null when there are none.
  final DateTime? latestTryAt;
}
