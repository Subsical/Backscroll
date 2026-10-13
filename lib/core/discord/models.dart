import 'cdn.dart';

typedef Json = Map<String, dynamic>;

List<T> _list<T>(Object? value, T Function(Json json) parse) => value is List
    ? value.whereType<Map<String, dynamic>>().map(parse).toList()
    : <T>[];

List<String> _strings(Object? value) =>
    value is List ? value.map((e) => e.toString()).toList() : const [];

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

int _int(Object? value, [int fallback = 0]) => switch (value) {
  int v => v,
  double v => v.round(),
  String v => int.tryParse(v) ?? fallback,
  _ => fallback,
};

int? _intOrNull(Object? value) => value == null ? null : _int(value);

Json? _map(Object? value) => value is Map<String, dynamic> ? value : null;

class DiscordUser {
  DiscordUser({
    required this.id,
    required this.username,
    this.globalName,
    this.discriminator = '0',
    this.avatar,
    this.bot = false,
    this.system = false,
  });

  factory DiscordUser.fromJson(Json json) => DiscordUser(
    id: json['id'].toString(),
    username: json['username'] as String? ?? 'Unknown user',
    globalName: json['global_name'] as String?,
    discriminator: json['discriminator'] as String? ?? '0',
    avatar: json['avatar'] as String?,
    bot: json['bot'] == true,
    system: json['system'] == true,
  );

  final String id;
  final String username;
  final String? globalName;
  final String discriminator;
  final String? avatar;
  final bool bot;
  final bool system;

  String get displayName =>
      (globalName?.trim().isNotEmpty ?? false) ? globalName! : username;

  bool get hasLegacyTag =>
      discriminator.isNotEmpty &&
      discriminator != '0' &&
      discriminator != '0000';

  String get tag => hasLegacyTag ? '$username#$discriminator' : username;

  String avatarUrl({int size = 128}) =>
      userAvatarUrl(id, avatar, discriminator: discriminator, size: size);

  Json toJson() => {
    'id': id,
    'username': username,
    'global_name': globalName,
    'discriminator': discriminator,
    'avatar': avatar,
    'bot': bot,
    'system': system,
  };
}

class GuildMember {
  GuildMember({
    this.user,
    this.nick,
    this.avatar,
    this.roleIds = const [],
    this.joinedAt,
  });

  factory GuildMember.fromJson(Json json) => GuildMember(
    user: _map(json['user']) == null
        ? null
        : DiscordUser.fromJson(_map(json['user'])!),
    nick: json['nick'] as String?,
    avatar: json['avatar'] as String?,
    roleIds: _strings(json['roles']),
    joinedAt: _date(json['joined_at']),
  );

  final DiscordUser? user;
  final String? nick;
  final String? avatar;
  final List<String> roleIds;
  final DateTime? joinedAt;
}

class Role {
  Role({
    required this.id,
    required this.name,
    this.color = 0,
    this.position = 0,
    this.permissions = 0,
    this.icon,
    this.unicodeEmoji,
  });

  factory Role.fromJson(Json json) => Role(
    id: json['id'].toString(),
    name: json['name'] as String? ?? '',
    color:
        _intOrNull(_map(json['colors'])?['primary_color']) ??
        _int(json['color']),
    position: _int(json['position']),
    permissions: _int(json['permissions']),
    icon: json['icon'] as String?,
    unicodeEmoji: json['unicode_emoji'] as String?,
  );

  final String id;
  final String name;
  final int color;
  final int position;
  final int permissions;
  final String? icon;
  final String? unicodeEmoji;
}

class Guild {
  Guild({
    required this.id,
    required this.name,
    this.icon,
    this.ownerId,
    this.owner = false,
    this.permissions,
    Json? raw,
  }) : raw = raw ?? {'id': id, 'name': name, 'icon': icon};

  factory Guild.fromJson(Json json) => Guild(
    id: json['id'].toString(),
    name: json['name'] as String? ?? 'Unknown server',
    icon: json['icon'] as String?,
    ownerId: json['owner_id']?.toString(),
    owner: json['owner'] == true,
    permissions: _intOrNull(json['permissions']),
    raw: json,
  );

