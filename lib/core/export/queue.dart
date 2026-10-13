import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../discord/api.dart';
import '../discord/models.dart';
import '../discord/snowflake.dart';
import '../media/pipeline.dart';
import '../util/files.dart';
import 'exporter.dart';
import 'job.dart';
import 'writers/writer.dart';

typedef ApiProvider = Future<DiscordApi?> Function(String accountId);
typedef PipelineFactory = MediaPipeline Function(ExportJob job);

class ExportQueue {
  ExportQueue({
    required this.store,
    required this.apiFor,
    required this.pipelineFor,
    this.assets = const ExportAssets(),
    this.onDiscard,
  });

  final JobStore store;
  final ApiProvider apiFor;
  final PipelineFactory pipelineFor;
  final ExportAssets assets;
  final Future<void> Function(ExportJob job)? onDiscard;
  final jobs = <ExportJob>[];
  final _cancels = <String, CancelToken>{};
  final _pausing = <String>{};
  final _draining = <String, Future<void>>{};
  final _changes = StreamController<void>.broadcast();
  bool _pumping = false;

  Stream<void> get changes => _changes.stream;

  File get _orderFile =>
      File('${store.directory.path}${Platform.pathSeparator}order.json');

  bool get isBusy =>
      jobs.any((j) => j.status == JobStatus.queued || j.isActive);

  ExportJob? get current =>
      jobs.where((j) => j.status == JobStatus.running).firstOrNull;

  int get remaining => jobs
      .where(
        (j) => j.status == JobStatus.queued || j.status == JobStatus.running,
      )
      .length;

  List<ExportJob> get interrupted =>
      jobs.where((j) => j.status == JobStatus.paused).toList();

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> _saveOrder() async {
    await store.directory.create(recursive: true);
    await writeAtomic(_orderFile, jsonEncode(jobs.map((j) => j.id).toList()));
  }

  Future<void> load() async {
    final loaded = {for (final j in await store.loadAll()) j.id: j};
    var order = <String>[];
    if (await _orderFile.exists()) {
      try {
        order = (jsonDecode(await _orderFile.readAsString()) as List)
            .cast<String>();
      } on FormatException {
        order = [];
      }
    }
    jobs
      ..clear()
      ..addAll([
        for (final id in order)
          if (loaded.containsKey(id)) loaded.remove(id)!,
        ...loaded.values.toList()..sort(
          (a, b) => (a.startedAt ?? DateTime(0)).compareTo(
            b.startedAt ?? DateTime(0),
          ),
        ),
      ]);
    for (final job in jobs) {
      // whatever was running when the app went away waits for the user
      if (job.status == JobStatus.running ||
          job.status == JobStatus.uploading ||
          job.status == JobStatus.queued) {
        job.status = JobStatus.paused;
        await store.save(job);
      }
    }
    _notify();
  }

  Future<void> enqueue(List<ExportJob> added) async {
    jobs.addAll(added);
    for (final job in added) {
      await store.save(job);
    }
    await _saveOrder();
    _notify();
    unawaited(_pump());
  }

  Future<void> adopt(ExportJob job) async {
    jobs.add(job);
    await store.save(job);
    await _saveOrder();
    _notify();
  }

  Future<void> resume(ExportJob job) async {
    if (!job.canResume) return;
    job
      ..status = JobStatus.queued
      ..error = null;
    await store.save(job);
    _notify();
    unawaited(_pump());
  }

  Future<void> resumeAll() async {
    for (final job in interrupted) {
      job.status = JobStatus.queued;
      await store.save(job);
    }
    _notify();
    unawaited(_pump());
  }

  void pause(ExportJob job) {
    if (job.status == JobStatus.queued) {
      job.status = JobStatus.paused;
      unawaited(store.save(job));
      _notify();
      return;
    }
    if (job.status != JobStatus.running || job.stopping != null) return;
    _pausing.add(job.id);
    job.stopping = JobStop.pause;
    _cancels[job.id]?.cancel();
    _notify();
  }

  Future<void> cancel(ExportJob job) async {
    if (job.status == JobStatus.uploading) return;
    if (job.status == JobStatus.running) {
      _pausing.remove(job.id);
      job.stopping = JobStop.cancel;
      _cancels[job.id]?.cancel();
      _notify();
      return;
    }
    if (job.isFinished) return;
    job.status = JobStatus.cancelled;
    await _discard(job);
    _notify();
  }

  Future<void> remove(ExportJob job) async {
    if (job.isActive) return;
    if (!job.isFinished) await _discard(job);
    jobs.remove(job);
    await store.delete(job.id);
    await _saveOrder();
    _notify();
  }

  Future<void> clearFinished() async {
    for (final job in jobs.where((j) => j.isFinished).toList()) {
      jobs.remove(job);
      await store.delete(job.id);
    }
    await _saveOrder();
    _notify();
  }

