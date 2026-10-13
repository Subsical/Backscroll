import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:backscroll/core/discord/permissions.dart';
import 'package:backscroll/core/discord/snowflake.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'sample_media.dart';

typedef Json = Map<String, dynamic>;

Json _user(
  String id,
  String username,
  String? name, {
  bool bot = false,
  String discriminator = '0',
}) => {
  'id': id,
  'username': username,
  'global_name': name,
  'discriminator': discriminator,
  'avatar': 'av$id',
  if (bot) 'bot': true,
};

class SampleWorld {
  SampleWorld();

  static final exportTime = DateTime.utc(2026, 3, 14, 12);

  final sam = _user('110000000000000001', 'samw', 'Sam');
  final nick = _user('110000000000000002', 'nickb', 'Nick');
  final dana = _user('110000000000000003', 'dana_k', 'Dana');
  final marta = _user('110000000000000004', 'martaa', 'Marta');
  final tom = _user('110000000000000005', 'tomtom', 'Tom');
  final chris = _user('110000000000000006', 'chrisf', 'Chris');
  final lena = _user('110000000000000007', 'lena_m', 'Lena');
  final buildbot = _user(
    '110000000000000008',
    'Buildbot',
    null,
    bot: true,
    discriminator: '7781',
  );
  final alex = _user('110000000000000009', 'alexr', 'Alex');

  late final avatars = <String, String>{
    sam['id']: 'sam',
    nick['id']: 'nick',
    dana['id']: 'dana',
    marta['id']: 'marta',
    tom['id']: 'tom',
    chris['id']: 'chris',
    lena['id']: 'lena',
    buildbot['id']: 'buildbot',
    alex['id']: 'alex',
  };

  static const studioId = '120000000000000001';
  static const devLogId = '140000000000000010';
  static const generalId = '140000000000000005';
  static const playtestingId = '140000000000000012';
  static const threadId = '140000000000000016';
  static const nickDmId = '150000000000000001';
  static const crewDmId = '150000000000000003';
  static const announcementsId = '140000000000000002';
  static const artShowcaseId = '140000000000000006';

  late final guilds = <Json>[
    {
      'id': studioId,
      'name': 'Plant Pot Games',
      'icon': 'pg',
      'owner_id': nick['id'],
      'permissions':
          '${Permission.viewChannel | Permission.readMessageHistory}',
    },
    {
      'id': '120000000000000002',
      'name': 'Book Club',
      'icon': 'owl',
      'owner_id': '1',
      'permissions':
          '${Permission.viewChannel | Permission.readMessageHistory}',
    },
    {
      'id': '120000000000000003',
      'name': 'Synth Lab',
      'icon': 'synth',
      'owner_id': '1',
      'permissions':
          '${Permission.viewChannel | Permission.readMessageHistory}',
    },
    {
      'id': '120000000000000004',
      'name': 'Trail Runners PDX',
      'icon': null,
      'owner_id': '1',
      'permissions':
          '${Permission.viewChannel | Permission.readMessageHistory}',
    },
  ];

  final guildIcons = <String, String>{
    'pg': 'plant_pot',
    'owl': 'book_club',
    'synth': 'synth_lab',
  };

  late final roles = <Json>[
    {
      'id': studioId,
      'name': '@everyone',
      'color': 0,
      'position': 0,
      'permissions':
          '${Permission.viewChannel | Permission.readMessageHistory}',
    },
    {
      'id': '130000000000000001',
      'name': 'Lead Dev',
      'color': 0xF47B67,
      'position': 6,
      'permissions': '0',
    },
    {
      'id': '130000000000000002',
      'name': 'Moderator',
      'color': 0x5DADEC,
      'position': 5,
      'permissions': '0',
    },
    {
      'id': '130000000000000003',
      'name': 'Artist',
      'color': 0x43B581,
      'position': 4,
      'permissions': '0',
    },
    {
      'id': '130000000000000004',
      'name': 'Composer',
      'color': 0xC27CFF,
      'position': 3,
      'permissions': '0',
    },
    {
      'id': '130000000000000005',
      'name': 'QA',
      'color': 0xF0A43C,
      'position': 2,
      'permissions': '0',
    },
    {
      'id': '130000000000000006',
      'name': 'Bots',
      'color': 0x8EA1E1,
      'position': 1,
      'permissions': '0',
    },
  ];

