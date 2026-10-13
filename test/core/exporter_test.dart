import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backscroll/core/discord/api.dart';
import 'package:backscroll/core/discord/models.dart';
import 'package:backscroll/core/export/exporter.dart';
import 'package:backscroll/core/export/job.dart';
import 'package:backscroll/core/export/options.dart';
import 'package:backscroll/core/export/packed.dart';
import 'package:backscroll/core/media/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_discord.dart';

const channelId = '100000000000000001';

final dmChannel = <String, dynamic>{
  'id': channelId,
  'type': 1,
  'recipients': [sampleUsers[1]],
};

Future<(ExportJob, JobStore)> runExport(
  FakeDiscord discord,
  Directory dir, {
  ExportFormat format = ExportFormat.htmlDark,
  int partitionSize = 0,
  bool pinnedOnly = false,
  ExportJob? resume,
  CancelToken? cancel,
}) async {
  final store = JobStore(Directory('${dir.path}/jobs'));
  final job =
      resume ??
      ExportJob.create(
        accountId: 'me',
        channel: Channel.fromJson(dmChannel),
        options: ExportOptions(
          outputDir: '${dir.path}/out',
          format: format,
          partitionSize: partitionSize,
          pinnedOnly: pinnedOnly,
          useUtc: true,
        ),
      );
  job.startedAt ??= DateTime.utc(2024, 6, 1, 12);
  final api = DiscordApi('token', TokenKind.user, client: discord.client);
  final exporter = ChannelExporter(
    api: api,
    job: job,
    media: LinkPipeline(job),
    store: store,
  );
  await exporter.run(cancel ?? CancelToken());
  await exporter.drain();
  return (job, store);
}

