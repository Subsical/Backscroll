enum ExportFormat {
  htmlDark('HTML (dark)', 'html'),
  htmlLight('HTML (light)', 'html'),
  json('JSON', 'json'),
  txt('Plain text', 'txt'),
  csv('CSV', 'csv');

  const ExportFormat(this.label, this.extension);

  final String label;
  final String extension;

  bool get isHtml => this == htmlDark || this == htmlLight;
}

enum MediaMode {
  links('Keep Discord links'),
  local('Save next to the export'),
  rehost('Re-host to my providers');

  const MediaMode(this.label);

  final String label;
}

class ExportOptions {
  const ExportOptions({
    required this.outputDir,
    this.format = ExportFormat.htmlDark,
    this.after,
    this.before,
    this.partitionSize = 0,
    this.mediaMode = MediaMode.links,
    this.keepLocalCopy = false,
    this.includeThreads = false,
    this.pinnedOnly = false,
    this.useUtc = false,
    this.locale,
    this.maxUploadBytes,
    this.providerIds = const [],
  });

  factory ExportOptions.fromJson(Map<String, dynamic> json) => ExportOptions(
    outputDir: json['outputDir'] as String,
    format: ExportFormat.values.byName(json['format'] as String),
    after: json['after'] == null
        ? null
        : DateTime.parse(json['after'] as String),
    before: json['before'] == null
        ? null
        : DateTime.parse(json['before'] as String),
    partitionSize: json['partitionSize'] as int? ?? 0,
    mediaMode: MediaMode.values.byName(json['mediaMode'] as String),
    keepLocalCopy: json['keepLocalCopy'] == true,
    includeThreads: json['includeThreads'] == true,
    pinnedOnly: json['pinnedOnly'] == true,
    useUtc: json['useUtc'] == true,
    locale: json['locale'] as String?,
    maxUploadBytes: json['maxUploadBytes'] as int?,
    providerIds: ((json['providerIds'] as List?) ?? const []).cast<String>(),
  );

  final String outputDir;
  final ExportFormat format;
  final DateTime? after;
  final DateTime? before;
  final int partitionSize;
  final MediaMode mediaMode;
  final bool keepLocalCopy;
  final bool includeThreads;
  final bool pinnedOnly;
  final bool useUtc;
  final String? locale;
  final int? maxUploadBytes;
  final List<String> providerIds;

  bool get savesLocalMedia =>
      mediaMode == MediaMode.local ||
      (mediaMode == MediaMode.rehost && keepLocalCopy);

  ExportOptions copyWith({
    String? outputDir,
    ExportFormat? format,
    DateTime? Function()? after,
    DateTime? Function()? before,
    int? partitionSize,
    MediaMode? mediaMode,
    bool? keepLocalCopy,
    bool? includeThreads,
    bool? pinnedOnly,
    bool? useUtc,
    String? Function()? locale,
    int? Function()? maxUploadBytes,
    List<String>? providerIds,
  }) => ExportOptions(
    outputDir: outputDir ?? this.outputDir,
    format: format ?? this.format,
    after: after != null ? after() : this.after,
    before: before != null ? before() : this.before,
    partitionSize: partitionSize ?? this.partitionSize,
    mediaMode: mediaMode ?? this.mediaMode,
    keepLocalCopy: keepLocalCopy ?? this.keepLocalCopy,
    includeThreads: includeThreads ?? this.includeThreads,
    pinnedOnly: pinnedOnly ?? this.pinnedOnly,
    useUtc: useUtc ?? this.useUtc,
    locale: locale != null ? locale() : this.locale,
    maxUploadBytes: maxUploadBytes != null
        ? maxUploadBytes()
        : this.maxUploadBytes,
    providerIds: providerIds ?? this.providerIds,
  );

  Map<String, dynamic> toJson() => {
    'outputDir': outputDir,
    'format': format.name,
    'after': after?.toIso8601String(),
    'before': before?.toIso8601String(),
    'partitionSize': partitionSize,
    'mediaMode': mediaMode.name,
    'keepLocalCopy': keepLocalCopy,
    'includeThreads': includeThreads,
    'pinnedOnly': pinnedOnly,
    'useUtc': useUtc,
    'locale': locale,
    'maxUploadBytes': maxUploadBytes,
    'providerIds': providerIds,
  };
}
