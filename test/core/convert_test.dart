import 'dart:convert';
import 'dart:io';

import 'package:backscroll/core/convert/converter.dart';
import 'package:backscroll/core/convert/reader.dart';
import 'package:backscroll/core/discord/api.dart';
import 'package:backscroll/core/discord/models.dart';
import 'package:backscroll/core/export/exporter.dart';
import 'package:backscroll/core/export/job.dart';
import 'package:backscroll/core/export/options.dart';
import 'package:backscroll/core/media/downloader.dart';
import 'package:backscroll/core/media/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../support/fake_discord.dart';

const channelId = '100000000000000001';

final dmChannel = <String, dynamic>{
  'id': channelId,
  'type': 1,
  'recipients': [sampleUsers[1]],
};

List<Map<String, dynamic>> mixedMessages() {
  final messages = generateMessages(200, channelId: channelId);
  messages[20]['pinned'] = true;
  messages[30]['edited_timestamp'] = messages[31]['timestamp'];
  messages[40]['content'] = 'see <@200000000000000002> about ||this||';
  messages[40]['mentions'] = [sampleUsers[1]];
  messages[50]['attachments'] = [
    {
      'id': '300000000000000001',
      'filename': 'SPOILER_plan.png',
      'size': 2048,
      'content_type': 'image/png',
      'width': 640,
      'height': 480,
      'url':
          'https://cdn.discordapp.com/attachments/$channelId/300000000000000001/SPOILER_plan.png?ex=1&is=2&hm=3',
    },
    {
      'id': '300000000000000002',
      'filename': 'voice-message.ogg',
      'size': 4096,
      'content_type': 'audio/ogg',
      'duration_secs': 3.5,
      'waveform': 'AAAA',
      'url':
          'https://cdn.discordapp.com/attachments/$channelId/300000000000000002/voice-message.ogg?ex=1&is=2&hm=3',
    },
  ];
  messages[60]['embeds'] = [
    {
      'type': 'rich',
      'title': 'Release notes',
      'url': 'https://example.com/notes',
      'description': 'Ask <@200000000000000003> or see <#$channelId>',
      'color': 0x43B581,
      'provider': {'name': 'Example'},
      'author': {'name': 'CI', 'icon_url': 'https://example.com/ci.png'},
      'fields': [
        {'name': 'Windows', 'value': '84 MB', 'inline': true},
        {'name': 'Linux', 'value': '79 MB', 'inline': true},
      ],
      'image': {
        'url': 'https://example.com/a.png',
        'proxy_url': 'https://images-ext-1.discordapp.net/external/a.png',
        'width': 800,
        'height': 400,
      },
      'footer': {'text': 'build 418'},
      'timestamp': messages[60]['timestamp'],
    },
  ];
  messages[70]['sticker_items'] = [
    {'id': '170000000000000001', 'name': 'Flutter', 'format_type': 1},
  ];
  messages[70]['content'] = '';
  messages[80]['poll'] = {
    'question': {'text': 'Lunch?'},
    'answers': [
      {
        'answer_id': 1,
        'poll_media': {
          'text': 'Soup',
          'emoji': {'id': null, 'name': '\u{1F35C}'},
        },
      },
      {
        'answer_id': 2,
        'poll_media': {'text': 'Salad'},
      },
    ],
    'expiry': messages[90]['timestamp'],
    'results': {
      'is_finalized': true,
      'answer_counts': [
        {'id': 1, 'count': 3},
        {'id': 2, 'count': 1},
      ],
    },
  };
  messages[90]
    ..['type'] = 6
    ..['content'] = ''
    ..['message_reference'] = {
      'message_id': messages[20]['id'],
      'channel_id': channelId,
    };
  messages[100]
    ..['type'] = 3
    ..['content'] = ''
    ..['call'] = {
      'participants': [sampleUsers[0]['id']],
      'ended_timestamp': messages[103]['timestamp'],
    };
  messages[110]
    ..['type'] = 19
    ..['message_reference'] = {
      'message_id': '99999999999999999',
      'channel_id': channelId,
    }
    ..['referenced_message'] = null;
  messages[120]
    ..['content'] = ''
    ..['message_reference'] = {
      'type': 1,
      'message_id': '88888888888888888',
      'channel_id': '100000000000000009',
    }
    ..['message_snapshots'] = [
      {
        'message': {
          'content': 'forwarded *text*',
          'timestamp': messages[10]['timestamp'],
          'attachments': [],
          'embeds': [],
          'sticker_items': [
            {'id': '170000000000000002', 'name': 'Wave', 'format_type': 1},
          ],
        },
      },
    ];
  messages[130]['thread'] = {
    'id': '100000000000000077',
    'type': 11,
    'name': 'Side thread',
    'message_count': 4,
  };
  messages[140]['reactions'] = [
    {
      'count': 3,
      'count_details': {'burst': 1, 'normal': 2},
      'emoji': {'id': '160000000000000001', 'name': 'party'},
    },
  ];
  messages.add(
    componentMessage(
      channelId: channelId,
      time: DateTime.parse(messages.last['timestamp'] as String)
          .add(const Duration(minutes: 30)),
    ),
  );
  return messages;
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('convert_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<Directory> export(
    String name,
    ExportFormat format, {
    int partitionSize = 0,
    List<Map<String, dynamic>>? messages,
    bool saveMedia = false,
  }) async {
    final dir = Directory('${temp.path}/$name')..createSync();
    final job = ExportJob.create(
      accountId: 'me',
      channel: Channel.fromJson(dmChannel),
      options: ExportOptions(
        outputDir: dir.path,
        format: format,
        partitionSize: partitionSize,
        mediaMode: saveMedia ? MediaMode.local : MediaMode.links,
        useUtc: true,
      ),
    )..startedAt = DateTime.utc(2024, 6, 1, 12);
    final discord = FakeDiscord(
      channel: dmChannel,
      messages: messages ?? mixedMessages(),
    );
    final exporter = ChannelExporter(
      api: DiscordApi('token', TokenKind.user, client: discord.client),
      job: job,
      media: saveMedia
          ? StandardMediaPipeline(
              job: job,
              downloader: MediaDownloader(
                client: MockClient(
                  (request) async => http.Response.bytes(
                    request.url.path.codeUnits,
                    200,
                    headers: {'content-type': 'image/png'},
                  ),
                ),
              ),
              stagingDir: '${temp.path}/staging-$name',
            )
          : LinkPipeline(job),
      store: JobStore(Directory('${temp.path}/jobs-$name')),
    );
    await exporter.run(CancelToken());
    await exporter.drain();
    return dir;
  }

  Map<String, String> files(Directory dir, String extension) => {
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.$extension'))
        p.basename(f.path): f.readAsStringSync(),
  };

  List<File> first(Directory dir, String extension) => exportParts(
    dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.$extension'))
        .first,
  );

  for (final (from, to) in [
    (ExportFormat.json, ExportFormat.htmlDark),
    (ExportFormat.json, ExportFormat.txt),
    (ExportFormat.json, ExportFormat.csv),
    (ExportFormat.htmlDark, ExportFormat.json),
    (ExportFormat.htmlLight, ExportFormat.txt),
    (ExportFormat.htmlDark, ExportFormat.csv),
  ]) {
    test('${from.name} converts to the same ${to.name} an export '
        'gives', () async {
      final source = await export('source', from, partitionSize: 80);
      final direct = await export('direct', to, partitionSize: 80);
      final parts = first(source, from.extension);
      expect(parts, hasLength(3));
      final result = await convertExport(
        sources: parts,
        target: to,
        useUtc: true,
      );
      expect(result.counts, [80, 80, 41]);
      final expected = files(direct, to.extension);
      final converted = {
        for (final path in result.files)
          p.basename(path): File(path).readAsStringSync(),
      };
      expect(converted.keys.toSet(), expected.keys.toSet());
      for (final name in expected.keys) {
        expect(converted[name] == expected[name], isTrue, reason: name);
      }
    });
  }

  for (final (from, to) in [
    (ExportFormat.json, ExportFormat.htmlDark),
    (ExportFormat.htmlDark, ExportFormat.json),
    (ExportFormat.htmlDark, ExportFormat.csv),
  ]) {
    test('${from.name} with saved attachments converts to the same '
        '${to.name}', () async {
      final source = await export('source', from, saveMedia: true);
      final direct = await export('direct', to, saveMedia: true);
      final result = await convertExport(
        sources: first(source, from.extension),
        target: to,
        useUtc: true,
      );
      final converted = File(result.files.single).readAsStringSync();
      expect(converted, contains('_files/'));
      expect(converted == files(direct, to.extension).values.single, isTrue);
    });
  }

  test('a dark page converts to a light one', () async {
    final source = await export('source', ExportFormat.htmlDark);
    final direct = await export('direct', ExportFormat.htmlLight);
    final result = await convertExport(
      sources: first(source, 'html'),
      target: ExportFormat.htmlLight,
      useUtc: true,
    );
    expect(p.basename(result.files.single), '${result.baseName}.html');
    expect(result.baseName, endsWith('(converted)'));
    expect(
      File(result.files.single).readAsStringSync(),
      files(direct, 'html').values.single,
    );
  });

  test('a converted file never replaces one that is already there', () async {
    final source = await export('source', ExportFormat.json);
    final parts = first(source, 'json');
    final once = await convertExport(sources: parts, target: ExportFormat.txt);
    final twice = await convertExport(sources: parts, target: ExportFormat.txt);
    final thrice = await convertExport(
      sources: parts,
      target: ExportFormat.txt,
    );
    expect(p.basename(twice.files.single), '${once.baseName} (converted).txt');
    expect(
      p.basename(thrice.files.single),
      '${once.baseName} (converted 2).txt',
    );
    expect(
      File(once.files.single).readAsStringSync(),
      File(thrice.files.single).readAsStringSync(),
    );
  });

  test('pages from before the data was kept say so', () async {
    final source = await export('source', ExportFormat.htmlDark);
    final file = first(source, 'html').single;
    file.writeAsStringSync(
      file.readAsStringSync().replaceAll(RegExp(r'<!--bs-[^\n]*-->\n'), ''),
    );
    await expectLater(
      convertExport(sources: [file], target: ExportFormat.json),
      throwsA(
        isA<UnreadableExport>().having(
          (e) => e.message,
          'message',
          contains('older version'),
        ),
      ),
    );
    expect(files(source, 'json'), isEmpty);
    expect(
      source.listSync().where((f) => f.path.endsWith('.partial')),
      isEmpty,
    );
  });

  test('other json files are turned away', () async {
    final file = File('${temp.path}/other.json')
      ..writeAsStringSync(jsonEncode({'messages': [], 'channel': 'general'}));
    await expectLater(
      convertExport(sources: [file], target: ExportFormat.htmlDark),
      throwsA(isA<UnreadableExport>()),
    );
    expect(temp.listSync().whereType<File>().map((f) => p.basename(f.path)), [
      'other.json',
    ]);
  });

  test('json rewritten by another tool still converts', () async {
    final source = await export('source', ExportFormat.json);
    final direct = await export('direct', ExportFormat.txt);
    final file = first(source, 'json').single;
    file.writeAsStringSync(
      const JsonEncoder.withIndent('    ')
          .convert(jsonDecode(file.readAsStringSync())),
    );
    final result = await convertExport(
      sources: [file],
      target: ExportFormat.txt,
      useUtc: true,
    );
    expect(
      File(result.files.single).readAsStringSync(),
      files(direct, 'txt').values.single,
    );
  });
}
