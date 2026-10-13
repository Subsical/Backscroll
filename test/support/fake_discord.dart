import 'dart:convert';

import 'package:backscroll/core/discord/snowflake.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _page(List<Map<String, dynamic>> messages, http.Request request) {
  final after = BigInt.parse(request.url.queryParameters['after'] ?? '0');
  final limit = int.parse(request.url.queryParameters['limit'] ?? '50');
  return _json(
    messages
        .where((m) => BigInt.parse(m['id'] as String) > after)
        .take(limit)
        .toList()
        .reversed
        .toList(),
  );
}

// Each pinned message here was pinned an hour after it was sent. Discord
// lists pins newest first and pages them by that time.
http.Response _pins(List<Map<String, dynamic>> messages, http.Request request) {
  final before = request.url.queryParameters['before'];
  final limit = int.parse(request.url.queryParameters['limit'] ?? '50');
  final pins =
      [
            for (final m in messages.reversed)
              if (m['pinned'] == true)
                {
                  'pinned_at': DateTime.parse(m['timestamp'] as String)
                      .add(const Duration(hours: 1))
                      .toIso8601String(),
                  'message': m,
                },
          ]
          .where(
            (p) =>
                before == null ||
                (p['pinned_at']! as String).compareTo(before) < 0,
          )
          .toList();
  return _json({
    'items': pins.take(limit).toList(),
    'has_more': pins.length > limit,
  });
}

class FakeDiscord {
  FakeDiscord({
    required this.channel,
    required this.messages,
    this.guild,
    this.roles = const [],
    this.members = const {},
    this.guildChannels = const [],
    this.threads = const [],
    this.threadMessages = const {},
  });

  final Map<String, dynamic> channel;
  final List<Map<String, dynamic>> messages;
  final Map<String, dynamic>? guild;
  final List<Map<String, dynamic>> roles;
  final Map<String, Map<String, dynamic>> members;
  final List<Map<String, dynamic>> guildChannels;
  final List<Map<String, dynamic>> threads;
  final Map<String, List<Map<String, dynamic>>> threadMessages;
  int messageRequests = 0;
  int pinRequests = 0;
  void Function(int request)? onMessagesRequest;
  Future<void> Function(int request)? beforeMessagesReply;

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    if (request.url.host != 'discord.com') {
      return http.Response('wrong host', 500);
    }
    final path = request.url.path.replaceFirst('/api/v10/', '');
    for (final thread in threads) {
      final id = thread['id'];
      if (path == 'channels/$id') return _json(thread);
      if (path == 'channels/$id/messages') {
        return _page(threadMessages[id] ?? const [], request);
      }
    }
    final channelId = channel['id'];
    if (path == 'channels/$channelId') return _json(channel);
    if (path == 'channels/$channelId/messages/pins') {
      pinRequests++;
      return _pins(messages, request);
    }
    if (path == 'channels/$channelId/messages') {
      messageRequests++;
      onMessagesRequest?.call(messageRequests);
      await beforeMessagesReply?.call(messageRequests);
      return _page(messages, request);
    }
    final archived = RegExp(
      r'^channels/(\d+)/threads/archived/(public|private)$',
    ).firstMatch(path);
    if (archived != null) {
      if (archived[2] == 'private') {
        return _json({'message': 'Missing Permissions', 'code': 50013}, 403);
      }
      return _json({
        'threads': threads
            .where(
              (t) =>
                  t['parent_id'] == archived[1] &&
                  (t['thread_metadata'] as Map?)?['archived'] == true,
            )
            .toList(),
        'has_more': false,
      });
    }
    final guildId = guild?['id'];
    if (guildId != null) {
      if (path == 'guilds/$guildId/roles') return _json(roles);
      if (path == 'guilds/$guildId/channels') return _json(guildChannels);
      if (path == 'guilds/$guildId/threads/active') {
        return _json({
          'threads': threads
              .where((t) => (t['thread_metadata'] as Map?)?['archived'] != true)
              .toList(),
          'members': [],
        });
      }
      final member = RegExp('^guilds/$guildId/members/(\\d+)\$')
          .firstMatch(path);
      if (member != null) {
        final found = members[member[1]];
        return found == null
            ? _json({'message': 'Unknown Member', 'code': 10007}, 404)
            : _json(found);
      }
    }
    return _json({'message': 'Unknown', 'code': 0}, 404);
  }
}

const sampleUsers = [
  {
    'id': '200000000000000001',
    'username': 'nick',
    'global_name': 'Nick',
    'discriminator': '0',
    'avatar': null,
  },
  {
    'id': '200000000000000002',
    'username': 'dana',
    'global_name': 'Dana',
    'discriminator': '0',
    'avatar': null,
  },
  {
    'id': '200000000000000003',
    'username': 'helperbot',
    'discriminator': '4242',
    'avatar': null,
    'bot': true,
  },
];

const componentGifUrl =
    'https://cdn.discordapp.com/attachments/100000000000000001/500000000000000001/clip.gif?ex=abc&is=def&hm=123';
