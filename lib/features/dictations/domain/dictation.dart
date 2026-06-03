/// Domain model for a dictation (mirrors the `dictations` table).
class Dictation {
  const Dictation({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.language,
    required this.fullText,
    this.classId,
    this.difficulty,
    this.shareCode,
    this.defaultPauseSecs = 5,
    required this.createdAt,
    required this.updatedAt,
    this.sentences = const [],
    this.ttsStatus = TtsStatus.pending,
    this.ttsError,
    this.allowStudentControls = true,
  });

  final String id;
  final String ownerId;
  final String? classId;
  final String title;
  final DictationLanguage language;
  final DictationDifficulty? difficulty;
  final String fullText;
  final String? shareCode;
  final int defaultPauseSecs;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Eagerly loaded sentences (optional join).
  final List<DictationSentence> sentences;

  final TtsStatus ttsStatus;
  final String? ttsError;
  final bool allowStudentControls;

  /// Shareable URL for students.
  String? get shareUrl => shareCode != null ? '/d/$shareCode' : null;

  int get wordCount =>
      fullText.trim().isEmpty ? 0 : fullText.trim().split(RegExp(r'\s+')).length;

  factory Dictation.fromJson(Map<String, dynamic> json) => Dictation(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        classId: json['class_id'] as String?,
        title: json['title'] as String,
        language: DictationLanguage.fromCode(json['language'] as String? ?? 'de'),
        difficulty: json['difficulty'] == null
            ? null
            : DictationDifficulty.fromString(json['difficulty'] as String),
        fullText: json['full_text'] as String,
        shareCode: json['share_code'] as String?,
        defaultPauseSecs: (json['default_pause_secs'] as int?) ?? 5,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        sentences: ((json['dictation_sentences'] as List<dynamic>?)
                    ?.map((s) => DictationSentence.fromJson(s as Map<String, dynamic>))
                    .toList() ??
                [])
              ..sort((a, b) => a.position.compareTo(b.position)),
        ttsStatus: TtsStatus.fromString(json['tts_status'] as String? ?? 'pending'),
        ttsError: json['tts_error'] as String?,
        allowStudentControls: (json['allow_student_controls'] as bool?) ?? true,
      );

  Map<String, dynamic> toInsertJson() => {
        'owner_id': ownerId,
        if (classId != null) 'class_id': classId,
        'title': title,
        'language': language.code,
        if (difficulty != null) 'difficulty': difficulty!.value,
        'full_text': fullText,
        'default_pause_secs': defaultPauseSecs,
      };

  Dictation copyWith({
    String? title,
    DictationLanguage? language,
    DictationDifficulty? difficulty,
    String? fullText,
    String? classId,
    int? defaultPauseSecs,
    List<DictationSentence>? sentences,
    TtsStatus? ttsStatus,
    String? ttsError,
    bool? allowStudentControls,
  }) =>
      Dictation(
        id: id,
        ownerId: ownerId,
        classId: classId ?? this.classId,
        title: title ?? this.title,
        language: language ?? this.language,
        difficulty: difficulty ?? this.difficulty,
        fullText: fullText ?? this.fullText,
        shareCode: shareCode,
        defaultPauseSecs: defaultPauseSecs ?? this.defaultPauseSecs,
        createdAt: createdAt,
        updatedAt: updatedAt,
        sentences: sentences ?? this.sentences,
        ttsStatus: ttsStatus ?? this.ttsStatus,
        ttsError: ttsError ?? this.ttsError,
        allowStudentControls: allowStudentControls ?? this.allowStudentControls,
      );
}

// ---------------------------------------------------------------------------

class DictationSentence {
  const DictationSentence({
    required this.id,
    required this.dictationId,
    required this.position,
    required this.text,
    this.audioUrl,
    this.durationMs,
  });

  final String id;
  final String dictationId;
  final int position;
  final String text;
  final String? audioUrl;
  final int? durationMs;

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;

  factory DictationSentence.fromJson(Map<String, dynamic> json) => DictationSentence(
        id: json['id'] as String,
        dictationId: json['dictation_id'] as String,
        position: json['position'] as int,
        text: json['text'] as String,
        audioUrl: json['audio_url'] as String?,
        durationMs: json['duration_ms'] as int?,
      );
}

// ---------------------------------------------------------------------------

enum DictationLanguage {
  german('de', 'Deutsch'),
  english('en', 'English'),
  french('fr', 'Français');

  const DictationLanguage(this.code, this.label);
  final String code;
  final String label;

  static DictationLanguage fromCode(String code) {
    return DictationLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => DictationLanguage.german,
    );
  }
}

enum DictationDifficulty {
  easy('easy', 'Easy'),
  medium('medium', 'Medium'),
  hard('hard', 'Hard');

  const DictationDifficulty(this.value, this.label);
  final String value;
  final String label;

  static DictationDifficulty fromString(String v) {
    return DictationDifficulty.values.firstWhere(
      (d) => d.value == v,
      orElse: () => DictationDifficulty.medium,
    );
  }
}

// ---------------------------------------------------------------------------

enum TtsStatus {
  pending,
  processing,
  done,
  error;

  static TtsStatus fromString(String v) => switch (v) {
        'processing' => TtsStatus.processing,
        'done' => TtsStatus.done,
        'error' => TtsStatus.error,
        _ => TtsStatus.pending,
      };
}
