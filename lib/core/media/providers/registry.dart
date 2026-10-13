import 'package:http/http.dart' as http;

import 'catbox.dart';
import 'imgbb.dart';
import 'provider.dart';
import 's3.dart';
import 'sharex.dart';

enum ProviderKind {
  catbox('Catbox'),
  imgbb('ImgBB'),
  s3('S3 storage'),
  sharex('ShareX uploader');

  const ProviderKind(this.label);

  final String label;
}

class ProviderConfig {
  ProviderConfig({
    required this.id,
    required this.kind,
    required this.name,
    this.enabled = true,
    this.concurrency,
    this.maxBytes,
    Map<String, String>? settings,
  }) : settings = settings ?? {};

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
    id: json['id'] as String,
    kind: ProviderKind.values.byName(json['kind'] as String),
    name: json['name'] as String,
    enabled: json['enabled'] != false,
    concurrency: json['concurrency'] as int?,
    maxBytes: json['maxBytes'] as int?,
    settings: ((json['settings'] as Map?) ?? const {}).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
  );

  final String id;
  final ProviderKind kind;
  String name;
  bool enabled;
  int? concurrency;
  int? maxBytes;
  final Map<String, String> settings;

  bool get isPublicHost => kind != ProviderKind.s3;

  int get defaultConcurrency => switch (kind) {
    ProviderKind.catbox => 2,
    ProviderKind.imgbb => 3,
    ProviderKind.s3 => 4,
    ProviderKind.sharex => 2,
  };

  int get maxConcurrency => switch (kind) {
    ProviderKind.catbox => 3,
    ProviderKind.imgbb => 4,
    ProviderKind.s3 => 16,
    ProviderKind.sharex => 6,
  };

  int get effectiveConcurrency =>
      (concurrency ?? defaultConcurrency).clamp(1, maxConcurrency);

  String get limitSummary => switch (kind) {
    ProviderKind.catbox => '200 MB per file, kept forever',
    ProviderKind.imgbb => 'Images up to 32 MB',
    ProviderKind.s3 => 'Your own bucket, multipart uploads',
    ProviderKind.sharex =>
      maxBytes == null
          ? 'Limits set by the host'
          : 'Up to ${(maxBytes! / 1048576).round()} MB',
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'enabled': enabled,
    'concurrency': concurrency,
    'maxBytes': maxBytes,
    'settings': settings,
  };
}

UploadProvider buildProvider(
  ProviderConfig config,
  Map<String, String> secrets, {
  http.Client? client,
}) => switch (config.kind) {
  ProviderKind.catbox => CatboxProvider(
    id: config.id,
    userhash: secrets['userhash'] ?? '',
    concurrency: config.effectiveConcurrency,
    limit: config.maxBytes,
    client: client,
  ),
  ProviderKind.imgbb => ImgbbProvider(
    id: config.id,
    apiKey: secrets['apiKey'] ?? '',
    concurrency: config.effectiveConcurrency,
    limit: config.maxBytes,
    client: client,
  ),
  ProviderKind.s3 => S3Provider(
    id: config.id,
    label: config.name,
    settings: S3Settings(
      endpoint: config.settings['endpoint'] ?? '',
      bucket: config.settings['bucket'] ?? '',
      region: config.settings['region'] ?? '',
      prefix: config.settings['prefix'] ?? '',
      publicBaseUrl: config.settings['publicUrl'] ?? '',
      pathStyle: config.settings['pathStyle'] != 'false',
      accessKey: secrets['accessKey'] ?? '',
      secretKey: secrets['secretKey'] ?? '',
    ),
    concurrency: config.effectiveConcurrency,
    limit: config.maxBytes,
    client: client,
  ),
  ProviderKind.sharex => ShareXProvider(
    id: config.id,
    config: ShareXConfig.parse(secrets['sxcu'] ?? ''),
    concurrency: config.effectiveConcurrency,
    limit: config.maxBytes,
    client: client,
  ),
};