  Future<void> _discard(ExportJob job) async {
    for (final part in job.parts) {
      if (part.finalized) continue;
      final partial = File(job.partialPath(part));
      try {
        if (await partial.exists()) await partial.delete();
      } on FileSystemException {
        // still being finalized, which windows won't delete
      }
    }
    await onDiscard?.call(job);
    await store.save(job);
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final next = jobs
            .where((j) => j.status == JobStatus.queued)
            .firstOrNull;
        if (next == null) break;
        await _run(next);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(ExportJob job) async {
    final cancel = _cancels[job.id] = CancelToken();
    job
      ..status = JobStatus.running
      ..error = null
      ..eta = null;
    await store.save(job);
    _notify();
    try {
      final api = await apiFor(job.accountId);
      if (api == null) {
        _fail(
          job,
          'The account for this export was logged out. '
          'Log in with it again to resume.',
        );
        return;
      }
      api.limiter.onWait = (wait) {
        job.rateLimitWait = wait;
        _notify();
      };
      if (job.options.includeThreads &&
          job.channel.canHaveThreads &&
          !job.threadsQueued) {
        await _queueThreads(job, api);
      }
      if (job.channel.isThreadOnly) {
        job
          ..status = JobStatus.done
          ..progress = 1
          ..finishedAt = DateTime.now();
        return;
      }
      final exporter = ChannelExporter(
        api: api,
        job: job,
        media: pipelineFor(job),
        store: store,
        assets: assets,
        onProgress: () {
          job.rateLimitWait = null;
          _notify();
        },
        onMessagesDone: () {
          job.status = JobStatus.uploading;
          _notify();
        },
      );
      await exporter.run(cancel);
      final finishing = _finish(job, exporter);
      _draining[job.id] = finishing;
      unawaited(
        finishing.whenComplete(() {
          _draining.remove(job.id);
        }),
      );
    } on ExportCancelled {
      if (_pausing.remove(job.id)) {
        job.status = JobStatus.paused;
      } else {
        job.status = JobStatus.cancelled;
        await _discard(job);
      }
    } on Object catch (e) {
      _fail(job, _describe(e));
    } finally {
      _cancels.remove(job.id);
      job
        ..rateLimitWait = null
        ..stopping = null;
      await store.save(job);
      _notify();
    }
  }

  Future<void> _finish(ExportJob job, ChannelExporter exporter) async {
    try {
      await exporter.drain();
      job
        ..status = JobStatus.done
        ..finishedAt = DateTime.now();
    } on Object catch (e) {
      _fail(job, _describe(e));
    }
    try {
      await store.save(job);
    } on FileSystemException {
      // the next save retries
    }
    _notify();
  }

  Future<void> waitForUploads() => Future.wait(_draining.values.toList());

  void _fail(ExportJob job, String message) {
    job
      ..status = JobStatus.failed
      ..error = message;
  }

  String _describe(Object error) => switch (error) {
    InvalidTokenException() =>
      'Discord rejected the token. Log in again, then resume.',
    ForbiddenException() => 'No access to this channel anymore.',
    NotFoundException() => 'The channel no longer exists.',
    DiscordException(:final message) => message,
    FileSystemException(:final message, :final path) =>
      'Could not write ${path ?? 'the export'}: $message',
    _ => '$error',
  };

  Future<void> _queueThreads(ExportJob job, DiscordApi api) async {
    final guild = job.guild;
    if (guild == null) return;
    final threads = <String, Channel>{};
    Future<void> collect(Future<void> Function() load) async {
      try {
        await load();
      } on DiscordException {
        return;
      }
    }

    await collect(() async {
      for (final t in await api.activeThreads(guild.id)) {
        if (t.parentId == job.channel.id) threads[t.id] = t;
      }
    });
    await collect(() async {
      await for (final t in api.archivedThreads(job.channel.id)) {
        threads[t.id] = t;
      }
    });
    await collect(() async {
      await for (final t in api.archivedThreads(
        job.channel.id,
        private: true,
      )) {
        threads[t.id] = t;
      }
    });

    final after = job.options.after;
    final before = job.options.before;
    final selected = threads.values.where((t) {
      final last = t.lastMessageId;
      if (after != null &&
          last != null &&
          snowflakeTime(last).isBefore(after)) {
        return false;
      }
      if (before != null && snowflakeTime(t.id).isAfter(before)) return false;
      return true;
    }).toList()..sort((a, b) => compareSnowflakes(a.id, b.id));

    final created = [
      for (final thread in selected)
        ExportJob.create(
          accountId: job.accountId,
          channel: thread,
          options: job.options,
          guild: guild,
          parent: job.channel,
          category: job.category,
          parentJobId: job.id,
        ),
    ];
    final index = jobs.indexOf(job);
    jobs.insertAll(index + 1, created);
    for (final thread in created) {
      await store.save(thread);
    }
    job.threadsQueued = true;
    await store.save(job);
    await _saveOrder();
    _notify();
  }

  Future<void> dispose() async {
    for (final cancel in _cancels.values) {
      cancel.cancel();
    }
    await _changes.close();
  }
}
