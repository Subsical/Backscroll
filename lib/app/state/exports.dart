import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../core/convert/converter.dart';
import '../../core/discord/models.dart';
import '../../core/export/dates.dart';
import '../../core/export/job.dart';
import '../../core/export/options.dart';
import '../../core/export/queue.dart';
import '../../core/export/writers/writer.dart';
import '../../core/media/downloader.dart';
import '../../core/media/pipeline.dart';
import '../../core/media/providers/provider.dart';
import '../../core/media/providers/registry.dart';
import '../../core/media/upload_cache.dart';
import '../../core/media/upload_queue.dart';
import '../services/keep_alive.dart';
import '../services/paths.dart';
import '../services/secrets.dart';
import 'session.dart';
import 'settings.dart';

class ExportsController extends ChangeNotifier {
  ExportsController({
    required this.paths,
    required this.settings,
    required this.secrets,
    required this.session,
    this.assets = const ExportAssets(),
    this.cdnClient,
    this.uploadClient,
    this.keepAlive,
    this.locale,
    UploadCache? cache,
  }) : cache = cache ?? UploadCache.open(paths.uploadCache);

  final AppPaths paths;
  final AppSettings settings;
  final SecretStore secrets;
  final Session session;
  final ExportAssets assets;
  final http.Client Function()? cdnClient;
  final http.Client Function()? uploadClient;
  final KeepAlive? keepAlive;
  final String? locale;
  final UploadCache cache;
  late final uploads = UploadQueue(cache: cache);
  late final queue = ExportQueue(
    store: JobStore(Directory(paths.jobs)),
    apiFor: session.apiFor,
    pipelineFor: _pipeline,
    assets: assets,
    onDiscard: _discard,
  );
  final _providerSecrets = <String, Map<String, String>>{};
  final _subscriptions = <StreamSubscription<void>>[];
  bool loaded = false;

  List<ExportJob> get jobs => queue.jobs;
  UploadStats get uploadStats => uploads.stats;

  Future<void> init() async {
    await reloadProviders();
    await queue.load();
    _subscriptions
      ..add(queue.changes.listen((_) => _changed()))
      ..add(uploads.changes.listen((_) => _changed()));
    loaded = true;
    notifyListeners();
  }

  void _changed() {
    notifyListeners();
    final busy = queue.isBusy || !uploads.stats.idle;
    unawaited(keepAlive?.update(busy: busy, text: statusLine));
  }

  String get statusLine {
    final job = queue.current;
    if (job != null) {
      final percent = (job.progress * 100).round();
      return '${job.title} · ${_numbers.format(job.messages)} messages · $percent%';
    }
    final stats = uploads.stats;
    if (!stats.idle) return 'Uploading ${stats.done} of ${stats.total} files';
    return 'Finishing up';
  }

  Future<void> reloadProviders() async {
    _providerSecrets.clear();
    for (final config in settings.providers) {
      _providerSecrets[config.id] = await secrets.readMap(
        _secretKey(config.id),
      );
    }
  }

  String _secretKey(String providerId) => 'provider.$providerId';

  Future<void> saveProvider(
    ProviderConfig config,
    Map<String, String> secretValues,
  ) async {
    final index = settings.providers.indexWhere((p) => p.id == config.id);
    if (index < 0) {
      settings.providers.add(config);
    } else {
      settings.providers[index] = config;
    }
    await secrets.writeMap(_secretKey(config.id), secretValues);
    _providerSecrets[config.id] = secretValues;
    await settings.save();
    notifyListeners();
  }

  Future<void> removeProvider(ProviderConfig config) async {
    settings.providers.removeWhere((p) => p.id == config.id);
    await secrets.delete(_secretKey(config.id));
    _providerSecrets.remove(config.id);
    await settings.save();
    notifyListeners();
  }

  Map<String, String> providerSecrets(String id) => {
    ..._providerSecrets[id] ?? {},
  };

