const _cdn = 'https://cdn.discordapp.com';

String _ext(String hash) => hash.startsWith('a_') ? 'gif' : 'png';

String userAvatarUrl(
  String userId,
  String? hash, {
  String discriminator = '0',
  int size = 128,
}) {
  if (hash == null) return defaultAvatarUrl(userId, discriminator);
  return '$_cdn/avatars/$userId/$hash.${_ext(hash)}?size=$size';
}

String memberAvatarUrl(
  String guildId,
  String userId,
  String hash, {
  int size = 128,
}) =>
    '$_cdn/guilds/$guildId/users/$userId/avatars/$hash.${_ext(hash)}?size=$size';

// Migrated usernames have discriminator "0" and pick the default avatar from
// the user id instead of the old four digit tag.
String defaultAvatarUrl(String userId, String discriminator) {
  final legacy = int.tryParse(discriminator) ?? 0;
  final index = legacy == 0 ? (int.parse(userId) >> 22) % 6 : legacy % 5;
  return '$_cdn/embed/avatars/$index.png';
}

String guildIconUrl(String guildId, String hash, {int size = 128}) =>
    '$_cdn/icons/$guildId/$hash.${_ext(hash)}?size=$size';

String channelIconUrl(String channelId, String hash, {int size = 128}) =>
    '$_cdn/channel-icons/$channelId/$hash.png?size=$size';

String customEmojiUrl(String id, {bool animated = false, int size = 96}) =>
    '$_cdn/emojis/$id.${animated ? 'gif' : 'png'}?size=$size';

String roleIconUrl(String roleId, String hash, {int size = 64}) =>
    '$_cdn/role-icons/$roleId/$hash.png?size=$size';

String stickerUrl(String id, int formatType) => switch (formatType) {
  3 => '$_cdn/stickers/$id.json',
  4 => 'https://media.discordapp.net/stickers/$id.gif',
  _ => '$_cdn/stickers/$id.png',
};

bool isDiscordAttachmentUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host;
  return (host == 'cdn.discordapp.com' || host == 'media.discordapp.net') &&
      (uri.path.startsWith('/attachments/') ||
          uri.path.startsWith('/ephemeral-attachments/'));
}
