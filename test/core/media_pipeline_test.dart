import 'dart:convert';
import 'dart:io';

import 'package:backscroll/core/convert/converter.dart';
import 'package:backscroll/core/discord/api.dart';
import 'package:backscroll/core/discord/models.dart';
import 'package:backscroll/core/export/exporter.dart';
import 'package:backscroll/core/export/job.dart';
import 'package:backscroll/core/export/naming.dart';
import 'package:backscroll/core/export/options.dart';
import 'package:backscroll/core/media/downloader.dart';
import 'package:backscroll/core/media/link_patcher.dart';
import 'package:backscroll/core/media/pipeline.dart';
import 'package:backscroll/core/media/upload_cache.dart';
import 'package:backscroll/core/media/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_discord.dart';
import '../support/scripted_provider.dart';

const channelId = '100000000000000001';

final channel = <String, dynamic>{
  'id': channelId,
  'type': 1,
  'recipients': [sampleUsers[1]],
};

List<Map<String, dynamic>> messagesWithFiles(int count) {
  final messages = generateMessages(count, channelId: channelId);
  for (var i = 0; i < messages.length; i++) {
    final id = '${300000000000000000 + i}';
    final pdf = i % 4 == 0;
    messages[i]['attachments'] = [
      {
        'id': id,
        'filename': pdf ? 'notes $i.pdf' : 'shot_$i.png',
        'size': 3,
        'content_type': pdf ? 'application/pdf' : 'image/png',
        'url':
            'https://cdn.discordapp.com/attachments/$channelId/$id/file?ex=abc&is=def&hm=123',
      },
    ];
  }
  return messages;
}

class CdnClient {
  final requested = <String>[];

