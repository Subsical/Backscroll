import 'dart:async';

import '../discord/api.dart';
import '../discord/cdn.dart';
import '../discord/models.dart';
import '../markdown/renderers.dart';
import '../util/pool.dart';
import 'dates.dart';

final _userMentionScan = RegExp(r'<@!?(\d{1,20})>');
final _channelMentionScan = RegExp(r'<#(\d{1,20})>');

List<String> messageTexts(Message m) {
  final texts = <String>[m.content];
  void layout(List<Component> components) {
    visitComponents(components, (component) {
      if (component is TextComponent) texts.add(component.content);
    });
  }

  void embeds(List<Embed> embeds) {
    for (final e in embeds) {
      texts.addAll([?e.title, ?e.description]);
      for (final f in e.fields) {
        texts
          ..add(f.name)
          ..add(f.value);
      }
      layout(e.components);
    }
  }

  embeds(m.embeds);
  layout(m.components);
  for (final f in m.forwards) {
    texts.add(f.content);
    embeds(f.embeds);
    layout(f.components);
  }
  return texts;
}

class ExportContext implements MarkdownResolver {
  ExportContext({
    required this.channel,
    required this.dates,
    this.guild,
    this.api,
    this.parent,
  });

  final Channel channel;
  final Guild? guild;
  final DiscordApi? api;
  final DateFormatter dates;
  final Channel? parent;
  final roles = <String, Role>{};
  final channels = <String, Channel>{};
  final _members = <String, GuildMember?>{};
  final _users = <String, DiscordUser>{};
  final _missingChannels = <String>{};
  String Function(String url) mediaLookup = _identity;

  static String _identity(String url) => url;

  bool get _inGuild => guild != null && !channel.isPrivate;

  String? get categoryName {
    final categoryId = (parent ?? channel).parentId;
    return categoryId == null ? null : channels[categoryId]?.displayName;
  }

  String? get iconUrl =>
      channel.isPrivate ? channel.iconUrl() : guild?.iconUrl();

  Future<void> load() async {
    channels[channel.id] = channel;
    if (parent != null) channels[parent!.id] = parent!;
    final api = this.api;
    if (!_inGuild || api == null) return;
    try {
      for (final role in await api.guildRoles(guild!.id)) {
        roles[role.id] = role;
      }
    } on DiscordException {
      // no roles just means no name colors
    }
    try {
      for (final c in await api.guildChannels(guild!.id)) {
        channels.putIfAbsent(c.id, () => c);
      }
    } on DiscordException {
      return;
    }
  }

  void addMember(String userId, GuildMember? member) {
    _members[userId] = member;
    final user = member?.user;
    if (user != null) _users[user.id] = user;
  }

  void addUser(DiscordUser user) => _users.putIfAbsent(user.id, () => user);

  Future<void> prepare(List<Message> messages) async {
    final wanted = <String>{};
    final channelIds = <String>{};

    void scanText(String? text) {
      if (text == null || text.isEmpty) return;
      for (final m in _userMentionScan.allMatches(text)) {
        wanted.add(m[1]!);
      }
      for (final m in _channelMentionScan.allMatches(text)) {
        channelIds.add(m[1]!);
      }
    }

    void visit(Message m) {
      addUser(m.author);
      if (m.webhookId == null) wanted.add(m.author.id);
      for (final user in m.mentions) {
        addUser(user);
      }
      m.mentionMembers.forEach((id, member) {
        if (!_members.containsKey(id)) addMember(id, member);
      });
      messageTexts(m).forEach(scanText);
      if (m.interaction != null) addUser(m.interaction!.user);
    }

    for (final m in messages) {
      visit(m);
      if (m.referenced != null) visit(m.referenced!);
    }

    final api = this.api;
    if (api == null) return;
    final pool = Pool(4);
    final tasks = <Future<void>>[];
    if (_inGuild) {
      for (final id in wanted) {
        if (_members.containsKey(id)) continue;
        _members[id] = null;
        tasks.add(
          pool.run(() async {
            try {
              addMember(id, await api.member(guild!.id, id));
            } on DiscordException {
              _members[id] = null;
            }
          }),
        );
      }
    }
    for (final id in channelIds) {
      if (channels.containsKey(id) || _missingChannels.contains(id)) continue;
      _missingChannels.add(id);
      tasks.add(
        pool.run(() async {
          try {
            channels[id] = await api.channel(id);
            _missingChannels.remove(id);
          } on DiscordException {
            return;
          }
        }),
      );
    }
    await Future.wait(tasks);
  }

  GuildMember? memberOf(String userId) => _members[userId];

  String displayName(DiscordUser user) {
    final nick = _members[user.id]?.nick;
    return (nick != null && nick.isNotEmpty) ? nick : user.displayName;
  }

  int? nameColor(String userId) {
    final member = _members[userId];
    if (member == null) return null;
    Role? best;
    for (final id in member.roleIds) {
      final role = roles[id];
      if (role == null || role.color == 0) continue;
      if (best == null || role.position > best.position) best = role;
    }
    return best?.color;
  }

  List<Role> memberRoles(String userId) {
    final member = _members[userId];
    if (member == null) return const [];
    return member.roleIds.map((id) => roles[id]).whereType<Role>().toList()
      ..sort((a, b) => b.position.compareTo(a.position));
  }

  String avatarUrl(DiscordUser user, {int size = 128}) {
    final memberAvatar = _members[user.id]?.avatar;
    if (memberAvatar != null && guild != null) {
      return memberAvatarUrl(guild!.id, user.id, memberAvatar, size: size);
    }
    return user.avatarUrl(size: size);
  }

  @override
  String? userName(String id) {
    final user = _users[id];
    final nick = _members[id]?.nick;
    if (nick != null && nick.isNotEmpty) return nick;
    return user?.displayName;
  }

  @override
  RoleInfo? role(String id) {
    final role = roles[id];
    return role == null ? null : RoleInfo(role.name, role.color);
  }

  @override
  String? channelName(String id) => channels[id]?.displayName;

  @override
  String media(String url) => mediaLookup(url);

  @override
  String timestamp(DateTime time, String? style) => dates.styled(time, style);

  @override
  String fullTimestamp(DateTime time) => dates.full(time);
}