  List<UploadProvider> _providersFor(ExportJob job) {
    final ids = job.options.providerIds;
    final result = <UploadProvider>[];
    for (final config in settings.providers) {
      if (!config.enabled || (ids.isNotEmpty && !ids.contains(config.id))) {
        continue;
      }
      try {
        result.add(
          buildProvider(
            config,
            _providerSecrets[config.id] ?? const {},
            client: uploadClient?.call(),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  MediaPipeline _pipeline(ExportJob job) {
    final mode = job.options.mediaMode;
    if (mode == MediaMode.links) return LinkPipeline(job);
    final rehost = mode == MediaMode.rehost;
    return StandardMediaPipeline(
      job: job,
      downloader: MediaDownloader(client: cdnClient?.call()),
      stagingDir: paths.staging,
      cache: rehost ? cache : null,
      uploads: rehost ? uploads : null,
      providers: rehost ? _providersFor(job) : const [],
    );
  }

  Future<void> _discard(ExportJob job) async {
    cache.deleteJobMedia(job.id);
    final staging = Directory(p.join(paths.staging, job.id));
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } on FileSystemException {
      // windows keeps files of a running upload locked
    }
  }

  ExportOptions defaultOptions() {
    final d = settings.defaults;
    return ExportOptions(
      outputDir: d.outputDir ?? paths.defaultExports,
      format: d.format,
      partitionSize: d.partitionSize,
      mediaMode: settings.defaultMediaMode,
      keepLocalCopy: d.keepLocalCopy,
      includeThreads: d.includeThreads,
      useUtc: d.useUtc,
      locale: locale,
      maxUploadBytes: settings.maxUploadMb == null
          ? null
          : settings.maxUploadMb! * 1024 * 1024,
    );
  }

  Future<void> start({
    required List<Channel> channels,
    required ExportOptions options,
    Guild? guild,
    String? Function(Channel channel)? categoryOf,
  }) async {
    final account = session.account;
    if (account == null || channels.isEmpty) return;
    if (!await AppPaths.ensureWriteAccess()) {
      throw const FileSystemException('Storage permission was denied');
    }
    await Directory(options.outputDir).create(recursive: true);
    final withProviders = options.copyWith(
      providerIds: options.mediaMode == MediaMode.rehost
          ? settings.enabledProviders.map((p) => p.id).toList()
          : const [],
    );
    await queue.enqueue([
      for (final channel in channels)
        ExportJob.create(
          accountId: account.id,
          channel: channel,
          guild: channel.isPrivate ? null : guild,
          category: categoryOf?.call(channel),
          options: withProviders,
        ),
    ]);
  }

  Future<ExportJob> convert({
    required List<File> sources,
    required ExportFormat format,
    ExportJob? from,
    void Function(int messages)? onProgress,
    bool Function()? stopped,
  }) async {
    final result = await convertExport(
      sources: sources,
      target: format,
      assets: assets,
      locale: locale,
      useUtc: from?.options.useUtc ?? settings.defaults.useUtc,
      onProgress: onProgress,
      stopped: stopped,
    );
    final channel = result.header['channel'] as Map<String, dynamic>;
    final guild = result.header['guild'] as Map<String, dynamic>?;
    final parentName = channel['parentName'] as String?;
    final now = DateTime.now();
    final job = ExportJob(
      id: newId(),
      accountId: from?.accountId ?? session.account?.id ?? '',
      channel:
          from?.channel ??
          Channel(
            id: '${channel['id']}',
            type: channel['type'] as int? ?? ChannelType.guildText,
            name: channel['name'] as String?,
          ),
      guild:
          from?.guild ??
          (guild == null
              ? null
              : Guild(
                  id: '${guild['id']}',
                  name: guild['name'] as String? ?? 'Server',
                )),
      parent:
          from?.parent ??
          (parentName == null
              ? null
              : Channel(
                  id: '${channel['parentId']}',
                  type: ChannelType.guildText,
                  name: parentName,
                )),
      category: from?.category ?? channel['category'] as String?,
      options: (from?.options ?? defaultOptions()).copyWith(
        outputDir: sources.first.parent.path,
        format: format,
      ),
      baseName: result.baseName,
      nonce: newId(6),
      status: JobStatus.done,
      messages: result.messages,
      progress: 1,
      startedAt: now,
      finishedAt: now,
      parts: [
        for (final (index, path) in result.files.indexed)
          PartRecord(
            index: index + 1,
            fileName: p.basename(path),
            startAfter: '0',
            messages: result.counts[index],
            closed: true,
            finalized: true,
          ),
      ],
    );
    await queue.adopt(job);
    return job;
  }

  late final _numbers = NumberFormat.decimalPattern(locale);

  String describe(ExportJob job) {
    final count =
        '${_numbers.format(job.messages)} message${job.messages == 1 ? '' : 's'}';
    return switch (job.status) {
      JobStatus.queued => 'Waiting',
      JobStatus.running when job.stopping == JobStop.pause => 'Pausing…',
      JobStatus.running when job.stopping == JobStop.cancel => 'Cancelling…',
      JobStatus.running =>
        job.rateLimitWait != null
            ? 'Rate limited, waiting ${formatDuration(job.rateLimitWait!)}'
            : '$count · ${(job.progress * 100).floor()}%'
                  '${(job.eta?.inSeconds ?? 0) > 0 ? ' · ${formatDuration(job.eta!)} left' : ''}',
      JobStatus.uploading => '$count · finishing uploads',
      JobStatus.paused => 'Paused at $count',
      JobStatus.done =>
        '$count · ${job.parts.length} file${job.parts.length == 1 ? '' : 's'}',
      JobStatus.failed => job.error ?? 'Failed',
      JobStatus.cancelled => 'Cancelled',
    };
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}