  final String id;
  final String name;
  final String? icon;
  final String? ownerId;
  final bool owner;
  final int? permissions;
  final Json raw;

  String? iconUrl({int size = 128}) =>
      icon == null ? null : guildIconUrl(id, icon!, size: size);
}

abstract final class ChannelType {
  static const guildText = 0;
  static const dm = 1;
  static const guildVoice = 2;
  static const groupDm = 3;
  static const guildCategory = 4;
  static const guildAnnouncement = 5;
  static const announcementThread = 10;
  static const publicThread = 11;
  static const privateThread = 12;
  static const guildStageVoice = 13;
  static const guildDirectory = 14;
  static const guildForum = 15;
  static const guildMedia = 16;
}

class PermissionOverwrite {
  PermissionOverwrite(this.id, this.type, this.allow, this.deny);

  factory PermissionOverwrite.fromJson(Json json) => PermissionOverwrite(
    json['id'].toString(),
    _int(json['type']),
    _int(json['allow']),
    _int(json['deny']),
  );

  final String id;
  final int type;
  final int allow;
  final int deny;
}

class Channel {
  Channel({
    required this.id,
    required this.type,
    this.guildId,
    this.name,
    this.topic,
    this.parentId,
    this.position = 0,
    this.lastMessageId,
    this.recipients = const [],
    this.icon,
    this.ownerId,
    this.nsfw = false,
    this.overwrites = const [],
    this.archived = false,
    this.archivedAt,
    this.messageCount,
    Json? raw,
  }) : raw = raw ?? {'id': id, 'type': type, 'name': name};

  factory Channel.fromJson(Json json) {
    final meta = _map(json['thread_metadata']);
    return Channel(
      id: json['id'].toString(),
      type: _int(json['type']),
      guildId: json['guild_id']?.toString(),
      name: json['name'] as String?,
      topic: json['topic'] as String?,
      parentId: json['parent_id']?.toString(),
      position: _int(json['position']),
      lastMessageId: json['last_message_id']?.toString(),
      recipients: _list(json['recipients'], DiscordUser.fromJson),
      icon: json['icon'] as String?,
      ownerId: json['owner_id']?.toString(),
      nsfw: json['nsfw'] == true,
      overwrites: _list(
        json['permission_overwrites'],
        PermissionOverwrite.fromJson,
      ),
      archived: meta?['archived'] == true,
      archivedAt: _date(meta?['archive_timestamp']),
      messageCount: _intOrNull(json['message_count']),
      raw: json,
    );
  }

  final String id;
  final int type;
  final String? guildId;
  final String? name;
  final String? topic;
  final String? parentId;
  final int position;
  final String? lastMessageId;
  final List<DiscordUser> recipients;
  final String? icon;
  final String? ownerId;
  final bool nsfw;
  final List<PermissionOverwrite> overwrites;
  final bool archived;
  final DateTime? archivedAt;
  final int? messageCount;
  final Json raw;

  bool get isDm => type == ChannelType.dm;
  bool get isGroupDm => type == ChannelType.groupDm;
  bool get isPrivate => isDm || isGroupDm;
  bool get isCategory => type == ChannelType.guildCategory;
  bool get isThread =>
      type == ChannelType.announcementThread ||
      type == ChannelType.publicThread ||
      type == ChannelType.privateThread;
  bool get isThreadOnly =>
      type == ChannelType.guildForum || type == ChannelType.guildMedia;
  bool get isVoice =>
      type == ChannelType.guildVoice || type == ChannelType.guildStageVoice;
  bool get canHaveThreads =>
      type == ChannelType.guildText ||
      type == ChannelType.guildAnnouncement ||
      isThreadOnly;
  bool get hasMessages =>
      !isCategory && !isThreadOnly && type != ChannelType.guildDirectory;

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (recipients.isNotEmpty) {
      return recipients.map((u) => u.displayName).join(', ');
    }
    return isPrivate ? 'Unnamed group' : id;
  }

  String? iconUrl({int size = 128}) {
    if (isDm && recipients.isNotEmpty) {
      return recipients.first.avatarUrl(size: size);
    }
    if (icon != null) return channelIconUrl(id, icon!, size: size);
    return null;
  }
}