  late final members = <String, Json>{
    nick['id']: {
      'user': nick,
      'roles': ['130000000000000001'],
      'nick': null,
    },
    marta['id']: {
      'user': marta,
      'roles': ['130000000000000002'],
    },
    dana['id']: {
      'user': dana,
      'roles': ['130000000000000003'],
    },
    chris['id']: {
      'user': chris,
      'roles': ['130000000000000004'],
    },
    tom['id']: {
      'user': tom,
      'roles': ['130000000000000005'],
    },
    lena['id']: {'user': lena, 'roles': []},
    buildbot['id']: {
      'user': buildbot,
      'roles': ['130000000000000006'],
    },
  };

  Json _channel(
    String id,
    int type,
    String name, {
    String? parent,
    int position = 0,
    String? topic,
  }) => {
    'id': id,
    'type': type,
    'guild_id': studioId,
    'name': name,
    'parent_id': parent,
    'position': position,
    'topic': topic,
    'permission_overwrites': [],
  };

  late final studioChannels = <Json>[
    _channel('140000000000000001', 4, 'Information', position: 0),
    _channel(
      '140000000000000002',
      5,
      'announcements',
      parent: '140000000000000001',
      topic: 'Release notes and news',
    ),
    _channel(
      '140000000000000003',
      0,
      'rules',
      parent: '140000000000000001',
      position: 1,
    ),
    _channel('140000000000000004', 4, 'Community', position: 1),
    _channel(
      generalId,
      0,
      'general',
      parent: '140000000000000004',
      topic: 'Say hi! Be kind.',
    ),
    _channel(
      '140000000000000006',
      0,
      'art-showcase',
      parent: '140000000000000004',
      position: 1,
    ),
    _channel(
      '140000000000000007',
      15,
      'ideas',
      parent: '140000000000000004',
      position: 2,
    ),
    _channel(
      '140000000000000008',
      0,
      'off-topic',
      parent: '140000000000000004',
      position: 3,
    ),
    _channel('140000000000000009', 4, 'Development', position: 2),
    _channel(
      devLogId,
      0,
      'dev-log',
      parent: '140000000000000009',
      topic: 'Daily progress: builds, bugs and screenshots',
    ),
    _channel(
      '140000000000000011',
      0,
      'bug-reports',
      parent: '140000000000000009',
      position: 1,
    ),
    _channel(
      playtestingId,
      0,
      'playtesting',
      parent: '140000000000000009',
      position: 2,
    ),
    _channel('140000000000000013', 4, 'Voice', position: 3),
    _channel('140000000000000014', 2, 'Lounge', parent: '140000000000000013'),
    _channel(
      '140000000000000015',
      2,
      'Studio',
      parent: '140000000000000013',
      position: 1,
    ),
  ];

  static String _idAt(int month, int day) =>
      snowflakeAt(DateTime.utc(2026, month, day, 12));

  late final dmChannels = <Json>[
    {
      'id': nickDmId,
      'type': 1,
      'recipients': [nick],
      'last_message_id': _idAt(3, 14),
    },
    {
      'id': '150000000000000003',
      'type': 3,
      'name': 'expo booth',
      'recipients': [nick, dana, chris],
      'last_message_id': _idAt(3, 13),
    },
    {
      'id': '150000000000000004',
      'type': 1,
      'recipients': [alex],
      'last_message_id': _idAt(3, 11),
    },
    {
      'id': '150000000000000002',
      'type': 1,
      'recipients': [dana],
      'last_message_id': _idAt(3, 8),
    },
    {
      'id': '150000000000000005',
      'type': 1,
      'recipients': [marta],
      'last_message_id': _idAt(2, 27),
    },
  ];

  final _messages = <String, List<Json>>{};
  var _sequence = 0;
  final _pictures = <String, String>{};
  final _pictureSizes = <String, int>{};
  final pageDelay = <String, Duration>{};