Map<String, String> readOutputs(Directory dir) => {
  for (final f in Directory('${dir.path}/out').listSync().whereType<File>())
    f.uri.pathSegments.last: f.readAsStringSync(),
};

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('export_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('splits html into parts with navigation', () async {
    final discord = FakeDiscord(
      channel: dmChannel,
      messages: generateMessages(300, channelId: channelId),
    );
    final (job, _) = await runExport(discord, temp, partitionSize: 120);
    expect(job.messages, 300);
    expect(job.parts.map((p) => p.messages), [120, 120, 60]);
    final files = readOutputs(temp);
    final base = job.baseName;
    expect(files.keys.toSet(), {
      '$base.html',
      '$base [part 2].html',
      '$base [part 3].html',
    });
    for (final html in files.values) {
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html.trimRight(), endsWith('</html>'));
    }
    expect(files['$base.html'], contains('Part 2'));
    expect(
      files['$base [part 2].html'],
      contains('href="${Uri.encodeComponent('$base.html')}"'),
    );
    expect(discord.messageRequests, 4);
  });

  test('replies link to messages in earlier parts', () async {
    final messages = generateMessages(130, channelId: channelId);
    final discord = FakeDiscord(channel: dmChannel, messages: messages);
    final (job, _) = await runExport(discord, temp, partitionSize: 127);
    final part2 = readOutputs(temp)['${job.baseName} [part 2].html']!;
    final target = messages[125]['id'];
    expect(
      part2,
      contains('${Uri.encodeComponent('${job.baseName}.html')}#m-$target'),
    );
  });

  test('every json part is valid json', () async {
    final discord = FakeDiscord(
      channel: dmChannel,
      messages: generateMessages(250, channelId: channelId),
    );
    final (job, _) = await runExport(
      discord,
      temp,
      format: ExportFormat.json,
      partitionSize: 100,
    );
    final files = readOutputs(temp);
    expect(files, hasLength(3));
    var total = 0;
    for (final content in files.values) {
      final data = jsonDecode(content) as Map<String, dynamic>;
      expect(data['messageCount'], (data['messages'] as List).length);
      total += data['messageCount'] as int;
    }
    expect(total, 250);
    expect(job.parts, hasLength(3));
  });

  test('exports only the pinned messages', () async {
    final messages = generateMessages(300, channelId: channelId);
    for (var i = 0; i < messages.length; i += 4) {
      messages[i]['pinned'] = true;
    }
    final discord = FakeDiscord(channel: dmChannel, messages: messages);
    final (job, _) = await runExport(
      discord,
      temp,
      format: ExportFormat.json,
      pinnedOnly: true,
    );
    final data =
        jsonDecode(readOutputs(temp).values.single) as Map<String, dynamic>;
    expect(data['pinnedOnly'], isTrue);
    expect(
      [for (final m in data['messages'] as List) (m as Map)['id']],
      [for (var i = 0; i < messages.length; i += 4) messages[i]['id']],
    );
    expect(job.baseName, endsWith('(pinned)'));
    expect(discord.pinRequests, 2);
    expect(discord.messageRequests, 0);
  });

  test('html marks pinned messages and lists them in the header', () async {
    final messages = generateMessages(20, channelId: channelId);
    messages[5]['pinned'] = true;
    messages[6]['pinned'] = true;
    final discord = FakeDiscord(channel: dmChannel, messages: messages);
    await runExport(discord, temp);
    final html = readOutputs(temp).values.single;
    expect(html, contains('id="pins-toggle"'));
    for (final m in [messages[5], messages[6]]) {
      expect(
        html,
        contains('<div class="msg first pinned" id="m-${m['id']}">'),
      );
    }
    expect(
      '<span class="pin-mark" title="Pinned">'.allMatches(html),
      hasLength(2),
    );
  });

  test('html pages carry their messages as data', () async {
    final messages = generateMessages(200, channelId: channelId);
    final discord = FakeDiscord(channel: dmChannel, messages: messages);
    final (job, _) = await runExport(discord, temp, partitionSize: 150);
    final files = readOutputs(temp);
    final ids = <Object?>[];
    final blockCounts = <int>[];
    for (final part in job.parts) {
      final html = files[part.fileName]!;
      final head = RegExp(r'<!--bs-head:(.+)-->').firstMatch(html)![1]!;
      final header = jsonDecode(unpackData(head)) as Map<String, dynamic>;
      expect(header['part'], part.index);
      expect((header['channel'] as Map)['id'], channelId);
      final blocks = RegExp(r'<!--bs-data:(.+)-->').allMatches(html).toList();
      blockCounts.add(blocks.length);
      for (final block in blocks) {
        for (final line in unpackData(block[1]!).split('\n')) {
          ids.add((jsonDecode(line) as Map)['id']);
        }
      }
    }
    expect(blockCounts, [3, 1]);
    expect(ids, [for (final m in messages) m['id']]);
  });

  test('html exports come with a search box', () async {
    final discord = FakeDiscord(
      channel: dmChannel,
      messages: generateMessages(5, channelId: channelId),
    );
    await runExport(discord, temp);
    final html = readOutputs(temp).values.single;
    for (final id in ['find-toggle', 'find-bar', 'find-input', 'find-next']) {
      expect(html, contains('id="$id"'));
    }
  });

  test('html lays out component messages', () async {
    final discord = FakeDiscord(
      channel: dmChannel,
      messages: [componentMessage(channelId: channelId)],
    );
    await runExport(discord, temp);
    final html = readOutputs(temp).values.single;
    for (final piece in [
      '<div class="components"><div class="container accent" '
          'style="border-left-color:#e67e22">',
      '<div class="section"><div class="section-main">'
          '<div class="content"><h2>Clip ready</h2></div>',
      '<span class="mention" title="200000000000000001">@Nick</span> in '
          '<strong>4 s</strong>',
      '<div class="media thumb"><a href="$componentThumbUrl"',
      'alt="Cover art"',
      '<div class="sep large" role="separator"></div>',
      'clip.gif?ex=abc&amp;is=def&amp;hm=123" alt="" width="197" '
          'height="350" loading="lazy">',
      '<small class="subtext">4.80MB \u{2022} clip.gif</small>',
      'build.zip</a><span class="file-size">2.00 KB</span>',
      '<a class="button link" href="https://example.com/original"',
      '<span class="button danger disabled">',
      '<div class="select"><span>Double</span>',
      '<div class="content">Expires in a day</div></div>',
    ]) {
      expect(html, contains(piece));
    }
    expect(html, isNot(contains('from the future')));
  });

  test('json keeps the layout of component messages', () async {
    final discord = FakeDiscord(
      channel: dmChannel,
      messages: [
        ...generateMessages(1, channelId: channelId),
        componentMessage(channelId: channelId),
      ],
    );
    await runExport(discord, temp, format: ExportFormat.json);
    final data =
        jsonDecode(readOutputs(temp).values.single) as Map<String, dynamic>;
    final messages = (data['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.first.containsKey('components'), isFalse);

    final components = (messages.last['components'] as List)
        .cast<Map<String, dynamic>>();
    expect(components.map((c) => c['type']), ['Container', 'TextDisplay']);
    final container = components.first;
    expect(container['accentColor'], '#e67e22');
    final inside = (container['components'] as List)
        .cast<Map<String, dynamic>>();
    expect(inside.map((c) => c['type']), [
      'Section',
      'Separator',
      'MediaGallery',
      'TextDisplay',
      'File',
      'ActionRow',
      'ActionRow',
    ]);
    final section = inside[0];
    expect((section['components'] as List).last, {
      'type': 'TextDisplay',
      'content': 'Converted for <@200000000000000001> in **4 s**',
      'text': 'Converted for @Nick in **4 s**',
    });
    expect(section['accessory'], {
      'type': 'Thumbnail',
      'url': componentThumbUrl,
      'originalUrl': 'https://example.com/cover.png',
      'contentType': 'image/png',
      'width': 256,
      'height': 256,
      'description': 'Cover art',
      'isSpoiler': false,
    });
    expect(inside[1], {
      'type': 'Separator',
      'hasDivider': true,
      'spacing': 'large',
    });
    expect(
      ((inside[2]['items'] as List).single as Map)['url'],
      componentGifUrl,
    );
    expect(inside[4], {
      'type': 'File',
      'url': componentZipUrl,
      'fileName': 'build.zip',
      'fileSizeBytes': 2048,
      'contentType': 'application/zip',
      'isSpoiler': false,
    });
    final buttons = (inside[5]['components'] as List)
        .cast<Map<String, dynamic>>();
    expect(buttons.map((b) => (b['style'], b['label'], b['isDisabled'])), [
      ('link', 'Open original', false),
      ('danger', 'Delete', true),
    ]);
    expect(buttons.first['url'], 'https://example.com/original');
    expect((buttons.last['emoji'] as Map)['name'], '\u{1F5D1}');
    final select = (inside[6]['components'] as List).single as Map;
    expect(select['placeholder'], 'Playback speed');
    expect(
      [for (final o in select['options'] as List) (o as Map)['isDefault']],
      [false, true],
    );
  });

  const componentText = [
    '## Clip ready',
    'Converted for @Nick in **4 s**',
    '-# 4.80MB \u{2022} clip.gif',
    '[Open original](https://example.com/original) [\u{1F5D1} Delete]',
    '[Double]',
    'Expires in a day',
  ];

  test('plain text lists what component messages show', () async {
    final discord = FakeDiscord(
      channel: dmChannel,
      messages: [componentMessage(channelId: channelId)],
    );
    await runExport(discord, temp, format: ExportFormat.txt);
    final text = readOutputs(temp).values.single;
    expect(
      text,
      contains(
        [
          '{Used /togif by Nick}',
          ...componentText.take(2),
          componentThumbUrl,
          componentGifUrl,
          componentText[2],
          componentZipUrl,
          ...componentText.skip(3),
          '',
        ].join('\n'),
      ),
    );
  });

  test('csv puts component text and files in their columns', () async {
    final discord = FakeDiscord(
      channel: dmChannel,
      messages: [componentMessage(channelId: channelId)],
    );
    await runExport(discord, temp, format: ExportFormat.csv);
    final csv = readOutputs(temp).values.single;
    expect(
      csv,
      contains(
        '"${componentText.join('\n')}",'
        '"$componentThumbUrl,$componentGifUrl,$componentZipUrl",',
      ),
    );
  });

  test('link previews built from components keep their layout', () async {
    const picture =
        'https://images-ext-1.discordapp.net/external/sig/https/example.com/hero.png';
    final message = generateMessages(1, channelId: channelId).single;
    message['embeds'] = [
      {
        'type': 'components',
        'url': 'https://example.com/posts/version2',
        'components': [
          {
            'type': 17,
            'accent_color': 1752220,
            'components': [
              {'type': 10, 'content': '# Patch notes'},
              {
                'type': 12,
                'items': [
                  {
                    'media': {
                      'url': 'https://example.com/hero.png',
                      'proxy_url': picture,
                      'width': 800,
                      'height': 400,
                    },
                  },
                ],
              },
              {
                'type': 1,
                'components': [
                  {
                    'type': 2,
                    'style': 5,
                    'label': 'Store',
                    'url': 'https://example.com/store',
                  },
                ],
              },
            ],
          },
        ],
      },
    ];
    final outputs = <ExportFormat, String>{};
    for (final format in [
      ExportFormat.htmlDark,
      ExportFormat.json,
      ExportFormat.txt,
    ]) {
      final dir = Directory('${temp.path}/${format.name}')..createSync();
      await runExport(
        FakeDiscord(channel: dmChannel, messages: [message]),
        dir,
        format: format,
      );
      outputs[format] = readOutputs(dir).values.single;
    }

    final html = outputs[ExportFormat.htmlDark]!;
    expect(
      html,
      contains(
        '<div class="embeds"><div class="container accent" '
        'style="border-left-color:#1abc9c"><div class="content">'
        '<h1>Patch notes</h1></div>',
      ),
    );
    expect(html, contains('<img src="$picture" alt="" width="550"'));
    expect(
      html,
      contains('<a class="button link" href="https://example.com/store"'),
    );

    final data =
        jsonDecode(outputs[ExportFormat.json]!) as Map<String, dynamic>;
    final embed =
        (((data['messages'] as List).single as Map)['embeds'] as List).single
            as Map;
    expect(embed['type'], 'components');
    expect(((embed['components'] as List).single as Map)['type'], 'Container');

    expect(
      outputs[ExportFormat.txt],
      contains(
        '{Embed}\nhttps://example.com/posts/version2\n# Patch notes\n'
        '$picture\n[Store](https://example.com/store)\n',
      ),
    );
  });

  test('csv has a pinned column', () async {
    final messages = generateMessages(3, channelId: channelId);
    messages[1]['pinned'] = true;
    final discord = FakeDiscord(channel: dmChannel, messages: messages);
    await runExport(discord, temp, format: ExportFormat.csv);
    final lines = readOutputs(temp).values.single.trim().split('\r\n');
    expect(lines.first, endsWith(',ReplyTo,Pinned'));
    expect(lines.skip(1).map((l) => l.split(',').last), [
      '"false"',
      '"true"',
      '"false"',
    ]);
  });

  test('progress counts from the first message', () async {
    final messages = generateMessages(300, channelId: channelId);
    final discord = FakeDiscord(
      channel: {...dmChannel, 'last_message_id': messages.last['id']},
      messages: messages,
    );
    final job = ExportJob.create(
      accountId: 'me',
      channel: Channel.fromJson(dmChannel),
      options: ExportOptions(outputDir: '${temp.path}/out', useUtc: true),
    );
    final seen = <double>[];
    final exporter = ChannelExporter(
      api: DiscordApi('token', TokenKind.user, client: discord.client),
      job: job,
      media: LinkPipeline(job),
      store: JobStore(Directory('${temp.path}/jobs')),
      onProgress: () => seen.add(job.progress),
    );
    await exporter.run(CancelToken());
    await exporter.drain();
    expect(seen, hasLength(3));
    expect(seen.first, closeTo(1 / 3, 0.05));
    expect(job.progress, 1);
  });

  test('pausing during a slow request stops without waiting for it', () async {
    final messages = generateMessages(300, channelId: channelId);
    final clean = Directory('${temp.path}/clean')..createSync();
    await runExport(FakeDiscord(channel: dmChannel, messages: messages), clean);

    final paused = Directory('${temp.path}/paused')..createSync();
    final cancel = CancelToken();
    final stuck = FakeDiscord(channel: dmChannel, messages: messages)
      ..beforeMessagesReply = (n) async {
        if (n < 2) return;
        cancel.cancel();
        await Completer<void>().future;
      };
    await expectLater(
      runExport(
        stuck,
        paused,
        cancel: cancel,
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<ExportCancelled>()),
    );

    final saved = (await JobStore(
      Directory('${paused.path}/jobs'),
    ).loadAll()).single;
    expect(saved.messages, 100);
    await runExport(
      FakeDiscord(channel: dmChannel, messages: messages),
      paused,
      resume: saved,
    );
    expect(readOutputs(paused), readOutputs(clean));
  });

  test('empty channels still produce a file', () async {
    final discord = FakeDiscord(channel: dmChannel, messages: []);
    final (job, _) = await runExport(discord, temp);
    final html = readOutputs(temp)['${job.baseName}.html']!;
    expect(html, contains('No messages'));
  });

  for (final format in [
    ExportFormat.htmlDark,
    ExportFormat.json,
    ExportFormat.csv,
  ]) {
    test(
      'resuming after a crash gives the same ${format.name} output',
      () async {
        final messages = generateMessages(520, channelId: channelId);

        final clean = Directory('${temp.path}/clean')..createSync();
        await runExport(
          FakeDiscord(channel: dmChannel, messages: messages),
          clean,
          format: format,
          partitionSize: 150,
        );

        final crashed = Directory('${temp.path}/crashed')..createSync();
        final cancel = CancelToken();
        final interrupted = FakeDiscord(channel: dmChannel, messages: messages)
          ..onMessagesRequest = (n) {
            if (n == 4) cancel.cancel();
          };
        await expectLater(
          runExport(
            interrupted,
            crashed,
            format: format,
            partitionSize: 150,
            cancel: cancel,
          ),
          throwsA(isA<ExportCancelled>()),
        );

        final store = JobStore(Directory('${crashed.path}/jobs'));
        final saved = (await store.loadAll()).single;
        final partial = File(saved.partialPath(saved.parts.last));
        // bytes written after the last checkpoint must be thrown away
        partial.writeAsStringSync('half written junk', mode: FileMode.append);

        await runExport(
          FakeDiscord(channel: dmChannel, messages: messages),
          crashed,
          format: format,
          partitionSize: 150,
          resume: saved,
        );

        expect(readOutputs(crashed), readOutputs(clean));
      },
    );
  }
}
