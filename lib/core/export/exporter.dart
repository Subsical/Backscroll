import 'dart:async';
import 'dart:io';

import '../discord/api.dart';
import '../discord/models.dart';
import '../discord/snowflake.dart';
import '../media/pipeline.dart';
import 'context.dart';
import 'dates.dart';
import 'eta.dart';
import 'job.dart';
import 'naming.dart';
import 'options.dart';
import 'part_sink.dart';
import 'writers/html_writer.dart';
import 'writers/json_writer.dart';
import 'writers/text_writer.dart';
import 'writers/writer.dart';

class ExportCancelled implements Exception {
  @override
  String toString() => 'Export stopped';
}

class CancelToken {
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw ExportCancelled();
  }

  // the work itself isn't cancelled, so only for steps that write nothing
  Future<T> guard<T>(Future<T> work) => Future.any([
    work,
    _cancelled.future.then<T>((_) => throw ExportCancelled()),
  ]);
}

class ChannelExporter implements ExportLinks {
  ChannelExporter({
    required this.api,
    required this.job,
    required this.media,
    required this.store,
    this.assets = const ExportAssets(),
    this.onProgress,
    this.onMessagesDone,
  });

  final DiscordApi api;
  final ExportJob job;
  final MediaPipeline media;
  final JobStore store;
  final ExportAssets assets;
  final void Function()? onProgress;
  final void Function()? onMessagesDone;

  late ExportContext ctx;
  late MessageWriter _writer;
  late PartRecord _current;
  PartSink? _sink;
  int _partAdded = 0;
  late String _initialCursor;
  late DateTime _rangeEnd;
  final _finalizing = <Future<void>>[];
  final _eta = EtaEstimator();
  Future<void> _saving = Future.value();

  ExportOptions get options => job.options;
  String get _extension => options.format.extension;

  Future<void> _save() => _saving = _saving
      .then((_) {}, onError: (_) {})
      .then((_) => store.save(job));

  MessageWriter _createWriter() => switch (options.format) {
    ExportFormat.htmlDark || ExportFormat.htmlLight => HtmlWriter(
      ctx,
      options,
      assets: assets,
      links: this,
    ),
    ExportFormat.json => JsonWriter(ctx, options),
    ExportFormat.txt => TextWriter(ctx, options),
    ExportFormat.csv => CsvWriter(ctx, options),
  };

  PartInfo _info(PartRecord part) => PartInfo(
    index: part.index,
    fileName: part.fileName,
    previousFileName: part.index > 1
        ? job.parts.firstWhere((p) => p.index == part.index - 1).fileName
        : null,
  );

  @override
  String? messageHref(String messageId) {
    for (final part in job.parts.reversed) {
      final first = part.firstId;
      if (first == null || compareSnowflakes(messageId, first) < 0) continue;
      final last = part.lastId;
      if (part != _current &&
          last != null &&
          compareSnowflakes(messageId, last) > 0) {
        return null;
      }
      return part == _current
          ? '#m-$messageId'
          : '${Uri.encodeComponent(part.fileName)}#m-$messageId';
    }
    return null;
  }

  @override
  String? threadHref(Channel thread) {
    if (!options.includeThreads || job.channel.isThread) return null;
    final base = jobBaseName(
      channel: thread,
      options: options,
      guild: job.guild,
      parent: job.channel,
      category: job.category,
    );
    return Uri.encodeComponent(partFileName(base, 1, _extension));
  }

  Future<void> run(CancelToken cancel) async {
    try {
      await _export(cancel);
    } finally {
      // windows can't delete or rename the partial file while it's open
      _sink?.discard();
    }
  }

  Future<void> _export(CancelToken cancel) async {
    job.startedAt ??= DateTime.now();
    final dates = DateFormatter(
      locale: options.locale,
      utc: options.useUtc,
      now: job.startedAt,
    );
    var channel = job.channel;
    try {
      channel = await api.channel(channel.id);
    } on ForbiddenException {
      rethrow;
    } on DiscordException {
      channel = job.channel;
    }
    ctx = ExportContext(
      channel: channel,
      guild: job.guild,
      api: api,
      dates: dates,
      parent: job.parent,
    );
    await ctx.load();
    _writer = _createWriter();
    media.attach(ctx);
    await media.prepareChannel();

    _initialCursor = options.after == null ? '0' : snowflakeAt(options.after!);
    final beforeId = options.before == null
        ? null
        : snowflakeAt(options.before!);
    final now = DateTime.now().toUtc();
    final lastTime = channel.lastMessageId == null
        ? now
        : snowflakeTime(channel.lastMessageId!);
    _rangeEnd = [
      options.before ?? now,
      lastTime,
      now,
    ].reduce((a, b) => a.isBefore(b) ? a : b);

    final cursorStart = await _openStartingPart();
    if (cursorStart != null) {
      // pins arrive in one go, so pages are cut from that list instead
      final pins = options.pinnedOnly
          ? await cancel.guard(api.pins(channel.id))
          : null;
      pins?.sort((a, b) => compareSnowflakes(a.id, b.id));
      var cursor = cursorStart;
      while (true) {
        cancel.check();
        final page = pins == null
            ? await cancel.guard(api.messages(channel.id, after: cursor))
            : pins
                  .where((m) => compareSnowflakes(m.id, cursor) > 0)
                  .take(100)
                  .toList();
        if (page.isEmpty) break;
        page.sort((a, b) => compareSnowflakes(a.id, b.id));
        // Progress runs from the first message rather than the channel's
        // creation, which can be years earlier.
        job.firstMessageAt ??= snowflakeTime(page.first.id);
        final inRange = beforeId == null
            ? page
            : page.where((m) => compareSnowflakes(m.id, beforeId) < 0).toList();
        if (inRange.isNotEmpty) {
          await cancel.guard(ctx.prepare(inRange));
          await _writeMessages(inRange, cancel);
        }
        _checkpoint();
        job.progress = _fraction(snowflakeTime(page.last.id));
        job.eta = _eta.update(job.progress);
        await _save();
        onProgress?.call();
        if (inRange.length < page.length || page.length < 100) break;
        cursor = page.last.id;
      }
      await _closeCurrent();
    }

    job.progress = 1;
    job.eta = null;
    await _save();
    onMessagesDone?.call();
  }

