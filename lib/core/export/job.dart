import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../discord/models.dart';
import '../util/files.dart';
import 'naming.dart';
import 'options.dart';

enum JobStatus { queued, running, uploading, paused, done, failed, cancelled }

enum JobStop { pause, cancel }

class PartRecord {
  PartRecord({
    required this.index,
    required this.fileName,
    required this.startAfter,
    this.firstId,
    this.lastId,
    this.messages = 0,
    this.closed = false,
    this.finalized = false,
  });

  factory PartRecord.fromJson(Map<String, dynamic> json) => PartRecord(
    index: json['index'] as int,
    fileName: json['fileName'] as String,
    startAfter: json['startAfter'] as String? ?? '0',
    firstId: json['firstId'] as String?,
    lastId: json['lastId'] as String?,
    messages: json['messages'] as int? ?? 0,
    closed: json['closed'] == true,
    finalized: json['finalized'] == true,
  );

  final int index;
  final String fileName;
  final String startAfter;
  String? firstId;
  String? lastId;
  int messages;
  bool closed;
  bool finalized;

  Map<String, dynamic> toJson() => {
    'index': index,
    'fileName': fileName,
    'startAfter': startAfter,
    'firstId': firstId,
    'lastId': lastId,
    'messages': messages,
    'closed': closed,
    'finalized': finalized,
  };
}

class JobCheckpoint {
  const JobCheckpoint({
    required this.offset,
    required this.lastId,
    required this.partMessages,
    required this.totalMessages,
    this.writerState = const {},
  });