class Attachment {
  Attachment({
    required this.id,
    required this.filename,
    required this.url,
    this.proxyUrl,
    this.title,
    this.description,
    this.contentType,
    this.size = 0,
    this.width,
    this.height,
    this.durationSecs,
    this.waveform,
    this.flags = 0,
  });

  factory Attachment.fromJson(Json json) => Attachment(
    id: json['id'].toString(),
    filename: json['filename'] as String? ?? 'file',
    url: json['url'] as String? ?? '',
    proxyUrl: json['proxy_url'] as String?,
    title: json['title'] as String?,
    description: json['description'] as String?,
    contentType: json['content_type'] as String?,
    size: _int(json['size']),
    width: _intOrNull(json['width']),
    height: _intOrNull(json['height']),
    durationSecs: (json['duration_secs'] as num?)?.toDouble(),
    waveform: json['waveform'] as String?,
    flags: _int(json['flags']),
  );

  static const _imageExts = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'gifv',
    'webp',
    'bmp',
    'avif',
    'heic',
    'svg',
  };
  static const _videoExts = {'mp4', 'webm', 'mov', 'mkv', 'm4v', 'avi'};
  static const _audioExts = {'mp3', 'ogg', 'wav', 'flac', 'm4a', 'opus', 'aac'};

  final String id;
  final String filename;
  final String url;
  final String? proxyUrl;
  final String? title;
  final String? description;
  final String? contentType;
  final int size;
  final int? width;
  final int? height;
  final double? durationSecs;
  final String? waveform;
  final int flags;

  String get extension {
    final dot = filename.lastIndexOf('.');
    return dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  }

  bool get isSpoiler => filename.startsWith('SPOILER_') || flags & 8 != 0;
  bool get isImage =>
      (contentType?.startsWith('image/') ?? false) ||
      _imageExts.contains(extension);
  bool get isVideo =>
      (contentType?.startsWith('video/') ?? false) ||
      _videoExts.contains(extension);
  bool get isAudio =>
      (contentType?.startsWith('audio/') ?? false) ||
      _audioExts.contains(extension);
  bool get isVoiceMessage => waveform != null && durationSecs != null;
  String get displayName => filename.startsWith('SPOILER_')
      ? filename.substring('SPOILER_'.length)
      : filename;
}

class EmbedMedia {
  EmbedMedia({required this.url, this.proxyUrl, this.width, this.height});

  static EmbedMedia? fromJson(Json? json) {
    final url = json?['url'] as String?;
    if (json == null || url == null) return null;
    return EmbedMedia(
      url: url,
      proxyUrl: json['proxy_url'] as String?,
      width: _intOrNull(json['width']),
      height: _intOrNull(json['height']),
    );
  }

  final String url;
  final String? proxyUrl;
  final int? width;
  final int? height;

  String get bestUrl => proxyUrl ?? url;
}

class EmbedField {
  EmbedField(this.name, this.value, this.inline);

  factory EmbedField.fromJson(Json json) => EmbedField(
    json['name'] as String? ?? '',
    json['value'] as String? ?? '',
    json['inline'] == true,
  );

  final String name;
  final String value;
  final bool inline;
}

class EmbedAuthor {
  EmbedAuthor({required this.name, this.url, this.iconUrl});

  final String name;
  final String? url;
  final String? iconUrl;
}

class EmbedFooter {
  EmbedFooter({required this.text, this.iconUrl});

  final String text;
  final String? iconUrl;
}

class Embed {
  Embed({
    this.type = 'rich',
    this.title,
    this.description,
    this.url,
    this.timestamp,
    this.color,
    this.author,
    this.footer,
    this.image,
    this.thumbnail,
    this.video,
    this.providerName,
    this.fields = const [],
    this.images = const [],
    this.components = const [],
  });

