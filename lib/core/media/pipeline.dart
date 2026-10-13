import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../discord/models.dart';
import '../export/context.dart';
import '../export/job.dart';
import '../export/naming.dart';
import '../export/options.dart';
import '../util/files.dart';
import '../util/pool.dart';
import 'downloader.dart';
import 'link_patcher.dart';
import 'media_refs.dart';
import 'providers/provider.dart';
import 'upload_cache.dart';
import 'upload_queue.dart';

abstract class MediaPipeline {
  void attach(ExportContext ctx);

  Future<void> prepareChannel() async {}

  Future<void> preparePage(
    List<Message> messages,
    PartRecord part, {
    bool Function()? stopped,
  });

  Future<void> finalizePart(PartRecord part);

  Future<void> close() async {}
}

Future<void> promotePartial(ExportJob job, PartRecord part) async {
  final partial = job.partialPath(part);
  if (await File(partial).exists()) {
    await moveFile(partial, job.partPath(part));
  }
}

class LinkPipeline extends MediaPipeline {
  LinkPipeline(this.job);

  final ExportJob job;

  @override
  void attach(ExportContext ctx) {}

  @override
  Future<void> preparePage(
    List<Message> messages,
    PartRecord part, {
    bool Function()? stopped,
  }) async {}

  @override
  Future<void> finalizePart(PartRecord part) => promotePartial(job, part);
}

String _shortHash(String value) =>
    sha1.convert(value.codeUnits).toString().substring(0, 12);

String _withoutQuery(String url) {
  final q = url.indexOf('?');
  return q < 0 ? url : url.substring(0, q);
}

String _safeName(String name) {
  final cleaned = sanitizeFileName(name, maxLength: 80).replaceAll(' ', '_');
  return cleaned.isEmpty ? 'file' : cleaned;
}

String mediaBaseName(MediaRef ref) {
  final attachment = ref.attachment;
  if (attachment != null) {
    return '${attachment.id}-${_safeName(attachment.filename)}';
  }
  final clean = _withoutQuery(ref.url);
  final segment = Uri.tryParse(clean)?.pathSegments.lastOrNull ?? 'file';
  return '${_shortHash(clean)}-${_safeName(segment)}';
}

class StandardMediaPipeline extends MediaPipeline {
  StandardMediaPipeline({
    required this.job,
    required this.downloader,
    required this.stagingDir,
    this.cache,
    this.uploads,
    this.providers = const [],
  });

  final ExportJob job;
  final MediaDownloader downloader;
  final String stagingDir;
  final UploadCache? cache;
  final UploadQueue? uploads;
  final List<UploadProvider> providers;

  static const _pagesKept = 4;

  final _pages = Queue<Map<String, String>>();
  final _channelLookup = <String, String>{};
  final _uploadsByPart = <int, Map<String, Future<void>>>{};
  final _inflightSources = <String, Future<UploadOutcome>>{};
  Set<String>? _existing;
  late ExportContext _ctx;

  ExportOptions get options => job.options;
  bool get _full =>
      options.format.isHtml || options.format == ExportFormat.json;
  bool get _rehosting =>
      options.mediaMode == MediaMode.rehost && cache != null && uploads != null;
  List<String> get _routeIds => providers.map((p) => p.id).toList();

  @override
  void attach(ExportContext ctx) {
    _ctx = ctx;
    ctx.mediaLookup = (url) {
      for (final page in _pages) {
        final hit = page[url];
        if (hit != null) return hit;
      }
      return _channelLookup[url] ?? url;
    };
  }

  String _relative(String name) {
    final dir = mediaDirName(job.baseName);
    return options.format.isHtml
        ? '${Uri.encodeComponent(dir)}/${Uri.encodeComponent(name)}'
        : '$dir/$name';
  }

