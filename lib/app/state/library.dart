import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/discord/api.dart';
import '../../core/discord/models.dart';
import '../../core/discord/permissions.dart';
import '../../core/discord/snowflake.dart';
import '../../core/util/pool.dart';
import 'session.dart';

enum LoadState { idle, loading, ready, failed }

class GuildState {
  GuildState(this.guild);

  Guild guild;
  LoadState state = LoadState.idle;
  String? error;
  List<Channel> channels = const [];
  Map<String, Role> roles = const {};
  final members = <String, GuildMember?>{};

  Iterable<Channel> get exportable => channels.where((c) => !c.isCategory);

  int? nameColor(String userId) {
    final member = members[userId];
    if (member == null) return null;
    Role? best;
    for (final id in member.roleIds) {
      final role = roles[id];
      if (role == null || role.color == 0) continue;
      if (best == null || role.position > best.position) best = role;
    }
    return best?.color;
  }

  String? categoryOf(Channel channel) {
    final parent = channel.parentId;
    if (parent == null) return null;
    for (final c in channels) {
      if (c.id == parent) return c.isCategory ? c.displayName : categoryOf(c);
    }
    return null;
  }
}

List<Channel> orderChannels(List<Channel> channels) {
  int rank(Channel c) => c.isVoice ? 1 : 0;
  int compare(Channel a, Channel b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final p = a.position.compareTo(b.position);
    return p != 0 ? p : compareSnowflakes(a.id, b.id);
  }

  final categories = channels.where((c) => c.isCategory).toList()
    ..sort(
      (a, b) => a.position != b.position
          ? a.position.compareTo(b.position)
          : compareSnowflakes(a.id, b.id),
    );
  final categoryIds = categories.map((c) => c.id).toSet();
  final loose =
      channels
          .where((c) => !c.isCategory && !categoryIds.contains(c.parentId))
          .toList()
        ..sort(compare);
  return [
    ...loose,
    for (final category in categories) ...[
      category,
      ...channels.where((c) => c.parentId == category.id).toList()
        ..sort(compare),
    ],
  ];
}

class _Place {
  const _Place(this.home, this.guildId, this.channel);

  final bool home;
  final String? guildId;
  final Channel? channel;

  bool matches(_Place other) =>
      home == other.home &&
      guildId == other.guildId &&
      channel?.id == other.channel?.id;
}

class Library extends ChangeNotifier {
  Library(this.session) {
    session.addListener(_onSession);
  }

  final Session session;
  String? _accountId;
  LoadState state = LoadState.idle;
  bool refreshing = false;
  String? error;
  bool tokenRejected = false;
  List<GuildState> guilds = [];
  List<Channel> dms = [];
  String? selectedGuildId;
  Channel? selectedChannel;
  bool home = false;
  final selection = <String>{};
  bool selecting = false;
  final _trail = <_Place>[];
  int _trailAt = -1;

  GuildState? get selectedGuild =>
      guilds.where((g) => g.guild.id == selectedGuildId).firstOrNull;

  GuildState? guildOf(Channel channel) =>
      guilds.where((g) => g.guild.id == channel.guildId).firstOrNull;

  void _onSession() {
    final id = session.account?.id;
    if (id == _accountId && session.signedIn) return;
    _accountId = id;
    guilds = [];
    dms = [];
    selectedGuildId = null;
    selectedChannel = null;
    home = false;
    selection.clear();
    selecting = false;
    _trail.clear();
    _trailAt = -1;
    state = LoadState.idle;
    refreshing = false;
    if (session.signedIn) load();
    notifyListeners();
  }

  void _visit() {
    final place = _Place(home, selectedGuildId, selectedChannel);
    if (_trailAt >= 0 && _trail[_trailAt].matches(place)) return;
    _trail
      ..removeRange(_trailAt + 1, _trail.length)
      ..add(place);
    if (_trail.length > 100) _trail.removeAt(0);
    _trailAt = _trail.length - 1;
  }