  Json _message(
    String channelId,
    DateTime time,
    Json author,
    String content, {
    int type = 0,
    List<Json> attachments = const [],
    List<Json> embeds = const [],
    List<Json> reactions = const [],
    List<Json> mentions = const [],
    List<Json> stickers = const [],
    List<Json>? components,
    int? flags,
    Json? replyTo,
    Json? poll,
    Json? thread,
    Json? interaction,
    Json? reference,
    String? edited,
  }) {
    final message = <String, dynamic>{
      'id': (BigInt.parse(snowflakeAt(time)) + BigInt.from(_sequence++))
          .toString(),
      'type': replyTo != null ? 19 : type,
      'channel_id': channelId,
      'author': author,
      'content': content,
      'timestamp': time.toIso8601String(),
      'edited_timestamp': edited,
      'pinned': false,
      'attachments': attachments,
      'embeds': embeds,
      'reactions': reactions,
      'mentions': mentions,
      'mention_roles': [],
      'sticker_items': stickers,
      'components': ?components,
      'flags': ?flags,
      'poll': ?poll,
      'thread': ?thread,
      'interaction_metadata': ?interaction,
    };
    if (replyTo != null) {
      message['message_reference'] = {
        'message_id': replyTo['id'],
        'channel_id': channelId,
      };
      message['referenced_message'] = replyTo;
    } else if (reference != null) {
      message['message_reference'] = reference;
    }
    (_messages[channelId] ??= []).add(message);
    return message;
  }

  Json _reaction(String emoji, int count, {String? customId}) => {
    'count': count,
    'emoji': {'id': customId, 'name': emoji},
  };

  Json _attachment(
    String id,
    String channel,
    String name,
    String type,
    int size, {
    int? width,
    int? height,
    double? duration,
  }) => {
    'id': id,
    'filename': name,
    'size': size,
    'content_type': type,
    'url':
        'https://cdn.discordapp.com/attachments/$channel/$id/$name?ex=6612a1b0&is=66005030&hm=4f2c',
    'proxy_url':
        'https://media.discordapp.net/attachments/$channel/$id/$name?ex=6612a1b0&is=66005030&hm=4f2c',
    'width': ?width,
    'height': ?height,
    'duration_secs': ?duration,
  };

  // (file, width, height)
  static const _levelShot = ('attachments/autumn_islands.jpg', 1280, 720);
  static const _keyArt = ('attachments/dungeon_room.jpg', 1152, 648);
  static const _gallery = [
    ('attachments/sky_islands.jpg', 778, 438),
    ('attachments/town_overview.jpg', 778, 438),
    ('attachments/race_track.jpg', 778, 438),
    ('attachments/prop_lineup.jpg', 778, 438),
    ('attachments/floating_arena.jpg', 778, 438),
    ('attachments/robot_run.jpg', 1280, 720),
    ('attachments/cave_start.png', 800, 480),
  ];

  Json _picture(String id, String channelId, (String, int, int) picture) {
    final (path, width, height) = picture;
    final name = path.split('/').last;
    _pictures['/attachments/$channelId/$id/$name'] = path;
    return _attachment(
      id,
      channelId,
      name,
      name.endsWith('.png') ? 'image/png' : 'image/jpeg',
      _pictureSizes[path] ??= sampleImage(path).length,
      width: width,
      height: height,
    );
  }

  Json _media(Json attachment) => {
    'url': attachment['url'],
    'proxy_url': attachment['proxy_url'],
    'width': attachment['width'],
    'height': attachment['height'],
    'content_type': attachment['content_type'],
    'attachment_id': attachment['id'],
  };

  Json _nextPicture(String channelId, (String, int, int) picture) => _picture(
    '19${(_pictures.length + 1).toString().padLeft(16, '0')}',
    channelId,
    picture,
  );

  static const lanternEmojiId = '160000000000000001';
  static const butterflyStickerId = '170000000000000001';