  factory Embed.fromJson(Json json) {
    final author = _map(json['author']);
    final footer = _map(json['footer']);
    final image = EmbedMedia.fromJson(_map(json['image']));
    return Embed(
      type: json['type'] as String? ?? 'rich',
      title: json['title'] as String?,
      description: json['description'] as String?,
      url: json['url'] as String?,
      timestamp: _date(json['timestamp']),
      color: _intOrNull(json['color']),
      author: author?['name'] == null
          ? null
          : EmbedAuthor(
              name: author!['name'] as String,
              url: author['url'] as String?,
              iconUrl:
                  (author['proxy_icon_url'] ?? author['icon_url']) as String?,
            ),
      footer: footer?['text'] == null
          ? null
          : EmbedFooter(
              text: footer!['text'] as String,
              iconUrl:
                  (footer['proxy_icon_url'] ?? footer['icon_url']) as String?,
            ),
      image: image,
      thumbnail: EmbedMedia.fromJson(_map(json['thumbnail'])),
      video: EmbedMedia.fromJson(_map(json['video'])),
      providerName: _map(json['provider'])?['name'] as String?,
      fields: _list(json['fields'], EmbedField.fromJson),
      images: image == null ? const [] : [image],
      components: parseComponents(json['components']),
    );
  }

  final String type;
  final String? title;
  final String? description;
  final String? url;
  final DateTime? timestamp;
  final int? color;
  final EmbedAuthor? author;
  final EmbedFooter? footer;
  final EmbedMedia? image;
  final EmbedMedia? thumbnail;
  final EmbedMedia? video;
  final String? providerName;
  final List<EmbedField> fields;
  final List<EmbedMedia> images;
  final List<Component> components;

  bool get isPlainImage =>
      type == 'image' &&
      thumbnail != null &&
      title == null &&
      description == null;
  bool get isGifv => type == 'gifv' && video != null;

  Embed withImages(List<EmbedMedia> all) => Embed(
    type: type,
    title: title,
    description: description,
    url: url,
    timestamp: timestamp,
    color: color,
    author: author,
    footer: footer,
    image: image,
    thumbnail: thumbnail,
    video: video,
    providerName: providerName,
    fields: fields,
    images: all,
    components: components,
  );
}

// Sites like Twitter send one embed per image, all sharing the url of the
// first one. Discord shows them as a single embed with an image grid.
List<Embed> mergeGalleryEmbeds(List<Embed> embeds) {
  final result = <Embed>[];
  for (final embed in embeds) {
    final last = result.isEmpty ? null : result.last;
    final isExtraImage =
        last != null &&
        embed.url != null &&
        embed.url == last.url &&
        embed.image != null &&
        embed.title == null &&
        embed.description == null &&
        embed.fields.isEmpty;
    if (isExtraImage) {
      result[result.length - 1] = last.withImages([
        ...last.images,
        embed.image!,
      ]);
    } else {
      result.add(embed);
    }
  }
  return result;
}

class PartialEmoji {
  PartialEmoji({this.id, required this.name, this.animated = false});

  factory PartialEmoji.fromJson(Json json) => PartialEmoji(
    id: json['id']?.toString(),
    name: json['name'] as String? ?? '',
    animated: json['animated'] == true,
  );

  final String? id;
  final String name;
  final bool animated;

  bool get isCustom => id != null;
  String? get imageUrl =>
      id == null ? null : customEmojiUrl(id!, animated: animated);
}

class Reaction {
  Reaction(this.emoji, this.count, {this.burstCount = 0});

  factory Reaction.fromJson(Json json) => Reaction(
    PartialEmoji.fromJson(_map(json['emoji']) ?? const {}),
    _int(json['count']),
    burstCount: _int(_map(json['count_details'])?['burst']),
  );

  final PartialEmoji emoji;
  final int count;
  final int burstCount;
}

