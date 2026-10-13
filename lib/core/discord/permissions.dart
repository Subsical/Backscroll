import 'models.dart';

abstract final class Permission {
  static const administrator = 1 << 3;
  static const viewChannel = 1 << 10;
  static const readMessageHistory = 1 << 16;
  static const manageThreads = 1 << 34;
  static const all = (1 << 62) - 1;
}

int basePermissions({
  required String guildId,
  required String userId,
  required String? ownerId,
  required List<String> memberRoleIds,
  required Map<String, Role> roles,
}) {
  if (ownerId == userId) return Permission.all;
  var perms = roles[guildId]?.permissions ?? 0;
  for (final id in memberRoleIds) {
    perms |= roles[id]?.permissions ?? 0;
  }
  return perms & Permission.administrator != 0 ? Permission.all : perms;
}

int channelPermissions({
  required int base,
  required String guildId,
  required String userId,
  required List<String> memberRoleIds,
  required Channel channel,
}) {
  if (base & Permission.administrator != 0 || base == Permission.all) {
    return Permission.all;
  }
  var perms = base;
  PermissionOverwrite? everyone;
  PermissionOverwrite? member;
  var roleAllow = 0;
  var roleDeny = 0;
  for (final ow in channel.overwrites) {
    if (ow.id == guildId) {
      everyone = ow;
    } else if (ow.type == 1 && ow.id == userId) {
      member = ow;
    } else if (ow.type == 0 && memberRoleIds.contains(ow.id)) {
      roleAllow |= ow.allow;
      roleDeny |= ow.deny;
    }
  }
  if (everyone != null) perms = (perms & ~everyone.deny) | everyone.allow;
  perms = (perms & ~roleDeny) | roleAllow;
  if (member != null) perms = (perms & ~member.deny) | member.allow;
  return perms;
}

bool canReadHistory(int perms) =>
    perms & Permission.viewChannel != 0 &&
    perms & Permission.readMessageHistory != 0;