  void build() {
    DateTime at(int day, int hour, int minute) =>
        DateTime.utc(2026, 3, day, hour, minute);
    const dev = devLogId;

    final screenshot = _message(
      dev,
      at(13, 18, 2),
      nick,
      "The autumn tileset is merged. Here's the floating islands level with the new trees:",
      attachments: [_picture('180000000000000001', dev, _levelShot)],
    );
    _message(
      dev,
      at(13, 18, 3),
      nick,
      'Still need to slow down the cloud parallax, it gets a bit much when you jump',
    );
    _message(
      dev,
      at(13, 18, 10),
      dana,
      'this looks *so* much better than before. the trees finally feel like part of the level instead of stickers',
      replyTo: screenshot,
      reactions: [
        _reaction('\u{1F525}', 6),
        _reaction('lantern', 4, customId: lanternEmojiId),
        _reaction('\u{2728}', 3),
      ],
    );
    _message(
      dev,
      at(13, 18, 14),
      marta,
      '> the trees finally feel like part of the level\nfully agree, this is going straight into the trailer <:lantern:$lanternEmojiId>',
    );
    final bug = _message(
      dev,
      at(13, 18, 41),
      tom,
      'Found a regression on vines. Jumping off one mid-climb leaves you stuck for about a second:\n'
      '```\n[18:39:52] PlayerController: state CLIMB -> JUMP\n[18:39:52] PlayerController: vine_contact lost\n'
      '[18:39:53] WARN stuck in CLIMB_EXIT for 42 frames\n```',
    );
    _message(
      dev,
      at(13, 18, 47),
      nick,
      'ugh, I see it. `ExitClimb()` never resets the velocity, so the next state inherits the climb speed',
      replyTo: bug,
    );
    _message(
      dev,
      at(13, 18, 49),
      nick,
      '```cs\nvoid ExitClimb()\n{\n    velocity = Vector2.zero;\n    state = State.Fall;\n    vine = null;\n}\n```',
    );
    _message(
      dev,
      at(13, 18, 50),
      nick,
      'fix is up, the bot will ping here when the build is ready',
    );

    final build = _message(
      dev,
      at(14, 9, 12),
      buildbot,
      '',
      interaction: {'id': '1', 'type': 2, 'user': nick, 'name': 'build status'},
      embeds: [
        {
          'type': 'rich',
          'title': 'Build 0.9.2 is ready',
          'url': 'https://example.com/builds/0.9.2',
          'color': 0x43B581,
          'author': {
            'name': 'Plant Pot CI',
            'icon_url':
                'https://cdn.discordapp.com/avatars/${buildbot['id']}/${buildbot['avatar']}.png?size=128',
          },
          'description': 'Vine fix and the new autumn tileset. **12 testers** have access.\nGrab it from the usual place or run `/build latest`.',
          'fields': [
            {'name': 'Windows', 'value': '84 MB', 'inline': true},
            {'name': 'macOS', 'value': '91 MB', 'inline': true},
            {'name': 'Linux', 'value': '79 MB', 'inline': true},
            {
              'name': 'Changes',
              'value': '- Fixed getting stuck when jumping off vines\n- Slower cloud parallax\n- Save files are now compressed',
              'inline': false,
            },
          ],
          'footer': {'text': 'build #418 · took 6m 12s'},
          'timestamp': at(14, 9, 12).toIso8601String(),
        },
      ],
    );
    build['pinned'] = true;
    _message(
      dev,
      at(14, 9, 20),
      nick,
      '',
      type: 6,
      reference: {'message_id': build['id'], 'channel_id': dev},
    );
    _message(
      dev,
      at(14, 10, 5),
      chris,
      'new loop for the autumn level, still rough',
      attachments: [
        _attachment(
          '180000000000000002',
          dev,
          'autumn_loop_v3.wav',
          'audio/wav',
          105884,
          duration: 2.4,
        ),
      ],
    );
    final spoiler = _message(
      dev,
      at(14, 10, 20),
      dana,
      'also, spoiler for the last level: ||the boss is a giant moth||',
    );
    _message(dev, at(14, 10, 22), nick, '\u{1F98B}\u{1F98B}', replyTo: spoiler);
    _message(
      dev,
      at(14, 10, 24),
      marta,
      'Which capsule art should go on the store page? Vote below',
      poll: {
        'question': {'text': 'Store page capsule art'},
        'answers': [
          {
            'answer_id': 1,
            'poll_media': {'text': 'Autumn islands'},
          },
          {
            'answer_id': 2,
            'poll_media': {'text': 'Dungeon room'},
          },
          {
            'answer_id': 3,
            'poll_media': {'text': 'Sky islands'},
          },
        ],
        'expiry': at(16, 10, 24).toIso8601String(),
        'allow_multiselect': false,
        'results': {
          'is_finalized': false,
          'answer_counts': [
            {'id': 1, 'count': 9, 'me_voted': false},
            {'id': 2, 'count': 14, 'me_voted': false},
            {'id': 3, 'count': 5, 'me_voted': false},
          ],
        },
      },
    );
    _message(
      dev,
      at(14, 11, 2),
      tom,
      "Next playtest is <t:1773594000:F>, that's <t:1773594000:R>. I'll keep the checklist in the thread",
      thread: {
        'id': threadId,
        'type': 11,
        'name': 'Playtest checklist',
        'parent_id': dev,
        'message_count': 8,
      },
    );
    final hello = _message(
      dev,
      at(14, 11, 15),
      lena,
      'hi everyone! found the devlog through the expo stream, the game looks great',
      reactions: [_reaction('\u{1F44B}', 5), _reaction('\u{1F49A}', 3)],
    );
    _message(
      dev,
      at(14, 11, 16),
      lena,
      '',
      stickers: [
        {'id': butterflyStickerId, 'name': 'Flutter', 'format_type': 1},
      ],
    );
    _message(
      dev,
      at(14, 11, 19),
      nick,
      'welcome <@${lena['id']}>! <#$playtestingId> has the details for the next session',
      replyTo: hello,
      mentions: [lena],
    );

    const playtest = playtestingId;
    final checklist = _attachment(
      '180000000000000008',
      playtest,
      'playtest-checklist.pdf',
      'application/pdf',
      48213,
    );
    _message(
      playtest,
      at(14, 12, 0),
      buildbot,
      '',
      type: 20,
      flags: 1 << 15,
      mentions: [tom],
      interaction: {'id': '2', 'type': 2, 'user': tom, 'name': 'playtest open'},
      components: [
        {
          'type': 17,
          'accent_color': 0xF0A43C,
          'components': [
            {
              'type': 9,
              'components': [
                {'type': 10, 'content': '## Playtest 12 is open'},
                {
                  'type': 10,
                  'content':
                      'Saturday at 18:00 UTC on build **0.9.2**. Twelve seats, first come first served. Ask <@${tom['id']}> if you get stuck.',
                },
              ],
              'accessory': {
                'type': 11,
                'media': _media(
                  _picture('180000000000000004', playtest, _gallery[6]),
                ),
                'description': 'The cave start',
              },
            },
            {'type': 14, 'divider': true, 'spacing': 1},
            {
              'type': 12,
              'items': [
                for (final (i, picture) in _gallery.take(3).indexed)
                  {
                    'media': _media(
                      _picture('18000000000000000${5 + i}', playtest, picture),
                    ),
                  },
              ],
            },
            {
              'type': 10,
              'content': '-# Three levels this round: sky islands, old town and the race track',
            },
            {
              'type': 13,
              'file': {
                'url': checklist['url'],
                'proxy_url': checklist['proxy_url'],
                'content_type': 'application/pdf',
                'attachment_id': checklist['id'],
              },
              'name': 'playtest-checklist.pdf',
              'size': 48213,
            },
            {
              'type': 1,
              'components': [
                {
                  'type': 2,
                  'style': 5,
                  'label': 'Download the build',
                  'url': 'https://example.com/builds/0.9.2',
                },
                {
                  'type': 2,
                  'style': 3,
                  'label': 'Sign up',
                  'emoji': {'id': lanternEmojiId, 'name': 'lantern'},
                  'custom_id': 'signup',
                },
                {
                  'type': 2,
                  'style': 2,
                  'label': 'Waitlist',
                  'custom_id': 'waitlist',
                  'disabled': true,
                },
              ],
            },
          ],
        },
      ],
    );
    _message(
      playtest,
      at(14, 12, 4),
      buildbot,
      'Which platform will you test on?',
      components: [
        {
          'type': 1,
          'components': [
            {
              'type': 3,
              'custom_id': 'platform',
              'placeholder': 'Pick a platform',
              'options': [
                {'label': 'Windows', 'value': 'windows'},
                {'label': 'macOS', 'value': 'macos'},
                {'label': 'Linux', 'value': 'linux'},
              ],
            },
          ],
        },
        {
          'type': 1,
          'components': [
            {'type': 2, 'style': 1, 'label': 'Save', 'custom_id': 'save'},
            {'type': 2, 'style': 4, 'label': 'Leave', 'custom_id': 'leave'},
          ],
        },
      ],
    );

    _message(generalId, at(14, 11, 12), lena, '', type: 7);
    _message(
      generalId,
      at(14, 11, 13),
      marta,
      'welcome Lena! grab a role in #rules if you want playtest pings',
      edited: at(14, 11, 20).toIso8601String(),
    );

    final dm = nickDmId;
    _message(
      dm,
      at(14, 13, 2),
      nick,
      'hey! did the export of the old #dev-log finish? I want to dig up the first lighting tests',
    );
    _message(
      dm,
      at(14, 13, 5),
      sam,
      'yep, 48k messages split into 5 parts. the media went to our R2 bucket so the links won\'t die',
    );
    _message(
      dm,
      at(14, 13, 6),
      sam,
      '',
      attachments: [
        _attachment(
          '180000000000000003',
          dm,
          'dev-log-2024.zip',
          'application/zip',
          12982000,
        ),
      ],
    );
    _message(
      dm,
      at(14, 13, 9),
      nick,
      "you're a hero \u{1F64F}",
      reactions: [_reaction('\u{2764}\u{FE0F}', 1)],
    );
  }