class StickerItem {
  StickerItem(this.id, this.name, this.formatType);

  factory StickerItem.fromJson(Json json) => StickerItem(
    json['id'].toString(),
    json['name'] as String? ?? 'Sticker',
    _int(json['format_type'], 1),
  );

  final String id;
  final String name;
  final int formatType;

  bool get isLottie => formatType == 3;
  String get url => stickerUrl(id, formatType);
}

String _urlExtension(String url) {
  final path = Uri.tryParse(url)?.path ?? '';
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
}

class ComponentMedia {
  ComponentMedia({
    required this.url,
    this.proxyUrl,
    this.contentType,
    this.width,
    this.height,
    this.description,
    this.spoiler = false,
  });

  static ComponentMedia? fromJson(Json json, [String key = 'media']) {
    final media = _map(json[key]);
    final url = media?['url'] as String?;
    if (media == null || url == null) return null;
    return ComponentMedia(
      url: url,
      proxyUrl: media['proxy_url'] as String?,
      contentType: media['content_type'] as String?,
      width: _intOrNull(media['width']),
      height: _intOrNull(media['height']),
      description: json['description'] as String?,
      spoiler: json['spoiler'] == true,
    );
  }

  final String url;
  final String? proxyUrl;
  final String? contentType;
  final int? width;
  final int? height;
  final String? description;
  final bool spoiler;

  // the proxy only serves pictures and videos, so uploads keep their own link
  String get bestUrl => isDiscordAttachmentUrl(url) ? url : proxyUrl ?? url;

  String get fileName {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    return segments.isEmpty || segments.last.isEmpty ? 'file' : segments.last;
  }

  bool get isVideo =>
      (contentType?.startsWith('video/') ?? false) ||
      Attachment._videoExts.contains(_urlExtension(url));
  bool get isAudio =>
      (contentType?.startsWith('audio/') ?? false) ||
      Attachment._audioExts.contains(_urlExtension(url));
}

sealed class Component {
  const Component();
}

class RowComponent extends Component {
  const RowComponent(this.components);
  final List<Component> components;
}

enum ButtonKind { primary, secondary, success, danger, link }

class ButtonComponent extends Component {
  const ButtonComponent({
    required this.kind,
    this.label,
    this.emoji,
    this.url,
    this.disabled = false,
  });

  final ButtonKind kind;
  final String? label;
  final PartialEmoji? emoji;
  final String? url;
  final bool disabled;
}

class SelectOption {
  const SelectOption(this.label, this.description, this.selected);

  final String label;
  final String? description;
  final bool selected;
}

class SelectComponent extends Component {
  const SelectComponent({
    this.placeholder,
    this.options = const [],
    this.disabled = false,
  });

  final String? placeholder;
  final List<SelectOption> options;
  final bool disabled;

  String get text {
    final chosen = options.where((o) => o.selected).map((o) => o.label);
    return chosen.isEmpty
        ? placeholder ?? 'Make a selection'
        : chosen.join(', ');
  }
}

class SectionComponent extends Component {
  const SectionComponent(this.components, this.accessory);
  final List<Component> components;
  final Component? accessory;
}

class TextComponent extends Component {
  const TextComponent(this.content);
  final String content;
}

class ThumbnailComponent extends Component {
  const ThumbnailComponent(this.media);
  final ComponentMedia media;
}

class GalleryComponent extends Component {
  const GalleryComponent(this.items);
  final List<ComponentMedia> items;
}

class FileComponent extends Component {
  const FileComponent(this.media, {required this.name, this.size = 0});
  final ComponentMedia media;
  final String name;
  final int size;
}

class SeparatorComponent extends Component {
  const SeparatorComponent({this.divider = true, this.large = false});
  final bool divider;
  final bool large;
}

class ContainerComponent extends Component {
  const ContainerComponent(
    this.components, {
    this.accentColor,
    this.spoiler = false,
  });

  final List<Component> components;
  final int? accentColor;
  final bool spoiler;
}