const componentZipUrl =
    'https://cdn.discordapp.com/attachments/100000000000000001/500000000000000002/build.zip?ex=abc&is=def&hm=456';
const componentThumbUrl =
    'https://images-ext-1.discordapp.net/external/sig/https/example.com/cover.png';

Map<String, dynamic> componentMessage({
  required String channelId,
  DateTime? time,
}) {
  final at = time ?? DateTime.utc(2024, 3, 2, 9);
  return {
    'id': snowflakeAt(at),
    'type': 20,
    'channel_id': channelId,
    'author': sampleUsers[2],
    'content': '',
    'timestamp': at.toIso8601String(),
    'edited_timestamp': null,
    'attachments': [],
    'embeds': [],
    'mentions': [],
    'mention_roles': [],
    'pinned': false,
    'flags': 1 << 15,
    'interaction_metadata': {
      'id': '1',
      'type': 2,
      'user': sampleUsers[0],
      'name': 'togif',
    },
    'components': [
      {
        'type': 17,
        'id': 1,
        'accent_color': 0xE67E22,
        'spoiler': false,
        'components': [
          {
            'type': 9,
            'id': 2,
            'components': [
              {'type': 10, 'id': 3, 'content': '## Clip ready'},
              {
                'type': 10,
                'id': 4,
                'content': 'Converted for <@200000000000000001> in **4 s**',
              },
            ],
            'accessory': {
              'type': 11,
              'id': 5,
              'media': {
                'url': 'https://example.com/cover.png',
                'proxy_url': componentThumbUrl,
                'width': 256,
                'height': 256,
                'content_type': 'image/png',
              },
              'description': 'Cover art',
              'spoiler': false,
            },
          },
          {'type': 14, 'id': 6, 'divider': true, 'spacing': 2},
          {
            'type': 12,
            'id': 7,
            'items': [
              {
                'media': {
                  'url': componentGifUrl,
                  'proxy_url': componentGifUrl.replaceFirst(
                    'cdn.discordapp.com',
                    'media.discordapp.net',
                  ),
                  'width': 320,
                  'height': 568,
                  'content_type': 'image/gif',
                  'attachment_id': '500000000000000001',
                  'flags': 1,
                },
                'description': null,
                'spoiler': false,
              },
            ],
          },
          {'type': 10, 'id': 8, 'content': '-# 4.80MB \u{2022} clip.gif'},
          {
            'type': 13,
            'id': 9,
            'file': {
              'url': componentZipUrl,
              'proxy_url': componentZipUrl.replaceFirst(
                'cdn.discordapp.com',
                'media.discordapp.net',
              ),
              'content_type': 'application/zip',
              'attachment_id': '500000000000000002',
            },
            'spoiler': false,
            'name': 'build.zip',
            'size': 2048,
          },
          {
            'type': 1,
            'id': 10,
            'components': [
              {
                'type': 2,
                'id': 11,
                'style': 5,
                'label': 'Open original',
                'url': 'https://example.com/original',
              },
              {
                'type': 2,
                'id': 12,
                'style': 4,
                'label': 'Delete',
                'emoji': {'id': null, 'name': '\u{1F5D1}'},
                'custom_id': 'delete',
                'disabled': true,
              },
            ],
          },
          {
            'type': 1,
            'id': 13,
            'components': [
              {
                'type': 3,
                'id': 14,
                'custom_id': 'speed',
                'placeholder': 'Playback speed',
                'options': [
                  {'label': 'Normal', 'value': '1'},
                  {'label': 'Double', 'value': '2', 'default': true},
                ],
              },
            ],
          },
        ],
      },
      {'type': 10, 'id': 15, 'content': 'Expires in a day'},
      {'type': 99, 'id': 16, 'content': 'from the future'},
    ],
  };
}

List<Map<String, dynamic>> generateMessages(
  int count, {
  required String channelId,
  DateTime? start,
}) {
  final result = <Map<String, dynamic>>[];
  var time = start ?? DateTime.utc(2024, 3, 1, 9);
  for (var i = 0; i < count; i++) {
    time = time.add(Duration(minutes: i % 6 == 0 ? 20 : 2));
    final id = (BigInt.parse(snowflakeAt(time)) + BigInt.from(i)).toString();
    final author = sampleUsers[(i ~/ 3) % sampleUsers.length];
    final message = <String, dynamic>{
      'id': id,
      'type': 0,
      'channel_id': channelId,
      'author': author,
      'content': 'Message $i with **bold** text and https://example.com/$i',
      'timestamp': time.toIso8601String(),
      'edited_timestamp': null,
      'attachments': [],
      'embeds': [],
      'mentions': [],
      'mention_roles': [],
      'pinned': false,
    };
    if (i % 10 == 9) {
      final target = result[i - 4];
      message['type'] = 19;
      message['message_reference'] = {
        'message_id': target['id'],
        'channel_id': channelId,
      };
      message['referenced_message'] = target;
    }
    if (i % 7 == 3) {
      message['reactions'] = [
        {
          'count': 2,
          'emoji': {'id': null, 'name': '\u{1F44D}'},
        },
      ];
    }
    result.add(message);
  }
  return result;
}