  void fill(
    String channelId, {
    required int count,
    required DateTime from,
    required DateTime to,
    required List<Json> authors,
    required List<String> lines,
    int imageEvery = 0,
    int seed = 1,
  }) {
    final random = Random(seed);
    final step = to.difference(from).inSeconds ~/ count;
    for (var i = 0; i < count; i++) {
      final time = from.add(Duration(seconds: i * step + random.nextInt(step)));
      final withImage = imageEvery > 0 && i % imageEvery == imageEvery - 1;
      _message(
        channelId,
        time,
        authors[random.nextInt(authors.length)],
        lines[random.nextInt(lines.length)],
        attachments: [
          if (withImage)
            _nextPicture(
              channelId,
              _gallery[i ~/ imageEvery % _gallery.length],
            ),
        ],
      );
    }
  }

  void fillHistory() {
    fill(
      artShowcaseId,
      count: 4000,
      from: DateTime.utc(2024, 4, 2),
      to: DateTime.utc(2026, 3, 12),
      authors: [dana, nick, marta, chris, lena, tom],
      imageEvery: 45,
      lines: const [
        'new screenshot from the sky islands',
        'colour pass on the floating arena',
        'tried a warmer palette for the town, thoughts?',
        'prop variations, I like the third one best',
        'wip of the cave tileset',
        'repainted the title screen background',
        'this is how the race track looks at dusk now',
        'quick study of the old town roofs',
        'the robot got a new run cycle',
        'blockout for the bridge area',
        'love the colours on this one',
        'the lighting!!',
        'can we use this for the trailer?',
        'the second one is my favourite',
        'nice',
        'this goes hard',
        'ooh the shadows on the platforms',
        'could the sky be a touch more purple?',
        'saving this as my wallpaper',
        'agreed, the darker version reads better in game',
      ],
    );
    _message(
      artShowcaseId,
      DateTime.utc(2026, 3, 12, 19, 40),
      dana,
      'key art for the dungeon chapter is done',
      attachments: [_nextPicture(artShowcaseId, _keyArt)],
    );
    _message(
      artShowcaseId,
      DateTime.utc(2026, 3, 12, 19, 52),
      nick,
      'oh wow. this is the one',
      reactions: [_reaction('\u{1F525}', 7), _reaction('\u{2728}', 4)],
    );
    fill(
      announcementsId,
      count: 180,
      from: DateTime.utc(2024, 4, 2),
      to: DateTime.utc(2026, 3, 10),
      authors: [nick, marta],
      seed: 2,
      lines: const [
        'New test build is live, check #dev-log for the notes',
        'Playtest this Saturday! Sign up in #playtesting',
        'Devlog is up: new tiles, vines and a boss fight',
        'Server maintenance tonight, the bot will be offline for an hour',
        'We hit 1,000 wishlists, thank you all!',
        'The art book preview is in #art-showcase',
      ],
    );
    fill(
      crewDmId,
      count: 3200,
      from: DateTime.utc(2025, 1, 10),
      to: DateTime.utc(2026, 3, 13),
      authors: [sam, nick, dana, chris],
      imageEvery: 60,
      seed: 3,
      lines: const [
        'who is bringing the extension cords?',
        'booth layout v2 attached',
        'I can do the morning shift',
        'printing the posters tomorrow',
        'did anyone book the van yet?',
        'the banner came out great',
        'running 10 min late, save me a coffee',
        'we need more stickers, they went fast last time',
        'ok see you all at 9',
        'demo build is on the laptop, tested twice',
      ],
    );
    for (final (minute, author, text) in [
      (4, nick, 'we got booth 14, right between the food trucks and the stage'),
      (7, dana, 'is the booth 3 m wide? the banner is 2.5'),
      (9, nick, '3 m, I measured it last year'),
      (20, chris, "I'll bring the string lights for the booth"),
      (31, sam, 'booth shifts: me 9-12, Dana 12-3, Nick and Chris 3-close'),
      (
        40,
        dana,
        'should the demo laptop face the aisle or the back of the booth?',
      ),
      (42, chris, 'the aisle, people walk past and see the trailer'),
    ]) {
      _message(crewDmId, DateTime.utc(2026, 3, 13, 18, minute), author, text);
    }
  }