Component? _component(Json json) {
  final emoji = _map(json['emoji']);
  final accessory = _map(json['accessory']);
  final media = ComponentMedia.fromJson(json);
  final file = ComponentMedia.fromJson(json, 'file');
  final children = parseComponents(json['components']);
  return switch (_int(json['type'])) {
    1 when children.isNotEmpty => RowComponent(children),
    2 when json['label'] != null || emoji != null => ButtonComponent(
      kind: switch (_int(json['style'])) {
        1 => ButtonKind.primary,
        3 => ButtonKind.success,
        4 => ButtonKind.danger,
        5 => ButtonKind.link,
        _ => ButtonKind.secondary,
      },
      label: json['label'] as String?,
      emoji: emoji == null ? null : PartialEmoji.fromJson(emoji),
      url: json['url'] as String?,
      disabled: json['disabled'] == true,
    ),
    3 || 5 || 6 || 7 || 8 => SelectComponent(
      placeholder: json['placeholder'] as String?,
      options: _list(
        json['options'],
        (o) => SelectOption(
          o['label'] as String? ?? '',
          o['description'] as String?,
          o['default'] == true,
        ),
      ),
      disabled: json['disabled'] == true,
    ),
    9 => SectionComponent(
      children,
      accessory == null ? null : _component(accessory),
    ),
    10 => TextComponent(json['content'] as String? ?? ''),
    11 when media != null => ThumbnailComponent(media),
    12 => GalleryComponent([
      for (final item in (json['items'] as List?) ?? const [])
        if (item is Map<String, dynamic>) ?ComponentMedia.fromJson(item),
    ]),
    13 when file != null => FileComponent(
      file,
      name: json['name'] as String? ?? file.fileName,
      size: _int(json['size']),
    ),
    14 => SeparatorComponent(
      divider: json['divider'] != false,
      large: _int(json['spacing'], 1) == 2,
    ),
    17 => ContainerComponent(
      children,
      accentColor: _intOrNull(json['accent_color']),
      spoiler: json['spoiler'] == true,
    ),
    _ => null,
  };
}

List<Component> parseComponents(Object? value) => [
  for (final item in value is List ? value : const [])
    if (item is Map<String, dynamic>) ?_component(item),
];

void visitComponents(
  List<Component> components,
  void Function(Component component) visit,
) {
  for (final component in components) {
    visit(component);
    switch (component) {
      case RowComponent(:final components) ||
          ContainerComponent(:final components):
        visitComponents(components, visit);
      case SectionComponent(:final components, :final accessory):
        visitComponents([...components, ?accessory], visit);
      default:
        break;
    }
  }
}

class MessageReference {
  MessageReference({
    this.type = 0,
    this.messageId,
    this.channelId,
    this.guildId,
  });

  factory MessageReference.fromJson(Json json) => MessageReference(
    type: _int(json['type']),
    messageId: json['message_id']?.toString(),
    channelId: json['channel_id']?.toString(),
    guildId: json['guild_id']?.toString(),
  );

  final int type;
  final String? messageId;
  final String? channelId;
  final String? guildId;

  bool get isForward => type == 1;
}

class InteractionInfo {
  InteractionInfo({required this.user, this.name, this.type = 2});

  final DiscordUser user;
  final String? name;
  final int type;
}

class PollAnswer {
  PollAnswer(this.id, this.text, this.emoji, this.votes);

  final int id;
  final String text;
  final PartialEmoji? emoji;
  final int votes;
}

class Poll {
  Poll({
    required this.question,
    required this.answers,
    this.expiry,
    this.multiselect = false,
    this.finalized = false,
  });