  late final http.Client client = MockClient((request) async {
    requested.add(request.url.toString());
    if (request.url.host == 'cdn.discordapp.com') {
      return http.Response.bytes(
        request.url.path.codeUnits,
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    return http.Response('nope', 404);
  });
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('pipeline'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<ExportJob> export(
    List<Map<String, dynamic>> messages,
    MediaPipeline Function(ExportJob job) pipeline, {
    MediaMode mode = MediaMode.local,
    bool keepLocal = false,
    ExportFormat format = ExportFormat.htmlDark,
    int partitionSize = 0,
    String? out,
  }) async {
    final discord = FakeDiscord(channel: channel, messages: messages);
    final job = ExportJob.create(
      accountId: 'me',
      channel: Channel.fromJson(channel),
      options: ExportOptions(
        outputDir: out ?? '${temp.path}/out',
        format: format,
        mediaMode: mode,
        keepLocalCopy: keepLocal,
        partitionSize: partitionSize,
        useUtc: true,
      ),
    );
    final exporter = ChannelExporter(
      api: DiscordApi('t', TokenKind.user, client: discord.client),
      job: job,
      media: pipeline(job),
      store: JobStore(Directory('${temp.path}/jobs')),
    );
    await exporter.run(CancelToken());
    await exporter.drain();
    return job;
  }

  test('local mode saves media next to the export', () async {
    final cdn = CdnClient();
    final job = await export(
      messagesWithFiles(5),
      (job) => StandardMediaPipeline(
        job: job,
        downloader: MediaDownloader(client: cdn.client),
        stagingDir: '${temp.path}/staging',
      ),
    );
    final names = Directory(job.mediaDir)
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(
      names,
      containsAll([
        '300000000000000000-notes_0.pdf',
        '300000000000000001-shot_1.png',
        '300000000000000004-notes_4.pdf',
      ]),
    );
    expect(names.where((n) => n.contains('-shot_')), hasLength(3));
    final html = File(job.partPath(job.parts.single)).readAsStringSync();
    final dir = Uri.encodeComponent(mediaDirName(job.baseName));
    expect(html, contains('src="$dir/300000000000000001-shot_1.png"'));
    expect(html, isNot(contains('hm=123')));
  });

  test('local mode saves the avatars a json header points to', () async {
    final cdn = CdnClient();
    final job = await export(
      messagesWithFiles(2),
      (job) => StandardMediaPipeline(
        job: job,
        downloader: MediaDownloader(client: cdn.client),
        stagingDir: '${temp.path}/staging',
      ),
      format: ExportFormat.json,
    );
    final data = jsonDecode(
      File(job.partPath(job.parts.single)).readAsStringSync(),
    ) as Map;
    final channel = data['channel'] as Map;
    final recipient = (channel['recipients'] as List).single as Map;
    expect(
      recipient['avatarUrl'],
      startsWith('${mediaDirName(job.baseName)}/'),
    );
    expect(channel['iconUrl'], recipient['avatarUrl']);
  });

  test('local mode saves the files a component message shows', () async {
    final cdn = CdnClient();
    final job = await export(
      [componentMessage(channelId: channelId)],
      (job) => StandardMediaPipeline(
        job: job,
        downloader: MediaDownloader(client: cdn.client),
        stagingDir: '${temp.path}/staging',
      ),
    );
    final names = Directory(job.mediaDir)
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(names.where((n) => n.endsWith('-clip.gif')), hasLength(1));
    expect(names.where((n) => n.endsWith('-build.zip')), hasLength(1));
    expect(cdn.requested, contains(componentThumbUrl));
  });

  test('pausing stops starting downloads for the rest of the page', () async {
    final cancel = CancelToken();
    var downloads = 0;
    final cdn = MockClient((request) async {
      downloads++;
      cancel.cancel();
      return http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    final discord = FakeDiscord(
      channel: channel,
      messages: messagesWithFiles(100),
    );
    final job = ExportJob.create(
      accountId: 'me',
      channel: Channel.fromJson(channel),
      options: ExportOptions(
        outputDir: '${temp.path}/out',
        mediaMode: MediaMode.local,
        useUtc: true,
      ),
    );
    final exporter = ChannelExporter(
      api: DiscordApi('t', TokenKind.user, client: discord.client),
      job: job,
      media: StandardMediaPipeline(
        job: job,
        downloader: MediaDownloader(client: cdn),
        stagingDir: '${temp.path}/staging',
      ),
      store: JobStore(Directory('${temp.path}/jobs')),
    );
    await expectLater(exporter.run(cancel), throwsA(isA<ExportCancelled>()));
    expect(downloads, lessThanOrEqualTo(4));
    expect(job.messages, 0);
  });

  test('re-hosting routes files and patches every part', () async {
    final cache = UploadCache.memory();
    final queue = UploadQueue(cache: cache, sleep: (_) async {});
    final images = ScriptedProvider('imgs', imagesOnly: true);
    final files = ScriptedProvider('files');
    final cdn = CdnClient();
    final job = await export(
      messagesWithFiles(12),
      (job) => StandardMediaPipeline(
        job: job,
        downloader: MediaDownloader(client: cdn.client),
        stagingDir: '${temp.path}/staging',
        cache: cache,
        uploads: queue,
        providers: [images, files],
      ),
      mode: MediaMode.rehost,
      partitionSize: 5,
    );
    expect(job.parts, hasLength(3));
    for (final part in job.parts) {
      final html = File(job.partPath(part)).readAsStringSync();
      expect(html, isNot(contains('@@bs-')));
      expect(html, isNot(contains('cdn.discordapp.com/attachments')));
      expect(File(job.partialPath(part)).existsSync(), isFalse);
    }
    final all = job.parts
        .map((p) => File(job.partPath(p)).readAsStringSync())
        .join();
    expect(all, contains('https://imgs.example/'));
    expect(all, contains('https://files.example/'));
    expect(Directory('${temp.path}/staging/${job.id}').existsSync(), isFalse);
    expect(cache.jobMedia(job.id), isEmpty);

    final converted = await convertExport(
      sources: [for (final part in job.parts) File(job.partPath(part))],
      target: ExportFormat.json,
    );
    final links = [
      for (final path in converted.files)
        for (final message
            in (jsonDecode(File(path).readAsStringSync()) as Map)['messages']
                as List)
          for (final attachment in (message as Map)['attachments'] as List)
            (attachment as Map)['url'] as String,
    ];
    expect(links, hasLength(12));
    expect(
      links.where(
        (link) =>
            !link.startsWith('https://imgs.example/') &&
            !link.startsWith('https://files.example/'),
      ),
      isEmpty,
    );

    final uploadsBefore = images.calls + files.calls;
    await export(
      messagesWithFiles(12),
      (job) => StandardMediaPipeline(
        job: job,
        downloader: MediaDownloader(client: cdn.client),
        stagingDir: '${temp.path}/staging',
        cache: cache,
        uploads: queue,
        providers: [images, files],
      ),
      mode: MediaMode.rehost,
      out: '${temp.path}/again',
    );
    expect(images.calls + files.calls, uploadsBefore);
  });

  test('falls back to the local copy when nothing accepts a file', () async {
    final cache = UploadCache.memory();
    final cdn = CdnClient();
    final job = await export(
      messagesWithFiles(4),
      (job) => StandardMediaPipeline(
        job: job,
        downloader: MediaDownloader(client: cdn.client),
        stagingDir: '${temp.path}/staging',
        cache: cache,
        uploads: UploadQueue(cache: cache, sleep: (_) async {}),
        providers: [ScriptedProvider('imgs', imagesOnly: true)],
      ),
      mode: MediaMode.rehost,
      keepLocal: true,
      format: ExportFormat.json,
    );
    final json = File(job.partPath(job.parts.single)).readAsStringSync();
    expect(
      json,
      contains(
        '"url":"${mediaDirName(job.baseName)}/300000000000000000-notes_0.pdf"',
      ),
    );
    expect(json, contains('https://imgs.example/'));
  });

  test('a resumed part re-queues uploads left pending', () async {
    final cache = UploadCache.memory();
    final provider = ScriptedProvider('p');
    final job = ExportJob.create(
      accountId: 'me',
      channel: Channel.fromJson(channel),
      options: ExportOptions(
        outputDir: '${temp.path}/out',
        mediaMode: MediaMode.rehost,
      ),
    );
    final part = PartRecord(
      index: 1,
      fileName: 'x.html',
      startAfter: '0',
      closed: true,
    );
    final staged = File('${temp.path}/staged.png')..writeAsBytesSync([1, 2, 3]);
    final sha = await hashFile(staged);
    cache.putJobMedia(
      JobMedia(
        job: job.id,
        part: 1,
        key: 'a1',
        source: 'att:1',
        path: staged.path,
        name: 'staged.png',
        size: 3,
        sha256: sha,
        contentType: 'image/png',
        fallback: 'https://cdn.discordapp.com/attachments/1/1/staged.png',
        temporary: true,
      ),
    );
    Directory('${temp.path}/out').createSync();
    File(job.partialPath(part))
        .writeAsStringSync('<img src="${mediaMarker(job.nonce, 'a1')}">\n');
    final pipeline = StandardMediaPipeline(
      job: job,
      downloader: MediaDownloader(client: CdnClient().client),
      stagingDir: '${temp.path}/staging',
      cache: cache,
      uploads: UploadQueue(cache: cache, sleep: (_) async {}),
      providers: [provider],
    );
    await pipeline.finalizePart(part);
    expect(
      File(job.partPath(part)).readAsStringSync(),
      '<img src="https://p.example/$sha">\n',
    );
    expect(staged.existsSync(), isFalse);
    expect(provider.calls, 1);
  });

  test('markers are escaped for each format', () async {
    final input = File('${temp.path}/in.csv')
      ..writeAsStringSync('"a","@@bs-n:k@@"\r\n');
    final output = File('${temp.path}/out.csv');
    await patchMarkers(
      input: input,
      output: output,
      replacements: {'k': 'https://x.dev/a"b'},
      nonce: 'n',
      format: ExportFormat.csv,
    );
    expect(output.readAsStringSync(), '"a","https://x.dev/a""b"\r\n');
  });
}