  List<Json> messages(String channelId) => _messages[channelId] ?? const [];

  Future<Map<String, Uint8List>> images() async {
    final result = <String, Uint8List>{};
    for (final entry in avatars.entries) {
      result['/avatars/${entry.key}/av${entry.key}.png'] = sampleImage(
        'avatars/${entry.value}.png',
      );
    }
    for (final entry in guildIcons.entries) {
      final guild = guilds.firstWhere((g) => g['icon'] == entry.key);
      result['/icons/${guild['id']}/${entry.key}.png'] = sampleImage(
        'icons/${entry.value}.png',
      );
    }
    result['/emojis/$lanternEmojiId.png'] = sampleImage('lantern_emoji.png');
    result['/stickers/$butterflyStickerId.png'] = sampleImage(
      'butterfly_sticker.png',
    );
    result['/attachments/$devLogId/180000000000000002/autumn_loop_v3.wav'] =
        toneWav();
    result['/attachments/$nickDmId/180000000000000003/dev-log-2024.zip'] =
        Uint8List.fromList(List.filled(2048, 7));
    result['/attachments/$playtestingId/180000000000000008/playtest-checklist.pdf'] =
        Uint8List.fromList(List.filled(1024, 9));
    for (final entry in _pictures.entries) {
      result[entry.key] = sampleImage(entry.value);
    }
    return result;
  }