  factory Poll.fromJson(Json json) {
    final counts = <int, int>{
      for (final c
          in (_map(json['results'])?['answer_counts'] as List?) ?? const [])
        if (c is Map) _int(c['id']): _int(c['count']),
    };
    return Poll(
      question: _map(json['question'])?['text'] as String? ?? '',
      answers: [
        for (final a in (json['answers'] as List?) ?? const [])
          if (a is Map<String, dynamic>)
            PollAnswer(
              _int(a['answer_id']),
              _map(a['poll_media'])?['text'] as String? ?? '',
              _map(_map(a['poll_media'])?['emoji']) == null
                  ? null
                  : PartialEmoji.fromJson(
                      _map(_map(a['poll_media'])!['emoji'])!,
                    ),
              counts[_int(a['answer_id'])] ?? 0,
            ),
      ],
      expiry: _date(json['expiry']),
      multiselect: json['allow_multiselect'] == true,
      finalized: _map(json['results'])?['is_finalized'] == true,
    );
  }

  final String question;
  final List<PollAnswer> answers;
  final DateTime? expiry;
  final bool multiselect;
  final bool finalized;

  int get totalVotes => answers.fold(0, (sum, a) => sum + a.votes);
}

class ForwardedMessage {
  ForwardedMessage({
    required this.content,
    this.timestamp,
    this.attachments = const [],
    this.embeds = const [],
    this.stickers = const [],
    this.components = const [],
    this.mentions = const [],
  });

  factory ForwardedMessage.fromJson(Json json) => ForwardedMessage(
    content: json['content'] as String? ?? '',
    timestamp: _date(json['timestamp']),
    attachments: _list(json['attachments'], Attachment.fromJson),
    embeds: _list(json['embeds'], Embed.fromJson),
    stickers: _list(json['sticker_items'], StickerItem.fromJson),
    components: parseComponents(json['components']),
    mentions: _list(json['mentions'], DiscordUser.fromJson),
  );

  final String content;
  final DateTime? timestamp;
  final List<Attachment> attachments;
  final List<Embed> embeds;
  final List<StickerItem> stickers;
  final List<Component> components;
  final List<DiscordUser> mentions;
}

enum ReferenceState { none, unknown, deleted, present }

abstract final class MessageType {
  static const normal = 0;
  static const recipientAdd = 1;
  static const recipientRemove = 2;
  static const call = 3;
  static const channelNameChange = 4;
  static const channelIconChange = 5;
  static const pinnedMessage = 6;
  static const userJoin = 7;
  static const boost = 8;
  static const boostTier1 = 9;
  static const boostTier2 = 10;
  static const boostTier3 = 11;
  static const followAdd = 12;
  static const threadCreated = 18;
  static const reply = 19;
  static const chatInputCommand = 20;
  static const threadStarter = 21;
  static const contextMenuCommand = 23;
  static const autoModerationAction = 24;
  static const stageStart = 27;
  static const stageEnd = 28;
  static const stageSpeaker = 29;
  static const stageTopic = 31;
  static const pollResult = 46;

  static bool isRegular(int type) =>
      type == normal ||
      type == reply ||
      type == chatInputCommand ||
      type == contextMenuCommand;
}

class Message {
  Message({
    required this.id,
    required this.channelId,
    required this.author,
    required this.timestamp,
    this.type = 0,
    this.content = '',
    this.editedTimestamp,
    this.pinned = false,
    this.mentionEveryone = false,
    this.mentions = const [],
    this.mentionMembers = const {},
    this.mentionRoles = const [],
    this.attachments = const [],
    this.embeds = const [],
    this.reactions = const [],
    this.stickers = const [],
    this.components = const [],
    this.reference,
    this.referenced,
    this.referenceState = ReferenceState.none,
    this.forwards = const [],
    this.webhookId,
    this.applicationId,
    this.interaction,
    this.thread,
    this.poll,
    this.callParticipants = const [],
    this.callEndedAt,
    this.flags = 0,
  });

