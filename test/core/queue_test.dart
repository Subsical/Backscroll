import 'dart:async';
import 'dart:io';

import 'package:backscroll/core/discord/api.dart';
import 'package:backscroll/core/discord/models.dart';
import 'package:backscroll/core/export/job.dart';
import 'package:backscroll/core/export/options.dart';
import 'package:backscroll/core/export/queue.dart';
import 'package:backscroll/core/media/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_discord.dart';

const guildId = '400000000000000001';
const textId = '400000000000000010';
const forumId = '400000000000000020';

Map<String, dynamic> thread(
  String id,
  String parent, {
  bool archived = false,
}) => {
  'id': id,
  'type': 11,
  'guild_id': guildId,
  'parent_id': parent,
  'name': 'thread $id',
  'last_message_id': '1300000000000000000',
  'thread_metadata': {
    'archived': archived,
    'archive_timestamp': '2024-03-01T00:00:00Z',
  },
};

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('queue'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> settle(ExportQueue queue) async {
    while (queue.isBusy) {
      await queue.changes.first.timeout(const Duration(seconds: 5));
    }
    await queue.waitForUploads();
  }

  ExportQueue makeQueue(FakeDiscord discord) => ExportQueue(
    store: JobStore(Directory('${temp.path}/jobs')),
    apiFor: (_) async => DiscordApi('t', TokenKind.bot, client: discord.client),
    pipelineFor: LinkPipeline.new,
  );

  ExportOptions options({bool threads = false}) => ExportOptions(
    outputDir: '${temp.path}/out',
    includeThreads: threads,
    useUtc: true,
  );

  test('runs jobs in order and expands threads', () async {
    final discord = FakeDiscord(
      guild: {'id': guildId, 'name': 'Plant Pot Games'},
      channel: {
        'id': textId,
        'type': 0,
        'guild_id': guildId,
        'name': 'dev-log',
      },
      messages: generateMessages(30, channelId: textId),
      threads: [
        thread('400000000000000011', textId),
        thread('400000000000000012', textId, archived: true),
        thread('400000000000000021', forumId),
      ],
      threadMessages: {
        '400000000000000011': generateMessages(
          5,
          channelId: '400000000000000011',
        ),
        '400000000000000012': generateMessages(
          3,
          channelId: '400000000000000012',
        ),
        '400000000000000021': generateMessages(
          4,
          channelId: '400000000000000021',
        ),
      },
    );
    final queue = makeQueue(discord);
    final guild = Guild(id: guildId, name: 'Plant Pot Games');
    await queue.enqueue([
      ExportJob.create(
        accountId: 'bot',
        guild: guild,
        channel: Channel.fromJson({
          'id': textId,
          'type': 0,
          'guild_id': guildId,
          'name': 'dev-log',
        }),
        options: options(threads: true),
      ),
      ExportJob.create(
        accountId: 'bot',
        guild: guild,
        channel: Channel.fromJson({
          'id': forumId,
          'type': 15,
          'guild_id': guildId,
          'name': 'ideas',
        }),
        options: options(threads: true),
      ),
    ]);
    await settle(queue);

    expect(queue.jobs.map((j) => j.channel.id), [
      textId,
      '400000000000000011',
      '400000000000000012',
      forumId,
      '400000000000000021',
    ]);
    expect(
      queue.jobs.every((j) => j.status == JobStatus.done),
      isTrue,
      reason: queue.jobs.map((j) => '${j.status} ${j.error}').join('\n'),
    );
    expect(queue.jobs[1].messages, 5);
    expect(queue.jobs[3].parts, isEmpty);
    final parentHtml = File(
      queue.jobs.first.partPath(queue.jobs.first.parts.single),
    ).readAsStringSync();
    expect(parentHtml, contains('Plant Pot Games'));
    expect(
      File(queue.jobs[1].partPath(queue.jobs[1].parts.single)).existsSync(),
      isTrue,
    );

    final restarted = makeQueue(discord);
    await restarted.load();
    expect(
      restarted.jobs.map((j) => j.channel.id),
      queue.jobs.map((j) => j.channel.id),
    );
  });

  test('pausing keeps the progress and resuming finishes the job', () async {
    final messages = generateMessages(450, channelId: textId);
    final channel = {
      'id': textId,
      'type': 1,
      'recipients': [sampleUsers[0]],
    };
    final discord = FakeDiscord(channel: channel, messages: messages);
    final queue = makeQueue(discord);
    final job = ExportJob.create(
      accountId: 'me',
      channel: Channel.fromJson(channel),
      options: options(),
    );
    discord.onMessagesRequest = (n) {
      if (n == 2) queue.pause(job);
    };
    await queue.enqueue([job]);
    await settle(queue);
    expect(job.status, JobStatus.paused);
    expect(job.messages, inInclusiveRange(1, 449));

    discord.onMessagesRequest = null;
    await queue.resume(job);
    await settle(queue);
    expect(job.status, JobStatus.done);
    expect(job.messages, 450);
    final html = File(job.partPath(job.parts.single)).readAsStringSync();
    expect('id="m-'.allMatches(html).length, 450);
  });

  test('a pause shows up at once and stops a stuck request', () async {
    final channel = {
      'id': textId,
      'type': 1,
      'recipients': [sampleUsers[0]],
    };
    final discord = FakeDiscord(
      channel: channel,
      messages: generateMessages(300, channelId: textId),
    );
    final queue = makeQueue(discord);
    final job = ExportJob.create(
      accountId: 'me',
      channel: Channel.fromJson(channel),
      options: options(),
    );
    final stuck = Completer<void>();
    discord.beforeMessagesReply = (n) async {
      if (n == 2) {
        stuck.complete();
        await Completer<void>().future;
      }
    };
    await queue.enqueue([job]);
    await stuck.future;

    queue.pause(job);
    expect(job.stopping, JobStop.pause);
    expect(job.status, JobStatus.running);
    await settle(queue).timeout(const Duration(seconds: 5));
    expect(job.status, JobStatus.paused);
    expect(job.stopping, isNull);
    expect(job.messages, 100);
  });

  test('interrupted jobs come back paused after a restart', () async {
    final channel = {
      'id': textId,
      'type': 1,
      'recipients': [sampleUsers[0]],
    };
    final discord = FakeDiscord(
      channel: channel,
      messages: generateMessages(10, channelId: textId),
    );
    final store = JobStore(Directory('${temp.path}/jobs'));
    final job = ExportJob.create(
      accountId: 'me',
      channel: Channel.fromJson(channel),
      options: options(),
    )..status = JobStatus.running;
    await store.save(job);

    final queue = makeQueue(discord);
    await queue.load();
    expect(queue.jobs.single.status, JobStatus.paused);
    await queue.resumeAll();
    await settle(queue);
    expect(queue.jobs.single.status, JobStatus.done);
  });

  test('a missing account fails the job with a clear message', () async {
    final queue = ExportQueue(
      store: JobStore(Directory('${temp.path}/jobs')),
      apiFor: (_) async => null,
      pipelineFor: LinkPipeline.new,
    );
    final job = ExportJob.create(
      accountId: 'gone',
      channel: Channel.fromJson({'id': textId, 'type': 1}),
      options: options(),
    );
    await queue.enqueue([job]);
    await settle(queue);
    expect(job.status, JobStatus.failed);
    expect(job.error, contains('logged out'));
    final saved = await JobStore(Directory('${temp.path}/jobs')).loadAll();
    expect(saved.single.status, JobStatus.failed);
  });
}
