import 'dart:convert';

import 'package:backscroll/core/discord/api.dart';
import 'package:backscroll/core/discord/models.dart';
import 'package:backscroll/core/discord/rate_limiter.dart';
import 'package:backscroll/core/discord/snowflake.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('snowflakes', () {
    test('round trip a timestamp', () {
      final time = DateTime.utc(2023, 5, 17, 12, 30);
      final id = snowflakeAt(time);
      expect(snowflakeTime(id), time);
    });

    test('dates before the discord epoch clamp to zero', () {
      expect(snowflakeAt(DateTime.utc(2010)), '0');
    });
  });

  group('cleanToken', () {
    test('strips quotes and prefixes', () {
      expect(DiscordApi.cleanToken('  "abc.def"  '), 'abc.def');
      expect(DiscordApi.cleanToken('Bot xyz'), 'xyz');
    });
  });

  group('requests', () {
    test('only ever talks to discord.com', () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        return http.Response('{"id":"1","username":"a"}', 200);
      });
      final api = DiscordApi('t', TokenKind.user, client: client);
      await api.currentUser();
      expect(hosts, ['discord.com']);
    });

    test('sends bot tokens with the Bot prefix', () async {
      String? auth;
      final client = MockClient((request) async {
        auth = request.headers['Authorization'];
        return http.Response('{"id":"1","username":"b","bot":true}', 200);
      });
      await DiscordApi('secret', TokenKind.bot, client: client).currentUser();
      expect(auth, 'Bot secret');
    });

    test('waits for retry_after on 429 and retries', () async {
      final waits = <Duration>[];
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({'retry_after': 1.5, 'global': false}),
            429,
          );
        }
        return http.Response('[]', 200);
      });
      var now = DateTime.utc(2024);
      Future<void> sleep(Duration d) async {
        waits.add(d);
        now = now.add(d);
      }

      final api = DiscordApi(
        't',
        TokenKind.user,
        client: client,
        sleep: sleep,
        limiter: RateLimiter(clock: () => now, sleep: sleep),
      );
      final messages = await api.messages('123');
      expect(messages, isEmpty);
      expect(calls, 2);
      expect(waits.single.inMilliseconds, greaterThanOrEqualTo(1500));
    });

    test('respects an exhausted bucket before the next request', () async {
      final waits = <Duration>[];
      final client = MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: {
            'x-ratelimit-bucket': 'abc',
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset-after': '2.0',
          },
        ),
      );
      var now = DateTime.utc(2024);
      Future<void> sleep(Duration d) async {
        waits.add(d);
        now = now.add(d);
      }

      final api = DiscordApi(
        't',
        TokenKind.bot,
        client: client,
        sleep: sleep,
        limiter: RateLimiter(clock: () => now, sleep: sleep),
      );
      await api.messages('1');
      expect(waits, isEmpty);
      await api.messages('1');
      expect(waits.single.inMilliseconds, greaterThanOrEqualTo(2000));
    });

    test('retries server errors with backoff', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return calls < 3
            ? http.Response('oops', 502)
            : http.Response('{"id":"1","username":"a"}', 200);
      });
      final api = DiscordApi(
        't',
        TokenKind.user,
        client: client,
        sleep: (_) async {},
      );
      final me = await api.currentUser();
      expect(me.username, 'a');
      expect(calls, 3);
    });

    test('maps 403 and 404 to typed errors', () async {
      final client = MockClient(
        (request) async => request.url.path.endsWith('/messages')
            ? http.Response('{"message":"Missing Access","code":50001}', 403)
            : http.Response('{"message":"Unknown Channel","code":10003}', 404),
      );
      final api = DiscordApi('t', TokenKind.bot, client: client);
      expect(api.messages('1'), throwsA(isA<ForbiddenException>()));
      expect(api.channel('1'), throwsA(isA<NotFoundException>()));
    });
  });

  group('identify', () {
    test('falls back to a bot token when the user token is rejected', () async {
      final client = MockClient((request) async {
        final auth = request.headers['Authorization']!;
        return auth.startsWith('Bot ')
            ? http.Response('{"id":"9","username":"helper","bot":true}', 200)
            : http.Response('{"message":"401: Unauthorized"}', 401);
      });
      final (kind, user) = await DiscordApi.identify('abc', client: client);
      expect(kind, TokenKind.bot);
      expect(user.bot, isTrue);
    });

    test('rejects tokens with whitespace inside', () async {
      expect(
        DiscordApi.identify('not a token'),
        throwsA(isA<InvalidTokenException>()),
      );
    });
  });

  group('search', () {
    Map<String, dynamic> message(String id, {bool? hit}) => {
      'id': id,
      'channel_id': '10',
      'author': {'id': '1', 'username': 'a'},
      'content': 'pizza $id',
      'timestamp': '2026-03-14T09:00:00.000Z',
      'hit': ?hit,
    };

    test(
      'searches a dm by itself and a server channel through the server',
      () async {
        final requests = <Uri>[];
        final client = MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'total_results': 1,
              'messages': [
                [message('5')],
              ],
            }),
            200,
          );
        });
        final api = DiscordApi('t', TokenKind.user, client: client);
        final dm = Channel.fromJson({'id': '10', 'type': 1});
        final text = Channel.fromJson({
          'id': '11',
          'type': 0,
          'guild_id': '20',
          'nsfw': true,
        });
        final results = await api.search(dm, 'pizza');
        await api.search(text, 'pizza', offset: 25);
        expect(results.total, 1);
        expect(results.messages.single.id, '5');
        expect(requests[0].path, '/api/v10/channels/10/messages/search');
        expect(requests[0].queryParameters, {'content': 'pizza'});
        expect(requests[1].path, '/api/v10/guilds/20/messages/search');
        expect(requests[1].queryParameters, {
          'content': 'pizza',
          'channel_id': '11',
          'include_nsfw': 'true',
          'offset': '25',
        });
      },
    );

    test('keeps only the hit when results come with context', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'total_results': 2,
            'messages': [
              [message('1'), message('2', hit: true), message('3')],
              [message('7', hit: true)],
            ],
          }),
          200,
        ),
      );
      final results = await DiscordApi(
        't',
        TokenKind.user,
        client: client,
      ).search(Channel.fromJson({'id': '10', 'type': 1}), 'pizza');
      expect(results.messages.map((m) => m.id), ['2', '7']);
    });

    test('reports when discord is still indexing', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'message': 'Index not yet available. Try again later',
            'code': 110000,
            'documents_indexed': 0,
            'retry_after': 2,
          }),
          202,
        ),
      );
      final results = await DiscordApi(
        't',
        TokenKind.user,
        client: client,
      ).search(Channel.fromJson({'id': '10', 'type': 1}), 'pizza');
      expect(results.messages, isEmpty);
      expect(results.retryAfter, const Duration(seconds: 2));
    });
  });
}