  factory Message.fromJson(Json json) {
    final mentions = <DiscordUser>[];
    final mentionMembers = <String, GuildMember>{};
    for (final m in (json['mentions'] as List?) ?? const []) {
      if (m is! Map<String, dynamic>) continue;
      final user = DiscordUser.fromJson(m);
      mentions.add(user);
      final member = _map(m['member']);
      if (member != null) {
        mentionMembers[user.id] = GuildMember.fromJson({...member, 'user': m});
      }
    }

    final reference = _map(json['message_reference']);
    final type = _int(json['type']);
    ReferenceState state = ReferenceState.none;
    Message? referenced;
    if (reference != null && (type == MessageType.reply || type == 21)) {
      if (!json.containsKey('referenced_message')) {
        state = ReferenceState.unknown;
      } else if (json['referenced_message'] == null) {
        state = ReferenceState.deleted;
      } else {
        referenced = Message.fromJson(_map(json['referenced_message'])!);
        state = ReferenceState.present;
      }
    }

    final metadata = _map(json['interaction_metadata']);
    final legacy = _map(json['interaction']);
    final interactionUser = _map(metadata?['user']) ?? _map(legacy?['user']);
    final call = _map(json['call']);
    final thread = _map(json['thread']);
    final poll = _map(json['poll']);

    return Message(
      id: json['id'].toString(),
      type: type,
      channelId: json['channel_id']?.toString() ?? '',
      author: DiscordUser.fromJson(
        _map(json['author']) ?? const {'id': '0', 'username': 'Unknown user'},
      ),
      content: json['content'] as String? ?? '',
      timestamp: _date(json['timestamp']) ?? DateTime.utc(2015),
      editedTimestamp: _date(json['edited_timestamp']),
      pinned: json['pinned'] == true,
      mentionEveryone: json['mention_everyone'] == true,
      mentions: mentions,
      mentionMembers: mentionMembers,
      mentionRoles: _strings(json['mention_roles']),
      attachments: _list(json['attachments'], Attachment.fromJson),
      embeds: _list(json['embeds'], Embed.fromJson),
      reactions: _list(json['reactions'], Reaction.fromJson),
      stickers: _list(json['sticker_items'], StickerItem.fromJson),
      components: parseComponents(json['components']),
      reference: reference == null
          ? null
          : MessageReference.fromJson(reference),
      referenced: referenced,
      referenceState: state,
      forwards: [
        for (final s in (json['message_snapshots'] as List?) ?? const [])
          if (s is Map && _map(s['message']) != null)
            ForwardedMessage.fromJson(_map(s['message'])!),
      ],
      webhookId: json['webhook_id']?.toString(),
      applicationId: json['application_id']?.toString(),
      interaction: interactionUser == null
          ? null
          : InteractionInfo(
              user: DiscordUser.fromJson(interactionUser),
              name: (metadata?['name'] ?? legacy?['name']) as String?,
              type: _int(metadata?['type'] ?? legacy?['type'], 2),
            ),
      thread: thread == null ? null : Channel.fromJson(thread),
      poll: poll == null ? null : Poll.fromJson(poll),
      callParticipants: _strings(call?['participants']),
      callEndedAt: _date(call?['ended_timestamp']),
      flags: _int(json['flags']),
    );
  }

  final String id;
  final int type;
  final String channelId;
  final DiscordUser author;
  final String content;
  final DateTime timestamp;
  final DateTime? editedTimestamp;
  final bool pinned;
  final bool mentionEveryone;
  final List<DiscordUser> mentions;
  final Map<String, GuildMember> mentionMembers;
  final List<String> mentionRoles;
  final List<Attachment> attachments;
  final List<Embed> embeds;
  final List<Reaction> reactions;
  final List<StickerItem> stickers;
  final List<Component> components;
  final MessageReference? reference;
  final Message? referenced;
  final ReferenceState referenceState;
  final List<ForwardedMessage> forwards;
  final String? webhookId;
  final String? applicationId;
  final InteractionInfo? interaction;
  final Channel? thread;
  final Poll? poll;
  final List<String> callParticipants;
  final DateTime? callEndedAt;
  final int flags;

  bool get isRegular => MessageType.isRegular(type);
  bool get isReply =>
      type == MessageType.reply && referenceState != ReferenceState.none;
  bool get isForward => reference?.isForward == true && forwards.isNotEmpty;
  bool get isCrosspost => flags & 2 != 0;
}