  http.Client cdnClient(Map<String, Uint8List> images) =>
      MockClient((request) async {
        final bytes = images[request.url.path];
        if (bytes == null) return http.Response('not found', 404);
        final ext = request.url.path.split('.').last;
        final type = switch (ext) {
          'png' => 'image/png',
          'jpg' => 'image/jpeg',
          'wav' => 'audio/wav',
          'zip' => 'application/zip',
          'pdf' => 'application/pdf',
          _ => 'application/octet-stream',
        };
        return http.Response.bytes(bytes, 200, headers: {'content-type': type});
      });

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _page(List<Json> all, Map<String, String> query) {
    final limit = int.tryParse(query['limit'] ?? '') ?? 50;
    final around = all.indexWhere((m) => m['id'] == query['around']);
    if (around >= 0) {
      final start = max(0, around - limit ~/ 2);
      return _json(
        all.sublist(start, min(all.length, start + limit)).reversed.toList(),
      );
    }
    final after = query['after'] == null ? null : BigInt.parse(query['after']!);
    final before = query['before'] == null
        ? null
        : BigInt.parse(query['before']!);
    var list = all.where((m) {
      final id = BigInt.parse(m['id'] as String);
      return (after == null || id > after) && (before == null || id < before);
    }).toList();
    list = after != null
        ? list.take(limit).toList()
        : list.reversed.take(limit).toList().reversed.toList();
    return _json(list.reversed.toList());
  }