  bool back() => _revisit(_trailAt - 1);

  bool forward() => _revisit(_trailAt + 1);

  bool _revisit(int index) {
    if (index < 0 || index >= _trail.length) return false;
    _trailAt = index;
    final place = _trail[index];
    if (place.guildId != selectedGuildId) {
      selection.clear();
      selecting = false;
    }
    home = place.home;
    selectedGuildId = place.guildId;
    selectedChannel = place.channel;
    notifyListeners();
    final guild = selectedGuild;
    if (guild != null &&
        (guild.state == LoadState.idle || guild.state == LoadState.failed)) {
      unawaited(_loadGuild(guild));
    }
    return true;
  }

  void goHome() {
    if (session.isBot) {
      home = true;
    } else {
      selectedChannel = null;
    }
    _visit();
    notifyListeners();
  }

  Future<void> load() async {
    final api = session.api;
    if (api == null) return;
    state = LoadState.loading;
    error = null;
    tokenRejected = false;
    notifyListeners();
    try {
      if (session.isBot) {
        guilds = (await api.guilds()).map(GuildState.new).toList();
        state = LoadState.ready;
        notifyListeners();
        if (guilds.isNotEmpty) await selectGuild(guilds.first.guild.id);
      } else {
        dms = await _conversations(api);
        state = LoadState.ready;
        _visit();
      }
    } on InvalidTokenException catch (e) {
      tokenRejected = true;
      state = LoadState.failed;
      error = e.message;
    } on DiscordException catch (e) {
      state = LoadState.failed;
      error = e.message;
    }
    notifyListeners();
  }

  Future<List<Channel>> _conversations(DiscordApi api) async =>
      (await api.privateChannels()).where((c) => c.isPrivate).toList()..sort(
        (a, b) =>
            compareSnowflakes(b.lastMessageId ?? b.id, a.lastMessageId ?? a.id),
      );

  Future<String?> refresh() async {
    final api = session.api;
    if (api == null || refreshing || state == LoadState.loading) return null;
    if (state != LoadState.ready) {
      await load();
      return null;
    }
    final account = _accountId;
    refreshing = true;
    notifyListeners();
    String? problem;
    try {
      if (session.isBot) {
        final fresh = await api.guilds();
        if (account != _accountId) return null;
        final known = {for (final g in guilds) g.guild.id: g};
        guilds = [
          for (final guild in fresh)
            (known[guild.id]?..guild = guild) ?? GuildState(guild),
        ];
        final open = selectedGuild;
        if (open != null && open.state == LoadState.ready) {
          await _loadGuild(open, quiet: true);
        }
      } else {
        final fresh = await _conversations(api);
        if (account != _accountId) return null;
        dms = fresh;
      }
      final open = selectedChannel;
      if (open != null && account == _accountId) {
        final list = session.isBot ? selectedGuild?.channels : dms;
        selectedChannel =
            list?.where((c) => c.id == open.id).firstOrNull ?? open;
      }
    } on InvalidTokenException catch (e) {
      tokenRejected = true;
      state = LoadState.failed;
      error = e.message;
    } on DiscordException catch (e) {
      problem = e.message;
    }
    if (account != _accountId) return null;
    refreshing = false;
    notifyListeners();
    return problem;
  }

  Future<void> selectGuild(String id) async {
    selectedGuildId = id;
    selectedChannel = null;
    home = false;
    selection.clear();
    selecting = false;
    _visit();
    notifyListeners();
    final guild = selectedGuild;
    if (guild != null &&
        (guild.state == LoadState.idle || guild.state == LoadState.failed)) {
      await _loadGuild(guild);
    }
  }