  Future<Set<String>> _existingNames() async {
    if (_existing != null) return _existing!;
    final dir = Directory(job.mediaDir);
    final names = <String>{};
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith('.download')) {
          names.add(p.basename(entity.path));
        }
      }
    }
    return _existing = names;
  }

  String _withExtension(String name, String? contentType) {
    if (p.extension(name).isNotEmpty || contentType == null) return name;
    final ext = extensionFromMime(contentType);
    return ext == null ? name : '$name.$ext';
  }

  Future<String?> _findExisting(String base) async {
    final names = await _existingNames();
    if (names.contains(base)) return base;
    for (final name in names) {
      if (name.startsWith('$base.')) return name;
    }
    return null;
  }

  Future<String?> _saveLocal(MediaRef ref) async {
    final base = mediaBaseName(ref);
    final existing = await _findExisting(base);
    if (existing != null) return existing;
    try {
      final result = await downloader.download(
        ref.url,
        p.join(job.mediaDir, base),
      );
      final name = _withExtension(base, result.contentType);
      if (name != base) {
        await File(result.path).rename(p.join(job.mediaDir, name));
      }
      (await _existingNames()).add(name);
      return name;
    } on DownloadException {
      return null;
    }
  }

  Future<void> _resolveInto(
    Map<String, String> lookup,
    MediaRef ref,
    PartRecord? part,
  ) async {
    if (_rehosting && ref.expiring && part != null) {
      await _rehost(lookup, ref, part);
      return;
    }
    if (options.savesLocalMedia) {
      final name = await _saveLocal(ref);
      if (name != null) lookup[ref.url] = _relative(name);
    }
  }

  @override
  Future<void> prepareChannel() async {
    if (!_full || !options.savesLocalMedia) return;
    final urls = {
      ?_ctx.iconUrl,
      for (final user in _ctx.channel.recipients) _ctx.avatarUrl(user),
    };
    for (final url in urls) {
      await _resolveInto(_channelLookup, MediaRef(url), null);
    }
  }

  @override
  Future<void> preparePage(
    List<Message> messages,
    PartRecord part, {
    bool Function()? stopped,
  }) async {
    if (options.mediaMode == MediaMode.links) return;
    if (_rehosting) await uploads!.waitForRoom();
    final lookup = <String, String>{};
    _pages.addFirst(lookup);
    while (_pages.length > _pagesKept) {
      _pages.removeLast();
    }
    final refs = collectMediaRefs(messages, _ctx, full: _full);
    final pool = Pool(4);
    await Future.wait(
      refs.map(
        (ref) => pool.run(() async {
          if (stopped?.call() ?? false) return;
          await _resolveInto(lookup, ref, part);
        }),
      ),
    );
  }

  String _source(MediaRef ref) => ref.attachment != null
      ? 'att:${ref.attachment!.id}'
      : 'url:${_shortHash(_withoutQuery(ref.url))}';

  String _key(String source) => source.startsWith('att:')
      ? 'a${source.substring(4)}'
      : 'u${source.substring(4)}';

  Future<void> _rehost(
    Map<String, String> lookup,
    MediaRef ref,
    PartRecord part,
  ) async {
    final cache = this.cache!;
    final source = _source(ref);
    final cached = cache.bySource(source, _routeIds);
    if (cached != null) {
      lookup[ref.url] = cached;
      return;
    }

    final keepLocal = options.keepLocalCopy;
    final base = mediaBaseName(ref);
    String path;
    String? localUrl;
    int size;
    String sha;
    String? contentType;
    try {
      if (keepLocal) {
        final name = await _saveLocal(ref);
        if (name == null) return;
        path = p.join(job.mediaDir, name);
        localUrl = _relative(name);
        size = await File(path).length();
        sha = await hashFile(File(path));
      } else {
        path = p.join(stagingDir, job.id, base);
        if (await File(path).exists()) {
          size = await File(path).length();
          sha = await hashFile(File(path));
        } else {
          final result = await downloader.download(ref.url, path);
          size = result.size;
          sha = result.sha256;
          contentType = result.contentType;
        }
      }
    } on DownloadException {
      return;
    }

    final fallback = localUrl ?? ref.url;
    final hit = cache.byHash(sha, _routeIds);
    if (hit != null) {
      cache.linkSource(source, hit.provider, sha);
      lookup[ref.url] = hit.url;
      if (!keepLocal) await _deleteQuietly(path);
      return;
    }

    final attachment = ref.attachment;
    final fileName = attachment?.filename ?? p.basename(path).substring(13);
    final file = UploadFile(
      file: File(path),
      name: fileName,
      size: size,
      contentType:
          attachment?.contentType ??
          contentType ??
          lookupMimeType(fileName) ??
          'application/octet-stream',
      sha256: sha,
    );
    final limit = options.maxUploadBytes;
    final route = providers
        .where(
          (provider) =>
              (limit == null || size <= limit) &&
              provider.rejectReason(file) == null,
        )
        .toList();
    if (route.isEmpty) {
      lookup[ref.url] = fallback;
      if (!keepLocal) await _deleteQuietly(path);
      return;
    }

    final key = _key(source);
    cache.putJobMedia(
      JobMedia(
        job: job.id,
        part: part.index,
        key: key,
        source: source,
        path: path,
        name: file.name,
        size: size,
        sha256: sha,
        contentType: file.contentType,
        fallback: fallback,
        temporary: !keepLocal,
      ),
    );
    lookup[ref.url] = mediaMarker(job.nonce, key);
    final outcome = _inflightSources[source] ??= uploads!
        .submit(UploadTask(source: source, file: file, route: route))
        .whenComplete(() {
          _inflightSources.remove(source);
        });
    (_uploadsByPart[part.index] ??= {})[key] = outcome.then(
      (result) => _record(part.index, key, result),
    );
  }

  void _record(int part, String key, UploadOutcome outcome) {
    cache!.resolveJobMedia(
      job.id,
      part,
      key,
      status: outcome.url == null ? MediaStatus.failed : MediaStatus.uploaded,
      url: outcome.url,
    );
  }

  Future<void> _retry(JobMedia row) async {
    final file = File(row.path);
    if (!await file.exists()) {
      _record(row.part, row.key, const UploadOutcome());
      return;
    }
    final upload = UploadFile(
      file: file,
      name: row.name,
      size: row.size,
      contentType: row.contentType,
      sha256: row.sha256,
    );
    final limit = options.maxUploadBytes;
    final route = providers
        .where(
          (provider) =>
              (limit == null || row.size <= limit) &&
              provider.rejectReason(upload) == null,
        )
        .toList();
    final outcome = route.isEmpty
        ? const UploadOutcome()
        : await uploads!.submit(
            UploadTask(source: row.source, file: upload, route: route),
          );
    _record(row.part, row.key, outcome);
  }

  @override
  Future<void> finalizePart(PartRecord part) async {
    final cache = this.cache;
    if (cache == null) return promotePartial(job, part);
    final rows = cache.jobMedia(job.id, part: part.index);
    if (rows.isEmpty) return promotePartial(job, part);
    final running = _uploadsByPart[part.index] ?? const {};
    await Future.wait([
      for (final row in rows)
        if (row.status == MediaStatus.pending) running[row.key] ?? _retry(row),
    ]);
    final resolved = cache.jobMedia(job.id, part: part.index);
    final partial = File(job.partialPath(part));
    if (await partial.exists()) {
      await patchMarkers(
        input: partial,
        output: File(job.partPath(part)),
        replacements: {for (final row in resolved) row.key: row.resolved},
        nonce: job.nonce,
        format: options.format,
      );
      await partial.delete();
    }
    for (final row in resolved) {
      if (row.temporary) await _deleteQuietly(row.path);
    }
    cache.deleteJobMedia(job.id, part: part.index);
    _uploadsByPart.remove(part.index);
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      return;
    }
  }

  @override
  Future<void> close() async {
    final dir = Directory(p.join(stagingDir, job.id));
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        return;
      }
    }
  }
}
