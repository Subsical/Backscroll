import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'rate_limiter.dart';

enum TokenKind { user, bot }

class DiscordException implements Exception {
  DiscordException(this.message, {this.status, this.code});

  final String message;
  final int? status;
  final int? code;

  @override
  String toString() => message;
}

class InvalidTokenException extends DiscordException {
  InvalidTokenException()
    : super(
        'The token was rejected by Discord. It may have expired or been reset.',
        status: 401,
      );
}

class ForbiddenException extends DiscordException {
  ForbiddenException(super.message, {super.code}) : super(status: 403);
}

class NotFoundException extends DiscordException {
  NotFoundException(super.message, {super.code}) : super(status: 404);
}

class SearchResults {
  const SearchResults({
    required this.total,
    required this.messages,
    this.retryAfter,
  });

  final int total;
  final List<Message> messages;

  // set while Discord is still indexing the conversation for search
  final Duration? retryAfter;
}

const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

class DiscordApi {
  DiscordApi(
    String token,
    this.kind, {
    http.Client? client,
    RateLimiter? limiter,
    Sleeper? sleep,
  }) : _authorization = kind == TokenKind.bot ? 'Bot $token' : token,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _sleep = sleep ?? realSleep,
       limiter = limiter ?? RateLimiter(sleep: sleep);

  static const host = 'discord.com';
  static const maxRetries = 5;

  final TokenKind kind;
  final String _authorization;
  final http.Client _client;
  final bool _ownsClient;
  final Sleeper _sleep;
  final RateLimiter limiter;
  final _random = Random();

  Map<String, String> get _headers => {
    'Authorization': _authorization,
    'Accept': 'application/json',
    'User-Agent': kind == TokenKind.bot
        ? 'DiscordBot (https://github.com/Subsical/Backscroll, $appVersion)'
        : 'Backscroll/$appVersion',
  };

  static String cleanToken(String raw) {
    var token = raw.trim();
    if (token.length > 1 &&
        (token.startsWith('"') && token.endsWith('"') ||
            token.startsWith("'") && token.endsWith("'"))) {
      token = token.substring(1, token.length - 1).trim();
    }
    for (final prefix in const ['Bot ', 'bot ', 'Bearer ']) {
      if (token.startsWith(prefix)) token = token.substring(prefix.length);
    }
    return token.trim();
  }