  Future<void> drain() async {
    await Future.wait(_finalizing);
    await media.close();
    await _save();
  }

  double _fraction(DateTime time) {
    final start = job.firstMessageAt!;
    final total = _rangeEnd.difference(start).inMilliseconds;
    if (total <= 0) return 1;
    return (time.difference(start).inMilliseconds / total)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Future<void> _writeMessages(
    List<Message> messages,
    CancelToken cancel,
  ) async {
    var pending = messages;
    while (pending.isNotEmpty) {
      if (options.partitionSize > 0 && _partAdded >= options.partitionSize) {
        await _rollover();
      }
      final room = options.partitionSize > 0
          ? options.partitionSize - _partAdded
          : pending.length;
      final chunk = pending.take(room).toList();
      pending = pending.sublist(chunk.length);
      await media.preparePage(
        chunk,
        _current,
        stopped: () => cancel.isCancelled,
      );
      // nothing of this chunk is written yet, so stopping here is safe
      cancel.check();
      for (final message in chunk) {
        _writer.add(message);
        _current.firstId ??= message.id;
        _current.lastId = message.id;
        _partAdded++;
        job.messages++;
      }
    }
  }

  Future<String?> _openStartingPart() async {
    if (job.parts.isEmpty) {
      _current = PartRecord(
        index: 1,
        fileName: partFileName(job.baseName, 1, _extension),
        startAfter: _initialCursor,
      );
      job.parts.add(_current);
      _startPart(_current);
      return _initialCursor;
    }

    for (final part in job.parts) {
      if (part.closed && !part.finalized) _finalizing.add(_finalize(part));
    }
    final last = job.parts.last;
    _current = last;
    if (last.closed) return null;

    final checkpoint = job.checkpoint;
    final partial = File(job.partialPath(last));
    if (checkpoint != null &&
        await partial.exists() &&
        await partial.length() >= checkpoint.offset) {
      _sink = PartSink.open(partial.path, resumeAt: checkpoint.offset);
      _writer.startPart(_sink!);
      _writer
        ..committedCount = checkpoint.partMessages
        ..committedId = checkpoint.lastId
        ..restoreState(checkpoint.writerState);
      _partAdded = checkpoint.partMessages;
      job.messages = checkpoint.totalMessages;
      return checkpoint.lastId ?? last.startAfter;
    }

    // partial file is gone or damaged, redo this part
    job.messages = job.parts
        .where((p) => p.closed)
        .fold(0, (sum, p) => sum + p.messages);
    last
      ..firstId = null
      ..lastId = null;
    _startPart(last);
    return last.startAfter;
  }

  void _startPart(PartRecord part) {
    _sink = PartSink.open(job.partialPath(part));
    _writer.startPart(_sink!);
    _writer.begin(_info(part));
    _partAdded = 0;
    _checkpoint();
  }

  void _checkpoint() {
    final sink = _sink!;
    sink.sync();
    final pending = _partAdded - _writer.committedCount;
    job.checkpoint = JobCheckpoint(
      offset: sink.offset,
      lastId: _writer.committedId ?? _current.startAfter,
      partMessages: _writer.committedCount,
      totalMessages: job.messages - pending,
      writerState: _writer.saveState(),
    );
  }

  Future<void> _rollover() async {
    final closed = _current;
    final next = PartRecord(
      index: closed.index + 1,
      fileName: partFileName(job.baseName, closed.index + 1, _extension),
      startAfter: closed.lastId ?? closed.startAfter,
    );
    _writer.end(_info(closed), nextFileName: next.fileName);
    _sink!.close();
    closed
      ..messages = _writer.committedCount
      ..closed = true;
    job.parts.add(next);
    _current = next;
    _startPart(next);
    await _save();
    _finalizing.add(_finalize(closed));
  }

  Future<void> _closeCurrent() async {
    _writer.end(_info(_current));
    _sink!.close();
    _current
      ..messages = _writer.committedCount
      ..closed = true;
    job.checkpoint = null;
    await _save();
    _finalizing.add(_finalize(_current));
  }

  // a resumed job can still be finalizing parts from its old exporter
  Future<void> _finalize(PartRecord part) =>
      job.finalizing[part.index] ??= () async {
        await media.finalizePart(part);
        part.finalized = true;
        await _save();
      }();
}