  factory JobCheckpoint.fromJson(Map<String, dynamic> json) => JobCheckpoint(
    offset: json['offset'] as int,
    lastId: json['lastId'] as String?,
    partMessages: json['partMessages'] as int,
    totalMessages: json['totalMessages'] as int? ?? 0,
    writerState:
        (json['writerState'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  final int offset;
  final String? lastId;
  final int partMessages;
  final int totalMessages;
  final Map<String, Object?> writerState;

  Map<String, dynamic> toJson() => {
    'offset': offset,
    'lastId': lastId,
    'partMessages': partMessages,
    'totalMessages': totalMessages,
    'writerState': writerState,
  };
}

String newId([int bytes = 8]) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String jobBaseName({
  required Channel channel,
  required ExportOptions options,
  Guild? guild,
  Channel? parent,
  String? category,
}) => exportBaseName(
  channel: channel,
  guild: guild,
  category: category,
  parentName: parent?.displayName,
  after: options.after,
  before: options.before,
  pinnedOnly: options.pinnedOnly,
);

class ExportJob {
  ExportJob({
    required this.id,
    required this.accountId,
    required this.channel,
    required this.options,
    required this.baseName,
    required this.nonce,
    this.guild,
    this.parent,
    this.category,
    this.parentJobId,
    this.status = JobStatus.queued,
    this.messages = 0,
    this.progress = 0,
    this.error,
    this.startedAt,
    this.finishedAt,
    this.firstMessageAt,
    this.checkpoint,
    this.threadsQueued = false,
    List<PartRecord>? parts,
  }) : parts = parts ?? [];

  factory ExportJob.create({
    required String accountId,
    required Channel channel,
    required ExportOptions options,
    Guild? guild,
    Channel? parent,
    String? category,
    String? parentJobId,
  }) => ExportJob(
    id: newId(),
    accountId: accountId,
    channel: channel,
    options: options,
    guild: guild,
    parent: parent,
    category: category,
    parentJobId: parentJobId,
    baseName: jobBaseName(
      channel: channel,
      options: options,
      guild: guild,
      parent: parent,
      category: category,
    ),
    nonce: newId(6),
  );

  factory ExportJob.fromJson(Map<String, dynamic> json) => ExportJob(
    id: json['id'] as String,
    accountId: json['accountId'] as String,
    channel: Channel.fromJson(json['channel'] as Map<String, dynamic>),
    guild: json['guild'] == null
        ? null
        : Guild.fromJson(json['guild'] as Map<String, dynamic>),
    parent: json['parent'] == null
        ? null
        : Channel.fromJson(json['parent'] as Map<String, dynamic>),
    category: json['category'] as String?,
    parentJobId: json['parentJobId'] as String?,
    options: ExportOptions.fromJson(json['options'] as Map<String, dynamic>),
    baseName: json['baseName'] as String,
    nonce: json['nonce'] as String,
    status: JobStatus.values.byName(json['status'] as String),
    messages: json['messages'] as int? ?? 0,
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    error: json['error'] as String?,
    startedAt: json['startedAt'] == null
        ? null
        : DateTime.parse(json['startedAt'] as String),
    finishedAt: json['finishedAt'] == null
        ? null
        : DateTime.parse(json['finishedAt'] as String),
    firstMessageAt: json['firstMessageAt'] == null
        ? null
        : DateTime.parse(json['firstMessageAt'] as String),
    checkpoint: json['checkpoint'] == null
        ? null
        : JobCheckpoint.fromJson(json['checkpoint'] as Map<String, dynamic>),
    threadsQueued: json['threadsQueued'] == true,
    parts: ((json['parts'] as List?) ?? const [])
        .map((p) => PartRecord.fromJson(p as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String accountId;
  final Channel channel;
  final Guild? guild;
  final Channel? parent;
  final String? category;
  final String? parentJobId;
  final ExportOptions options;
  final String baseName;
  final String nonce;
  JobStatus status;
  int messages;
  double progress;
  String? error;
  DateTime? startedAt;
  DateTime? finishedAt;
  DateTime? firstMessageAt;
  JobCheckpoint? checkpoint;
  bool threadsQueued;
  final List<PartRecord> parts;

  Duration? eta;
  Duration? rateLimitWait;
  JobStop? stopping;
  final finalizing = <int, Future<void>>{};

  String get title => channel.isPrivate
      ? channel.displayName
      : channel.isThread
      ? '${parent?.displayName ?? 'thread'} / ${channel.displayName}'
      : '#${channel.displayName}';

  bool get isActive =>
      status == JobStatus.running || status == JobStatus.uploading;

  bool get isFinished =>
      status == JobStatus.done ||
      status == JobStatus.failed ||
      status == JobStatus.cancelled;

  bool get canResume =>
      status == JobStatus.paused || status == JobStatus.failed;

  String get mediaDir =>
      '${options.outputDir}${Platform.pathSeparator}${mediaDirName(baseName)}';

  String partPath(PartRecord part) =>
      '${options.outputDir}${Platform.pathSeparator}${part.fileName}';

  String partialPath(PartRecord part) => '${partPath(part)}.partial';

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'channel': channel.raw,
    'guild': guild?.raw,
    'parent': parent?.raw,
    'category': category,
    'parentJobId': parentJobId,
    'options': options.toJson(),
    'baseName': baseName,
    'nonce': nonce,
    'status': status.name,
    'messages': messages,
    'progress': progress,
    'error': error,
    'startedAt': startedAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'firstMessageAt': firstMessageAt?.toIso8601String(),
    'checkpoint': checkpoint?.toJson(),
    'threadsQueued': threadsQueued,
    'parts': parts.map((p) => p.toJson()).toList(),
  };
}

class JobStore {
  JobStore(this.directory);

  final Directory directory;
  final _writes = <String, Future<void>>{};

  File _file(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id.json');

  // the queue and the exporter both save the same job, so chain the writes
  Future<void> save(ExportJob job) {
    final payload = jsonEncode(job.toJson());
    final next = (_writes[job.id] ?? Future.value())
        .then((_) {}, onError: (_) {})
        .then((_) async {
          await directory.create(recursive: true);
          await writeAtomic(_file(job.id), payload);
        });
    _writes[job.id] = next;
    unawaited(
      next.then((_) {}, onError: (_) {}).whenComplete(() {
        if (identical(_writes[job.id], next)) _writes.remove(job.id);
      }),
    );
    return next;
  }

  Future<void> delete(String id) async {
    await _writes[id]?.then((_) {}, onError: (_) {});
    final file = _file(id);
    if (await file.exists()) await file.delete();
  }

  Future<List<ExportJob>> loadAll() async {
    if (!await directory.exists()) return [];
    final jobs = <ExportJob>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        // the queue keeps its order.json in the same folder
        final json = jsonDecode(await entity.readAsString());
        if (json is Map<String, dynamic>) jobs.add(ExportJob.fromJson(json));
      } on FormatException {
        continue;
      }
    }
    return jobs;
  }
}
