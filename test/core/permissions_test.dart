import 'package:backscroll/core/discord/models.dart';
import 'package:backscroll/core/discord/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const guildId = '100';
  const botId = '200';
  final roles = {
    guildId: Role(
      id: guildId,
      name: '@everyone',
      permissions: Permission.viewChannel | Permission.readMessageHistory,
    ),
    '300': Role(id: '300', name: 'Helpers'),
    '400': Role(
      id: '400',
      name: 'Admin',
      permissions: Permission.administrator,
    ),
  };

  Channel channel(List<PermissionOverwrite> overwrites) =>
      Channel(id: '1', type: ChannelType.guildText, overwrites: overwrites);

  int perms(List<String> memberRoles, Channel c, {String? owner}) {
    final base = basePermissions(
      guildId: guildId,
      userId: botId,
      ownerId: owner,
      memberRoleIds: memberRoles,
      roles: roles,
    );
    return channelPermissions(
      base: base,
      guildId: guildId,
      userId: botId,
      memberRoleIds: memberRoles,
      channel: c,
    );
  }

  test('everyone can read an open channel', () {
    expect(canReadHistory(perms(['300'], channel([]))), isTrue);
  });

  test('a deny on @everyone hides the channel', () {
    final hidden = channel([
      PermissionOverwrite(guildId, 0, 0, Permission.viewChannel),
    ]);
    expect(canReadHistory(perms(['300'], hidden)), isFalse);
  });

  test('a role allow beats the @everyone deny', () {
    final c = channel([
      PermissionOverwrite(guildId, 0, 0, Permission.viewChannel),
      PermissionOverwrite('300', 0, Permission.viewChannel, 0),
    ]);
    expect(canReadHistory(perms(['300'], c)), isTrue);
  });

  test('a member deny beats a role allow', () {
    final c = channel([
      PermissionOverwrite('300', 0, Permission.viewChannel, 0),
      PermissionOverwrite(botId, 1, 0, Permission.viewChannel),
    ]);
    expect(canReadHistory(perms(['300'], c)), isFalse);
  });

  test('administrators and owners see everything', () {
    final hidden = channel([
      PermissionOverwrite(guildId, 0, 0, Permission.viewChannel),
    ]);
    expect(canReadHistory(perms(['400'], hidden)), isTrue);
    expect(canReadHistory(perms([], hidden, owner: botId)), isTrue);
  });
}