  static Future<(TokenKind, DiscordUser)> identify(
    String rawToken, {
    http.Client? client,
    Sleeper? sleep,
  }) async {
    final token = cleanToken(rawToken);
    if (token.isEmpty || token.contains(RegExp(r'\s'))) {
      throw InvalidTokenException();
    }
    final kinds = rawToken.trim().toLowerCase().startsWith('bot ')
        ? const [TokenKind.bot]
        : const [TokenKind.user, TokenKind.bot];
    for (final kind in kinds) {
      final api = DiscordApi(
        token,
        kind,
        client: client ?? http.Client(),
        sleep: sleep,
      );
      try {
        return (kind, await api.currentUser());
      } on InvalidTokenException {
        continue;
      } finally {
        if (client == null) api._client.close();
      }
    }
    throw InvalidTokenException();
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Duration _backoff(int attempt) => Duration(
    milliseconds:
        min(30000, 1000 * pow(2, attempt - 1).toInt()) + _random.nextInt(400),
  );

  (Duration, bool) _retryAfter(http.Response response) {
    double? seconds;
    var global = response.headers['x-ratelimit-global'] == 'true';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map) {
        seconds = (body['retry_after'] as num?)?.toDouble();
        global = global || body['global'] == true;
      }
    } on FormatException {
      // cloudflare sends html here
    }
    seconds ??= double.tryParse(response.headers['retry-after'] ?? '') ?? 5;
    return (Duration(milliseconds: (seconds * 1000).ceil()), global);
  }

  String _errorMessage(http.Response response, String fallback) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['message'] is String) {
        return body['message'] as String;
      }
    } on FormatException {
      return fallback;
    }
    return fallback;
  }

  int? _errorCode(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body is Map ? body['code'] as int? : null;
    } on FormatException {
      return null;
    }
  }

  Future<Object?> getJson(
    String path, {
    Map<String, String>? query,
    String? route,
  }) async {
    final uri = Uri.https(host, '/api/v10/$path', query);
    final routeKey = route ?? path;
    var failures = 0;
    var limited = 0;
    while (true) {
      await limiter.acquire(routeKey);
      final http.Response response;
      try {
        response = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 45));
      } on Exception catch (e) {
        if (e is! TimeoutException &&
            e is! SocketException &&
            e is! http.ClientException &&
            e is! HandshakeException) {
          rethrow;
        }
        if (++failures > maxRetries) {
          throw DiscordException(
            'Could not reach Discord. Check your connection.',
          );
        }
        await _sleep(_backoff(failures));
        continue;
      }
      limiter.update(routeKey, response.headers);
      final status = response.statusCode;
      if (status == 429) {
        if (++limited > 30) {
          throw DiscordException(
            'Discord kept rate limiting the requests.',
            status: 429,
          );
        }
        final (wait, global) = _retryAfter(response);
        limiter.tooManyRequests(routeKey, wait, global: global);
        continue;
      }
      if (status >= 500) {
        if (++failures > maxRetries) {
          throw DiscordException(
            'Discord returned an error ($status).',
            status: status,
          );
        }
        await _sleep(_backoff(failures));
        continue;
      }
      if (status == 401) throw InvalidTokenException();
      if (status == 403) {
        throw ForbiddenException(
          _errorMessage(response, 'Missing access'),
          code: _errorCode(response),
        );
      }
      if (status == 404) {
        throw NotFoundException(
          _errorMessage(response, 'Not found'),
          code: _errorCode(response),
        );
      }
      if (status >= 400) {
        throw DiscordException(
          _errorMessage(response, 'Request failed ($status)'),
          status: status,
          code: _errorCode(response),
        );
      }
      if (response.bodyBytes.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
  }

  Future<Json> _object(
    String path, {
    Map<String, String>? query,
    String? route,
  }) async => (await getJson(path, query: query, route: route) as Map)
      .cast<String, dynamic>();

  Future<List<Json>> _array(
    String path, {
    Map<String, String>? query,
    String? route,
  }) async =>
      ((await getJson(path, query: query, route: route) as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  Future<DiscordUser> currentUser() async =>
      DiscordUser.fromJson(await _object('users/@me'));

  Future<List<Guild>> guilds() async {
    final result = <Guild>[];
    var after = '0';
    while (true) {
      final page = await _array(
        'users/@me/guilds',
        query: {'limit': '200', 'after': after},
      );
      result.addAll(page.map(Guild.fromJson));
      if (page.length < 200) return result;
      after = page.last['id'].toString();
    }
  }

  Future<Guild> guild(String id) async =>
      Guild.fromJson(await _object('guilds/$id'));

  Future<List<Channel>> guildChannels(String guildId) async =>
      (await _array('guilds/$guildId/channels'))
          .map((j) => Channel.fromJson({...j, 'guild_id': guildId}))
          .toList();

  Future<List<Role>> guildRoles(String guildId) async =>
      (await _array('guilds/$guildId/roles')).map(Role.fromJson).toList();

  Future<GuildMember?> member(String guildId, String userId) async {
    try {
      return GuildMember.fromJson(
        await _object(
          'guilds/$guildId/members/$userId',
          route: 'guilds/$guildId/members',
        ),
      );
    } on NotFoundException {
      return null;
    }
  }

  Future<List<Channel>> privateChannels() async =>
      (await _array('users/@me/channels')).map(Channel.fromJson).toList();

  Future<Channel> channel(String id) async =>
      Channel.fromJson(await _object('channels/$id'));

  Future<List<Message>> messages(
    String channelId, {
    String? after,
    String? before,
    String? around,
    int limit = 100,
  }) async => (await _array(
    'channels/$channelId/messages',
    query: {
      'limit': '$limit',
      'after': ?after,
      'before': ?before,
      'around': ?around,
    },
  )).map(Message.fromJson).toList();

  // User accounts can search a DM on its own. Bots search the whole server
  // and narrow it down to the channel, which needs the Message Content intent.
  Future<SearchResults> search(
    Channel channel,
    String content, {
    int offset = 0,
  }) async {
    final guildId = channel.isPrivate ? null : channel.guildId;
    final body = await _object(
      guildId == null
          ? 'channels/${channel.id}/messages/search'
          : 'guilds/$guildId/messages/search',
      query: {
        'content': content,
        if (guildId != null) 'channel_id': channel.id,
        if (channel.nsfw) 'include_nsfw': 'true',
        if (offset > 0) 'offset': '$offset',
      },
    );
    if (body['messages'] is! List) {
      final seconds = (body['retry_after'] as num?)?.toDouble() ?? 0;
      return SearchResults(
        total: 0,
        messages: const [],
        retryAfter: Duration(milliseconds: max(1000, (seconds * 1000).ceil())),
      );
    }
    final messages = <Message>[];
    // older responses include context, the match is marked as hit
    for (final group in body['messages'] as List) {
      if (group is! List) continue;
      final items = group.whereType<Map<String, dynamic>>().toList();
      final hits = items.where((m) => m['hit'] == true).toList();
      messages.addAll((hits.isEmpty ? items : hits).map(Message.fromJson));
    }
    return SearchResults(
      total: (body['total_results'] as num?)?.toInt() ?? messages.length,
      messages: messages,
    );
  }

  // Discord pages pins by the time they were pinned, newest first.
  Future<List<Message>> pins(String channelId) async {
    final result = <Message>[];
    String? before;
    while (true) {
      final body = await _object(
        'channels/$channelId/messages/pins',
        query: {'limit': '50', 'before': ?before},
      );
      final items = ((body['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      for (final item in items) {
        final message = item['message'];
        if (message is Map<String, dynamic>) {
          result.add(Message.fromJson({...message, 'pinned': true}));
        }
      }
      before = items.lastOrNull?['pinned_at'] as String?;
      if (body['has_more'] != true || before == null) return result;
    }
  }

  Future<List<Channel>> activeThreads(String guildId) async {
    final body = await _object('guilds/$guildId/threads/active');
    return ((body['threads'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Channel.fromJson)
        .toList();
  }

  Stream<Channel> archivedThreads(
    String channelId, {
    bool private = false,
  }) async* {
    String? before;
    while (true) {
      final body = await _object(
        'channels/$channelId/threads/archived/${private ? 'private' : 'public'}',
        query: {'limit': '100', 'before': ?before},
      );
      final threads = ((body['threads'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Channel.fromJson)
          .toList();
      for (final thread in threads) {
        yield thread;
      }
      if (body['has_more'] != true || threads.isEmpty) return;
      final last = threads.last.archivedAt;
      if (last == null) return;
      before = last.toIso8601String();
    }
  }
}