  http.Response _search(List<Json> all, Map<String, String> query) {
    final words = (query['content'] ?? '').toLowerCase().split(' ');
    final hits = all.reversed
        .where((m) {
          final text = (m['content'] as String).toLowerCase();
          return words.every(text.contains);
        })
        .map((m) => [m])
        .toList();
    final offset = int.tryParse(query['offset'] ?? '') ?? 0;
    return _json({
      'total_results': hits.length,
      'messages': hits.skip(offset).take(25).toList(),
    });
  }

  http.Client apiClient() => MockClient((request) async {
    if (request.url.host != 'discord.com') {
      return http.Response('wrong host', 500);
    }
    final bot = request.headers['Authorization']?.startsWith('Bot ') ?? false;
    final path = request.url.path.replaceFirst('/api/v10/', '');
    final query = request.url.queryParameters;
    if (path == 'users/@me') return _json(bot ? buildbot : sam);
    if (path == 'users/@me/guilds') return _json(bot ? guilds : <Json>[]);
    if (path == 'users/@me/channels') return _json(bot ? <Json>[] : dmChannels);
    for (final guild in guilds) {
      final id = guild['id'];
      if (path == 'guilds/$id') return _json(guild);
      if (path == 'guilds/$id/channels') {
        return _json(
          id == studioId
              ? studioChannels
              : [
                  {
                    'id': '${id}9',
                    'type': 0,
                    'guild_id': id,
                    'name': 'general',
                    'position': 0,
                    'permission_overwrites': [],
                  },
                ],
        );
      }
      if (path == 'guilds/$id/roles') {
        return _json(id == studioId ? roles : [roles.first]);
      }
      if (path == 'guilds/$id/threads/active') {
        return _json({'threads': [], 'members': []});
      }
      final member = RegExp('^guilds/$id/members/(\\d+)\$').firstMatch(path);
      if (member != null) {
        final found = id == studioId ? members[member[1]] : null;
        return found == null
            ? _json({'message': 'Unknown Member', 'code': 10007}, 404)
            : _json(found);
      }
    }
    final search = RegExp(r'^(?:channels/(\d+)|guilds/\d+)/messages/search$')
        .firstMatch(path);
    if (search != null) {
      return _search(messages(search[1] ?? query['channel_id']!), query);
    }
    final pins = RegExp(r'^channels/(\d+)/messages/pins$').firstMatch(path);
    if (pins != null) {
      return _json({
        'items': [
          for (final m in messages(pins[1]!).reversed)
            if (m['pinned'] == true)
              {'pinned_at': m['timestamp'], 'message': m},
        ],
        'has_more': false,
      });
    }
    final channel = RegExp(r'^channels/(\d+)(/messages)?$').firstMatch(path);
    if (channel != null) {
      final id = channel[1]!;
      final all = [...studioChannels, ...dmChannels];
      final found = all.where((c) => c['id'] == id).firstOrNull;
      if (found == null) {
        return _json({'message': 'Unknown Channel', 'code': 10003}, 404);
      }
      if (channel[2] != null) {
        final delay = pageDelay[id];
        if (delay != null) await Future<void>.delayed(delay);
        return _page(messages(id), query);
      }
      final list = messages(id);
      return _json({
        ...found,
        if (list.isNotEmpty) 'last_message_id': list.last['id'],
      });
    }
    if (path.contains('/threads/archived/')) {
      return _json({'threads': [], 'has_more': false});
    }
    return _json({'message': 'Unknown', 'code': 0}, 404);
  });
}