  Future<void> _loadGuild(GuildState g, {bool quiet = false}) async {
    final api = session.api;
    final me = session.account;
    if (api == null || me == null) return;
    if (!quiet) {
      g.state = LoadState.loading;
      notifyListeners();
    }
    try {
      final channels = await api.guildChannels(g.guild.id);
      var roles = <String, Role>{};
      try {
        roles = {for (final r in await api.guildRoles(g.guild.id)) r.id: r};
      } on DiscordException {
        roles = {};
      }
      final member = await api.member(g.guild.id, me.id);
      final memberRoles = member?.roleIds ?? const <String>[];
      final base = roles.isEmpty
          ? (g.guild.permissions ?? 0)
          : basePermissions(
              guildId: g.guild.id,
              userId: me.id,
              ownerId: g.guild.ownerId,
              memberRoleIds: memberRoles,
              roles: roles,
            );
      bool readable(Channel c) => canReadHistory(
        channelPermissions(
          base: base,
          guildId: g.guild.id,
          userId: me.id,
          memberRoleIds: memberRoles,
          channel: c,
        ),
      );
      final visible = channels
          .where((c) => !c.isCategory && (c.hasMessages || c.isThreadOnly))
          .where(readable)
          .toList();
      final usedCategories = visible.map((c) => c.parentId).toSet();
      g.roles = roles;
      g.channels = orderChannels([
        ...channels.where((c) => c.isCategory && usedCategories.contains(c.id)),
        ...visible,
      ]);
      g.state = LoadState.ready;
    } on DiscordException catch (e) {
      if (quiet) rethrow;
      g.state = LoadState.failed;
      g.error = e.message;
    }
    notifyListeners();
  }

  void selectChannel(Channel? channel) {
    selectedChannel = channel;
    _visit();
    notifyListeners();
  }

  void toggleSelecting() {
    selecting = !selecting;
    if (!selecting) selection.clear();
    notifyListeners();
  }

  void toggleSelected(Channel channel) {
    if (!selection.remove(channel.id)) selection.add(channel.id);
    notifyListeners();
  }

  void selectAll(Iterable<Channel> channels) {
    selection
      ..clear()
      ..addAll(channels.map((c) => c.id));
    notifyListeners();
  }

  List<Channel> get selectedChannels {
    final source = session.isBot
        ? (selectedGuild?.exportable ?? const <Channel>[])
        : dms;
    return source.where((c) => selection.contains(c.id)).toList();
  }

  Future<List<Message>> fetchMessages(
    Channel channel, {
    String? before,
    String? after,
    String? around,
  }) async {
    final api = session.api;
    if (api == null) return const [];
    final page = await api.messages(
      channel.id,
      before: before,
      after: after,
      around: around,
      limit: 50,
    );
    page.sort((a, b) => compareSnowflakes(a.id, b.id));
    final guild = guildOf(channel);
    if (guild != null) await _prefetchMembers(guild, page);
    return page;
  }

  Future<List<Message>> fetchPins(Channel channel) async {
    final api = session.api;
    if (api == null) return const [];
    final pins = await api.pins(channel.id);
    final guild = guildOf(channel);
    if (guild != null) await _prefetchMembers(guild, pins);
    return pins;
  }

  Future<SearchResults> search(
    Channel channel,
    String query, {
    int offset = 0,
  }) async {
    final api = session.api;
    if (api == null) return const SearchResults(total: 0, messages: []);
    final results = await api.search(channel, query, offset: offset);
    final guild = guildOf(channel);
    if (guild != null) await _prefetchMembers(guild, results.messages);
    return results;
  }

  Future<void> _prefetchMembers(
    GuildState guild,
    List<Message> messages,
  ) async {
    final api = session.api;
    if (api == null) return;
    for (final m in messages) {
      m.mentionMembers.forEach(
        (id, member) => guild.members.putIfAbsent(id, () => member),
      );
    }
    final missing = {
      for (final m in messages)
        if (m.webhookId == null && !guild.members.containsKey(m.author.id))
          m.author.id,
    };
    final pool = Pool(3);
    await Future.wait(
      missing.map(
        (id) => pool.run(() async {
          try {
            guild.members[id] = await api.member(guild.guild.id, id);
          } on DiscordException {
            guild.members[id] = null;
          }
        }),
      ),
    );
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }
}
