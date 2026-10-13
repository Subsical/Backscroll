import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../discord/rate_limiter.dart';
import '../util/pool.dart';
import 'providers/provider.dart';
import 'upload_cache.dart';

class UploadTask {
  const UploadTask({
    required this.source,
    required this.file,
    required this.route,
  });

  final String source;
  final UploadFile file;
  final List<UploadProvider> route;
}

class UploadOutcome {
  const UploadOutcome({this.url, this.providerId, this.error});

  final String? url;
  final String? providerId;
  final String? error;
}

class UploadStats {
  int waiting = 0;
  int active = 0;
  int done = 0;
  int failed = 0;
  int totalBytes = 0;
  int sentBytes = 0;
  int pendingBytes = 0;
  double bytesPerSecond = 0;
  String? lastError;
  final activeByProvider = <String, int>{};

  int get pending => waiting + active;
  int get total => waiting + active + done + failed;
  bool get idle => pending == 0;

  Duration? get eta {
    if (bytesPerSecond < 1 || pendingBytes <= 0) return null;
    final left = max(0, totalBytes - sentBytes);
    return Duration(seconds: (left / bytesPerSecond).round());
  }
}

class UploadQueue {
  UploadQueue({required this.cache, Sleeper? sleep, this.maxAttempts = 4})
    : _sleep = sleep ?? realSleep;

  final UploadCache cache;
  final Sleeper _sleep;
  final int maxAttempts;
  final stats = UploadStats();
  final _pools = <String, Pool>{};
  final _inflight = <String, Future<UploadOutcome>>{};
  final _changes = StreamController<void>.broadcast();
  final _random = Random();
  final _samples = <(int, int)>[];
  Timer? _notifyTimer;

  Stream<void> get changes => _changes.stream;

  void _notify() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _samples.add((now, stats.sentBytes));
    while (_samples.length > 2 && now - _samples.first.$1 > 10000) {
      _samples.removeAt(0);
    }
    if (_samples.length >= 2) {
      final (t0, b0) = _samples.first;
      final elapsed = (now - t0) / 1000;
      stats.bytesPerSecond = elapsed <= 0
          ? 0
          : max(0, stats.sentBytes - b0) / elapsed;
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  void _notifySoon() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 250), () {
      _notifyTimer = null;
      _notify();
    });
  }

  Future<UploadOutcome> submit(UploadTask task) {
    final key = task.file.sha256;
    final running = _inflight[key];
    if (running != null) return running;
    final future = _run(task);
    _inflight[key] = future;
    unawaited(
      future.whenComplete(() {
        _inflight.remove(key);
      }),
    );
    return future;
  }

  Future<void> waitForRoom({
    int maxPending = 250,
    int maxBytes = 2 * 1024 * 1024 * 1024,
  }) async {
    while (stats.pending > maxPending || stats.pendingBytes > maxBytes) {
      await changes.first.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
  }

  Duration _backoff(int attempt) => Duration(
    milliseconds:
        min(60000, 2000 * (1 << (attempt - 1))) + _random.nextInt(1000),
  );

  Future<UploadOutcome> _run(UploadTask task) async {
    final file = task.file;
    stats
      ..waiting += 1
      ..totalBytes += file.size
      ..pendingBytes += file.size;
    _notify();
    var started = false;
    String? error;

    void finish({required bool ok}) {
      if (started) {
        stats.active--;
      } else {
        stats.waiting--;
      }
      if (ok) {
        stats.done++;
      } else {
        stats.failed++;
      }
      stats.pendingBytes -= file.size;
      _notify();
    }

    for (final provider in task.route) {
      final hit = cache.byHash(file.sha256, [provider.id]);
      if (hit != null) {
        cache.linkSource(task.source, provider.id, file.sha256);
        stats.sentBytes += file.size;
        finish(ok: true);
        return UploadOutcome(url: hit.url, providerId: provider.id);
      }
      final pool = _pools.putIfAbsent(
        provider.id,
        () => Pool(provider.concurrency),
      )..size = provider.concurrency;
      try {
        final url = await pool.run(() async {
          if (!started) {
            started = true;
            stats
              ..waiting -= 1
              ..active += 1;
          }
          stats.activeByProvider.update(
            provider.id,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
          _notify();
          try {
            return await _attempts(provider, task);
          } finally {
            stats.activeByProvider.update(provider.id, (n) => n - 1);
          }
        });
        cache.remember(
          provider: provider.id,
          sha256: file.sha256,
          url: url,
          size: file.size,
          source: task.source,
        );
        finish(ok: true);
        return UploadOutcome(url: url, providerId: provider.id);
      } on UploadException catch (e) {
        error = '${provider.name}: ${e.message}';
        stats.lastError = error;
      }
    }
    finish(ok: false);
    return UploadOutcome(error: error ?? 'No provider accepted the file');
  }

  Future<String> _attempts(UploadProvider provider, UploadTask task) async {
    for (var attempt = 1; ; attempt++) {
      var reported = 0;
      try {
        return await provider.upload(
          task.file,
          onProgress: (sent) {
            stats.sentBytes += sent - reported;
            reported = sent;
            _notifySoon();
          },
        );
      } on UploadException catch (e) {
        stats.sentBytes -= reported;
        if (!e.retryable || attempt >= maxAttempts) rethrow;
        await _sleep(e.retryAfter ?? _backoff(attempt));
      } on FileSystemException catch (e) {
        stats.sentBytes -= reported;
        throw UploadException(
          'could not read ${task.file.name} (${e.message})',
        );
      }
    }
  }

  void resetStats() {
    if (!stats.idle) return;
    stats
      ..done = 0
      ..failed = 0
      ..totalBytes = 0
      ..sentBytes = 0
      ..pendingBytes = 0
      ..lastError = null;
    _samples.clear();
    _notify();
  }

  Future<void> close() async {
    _notifyTimer?.cancel();
    await _changes.close();
  }
}
