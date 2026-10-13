import '../discord/models.dart';
import '../discord/snowflake.dart';
import '../export/context.dart';
import '../export/dates.dart';
import '../export/writers/json_writer.dart';
import '../media/media_refs.dart';

typedef Json = Map<String, dynamic>;

final _typeIds = {
  for (final entry in messageTypeNames.entries) entry.value: entry.key,
};

final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');

bool isRelativeUrl(String url) => !_scheme.hasMatch(url);

String encodeRelativeUrl(String url) =>
    url.split('/').map(Uri.encodeComponent).join('/');

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

int? _color(Object? value) => value is String && value.startsWith('#')
    ? int.tryParse(value.substring(1), radix: 16)
    : null;

List<Json> _maps(Object? value) =>
    value is List ? value.whereType<Json>().toList() : const [];

class ReadContext extends ExportContext {
  ReadContext({
    required super.channel,
    required super.dates,
    super.guild,
    super.parent,
    this.icon,
  });

  final String? icon;
  final avatars = <String, String>{};

  @override
  String? get iconUrl => icon;

  @override
  String avatarUrl(DiscordUser user, {int size = 128}) =>
      avatars[user.id] ?? super.avatarUrl(user, size: size);
}

class ExportDecoder {
  ExportDecoder(Json header, {required DateFormatter dates, required this.html})
    : ctx = _context(header, dates, html) {
    final channel = header['channel'] as Json;
    ctx.channel.recipients.addAll(_maps(channel['recipients']).map(_user));
    _names(channel);
  }

  // relative links inside a page are written url-encoded
  final bool html;
  final ReadContext ctx;
  final urls = <String, String>{};
  final _seen = <String, Message>{};

  static const _remembered = 20000;

  static String _plain(String url, bool html) => html && isRelativeUrl(url)
      ? url.split('/').map(Uri.decodeComponent).join('/')
      : url;

  static ReadContext _context(Json header, DateFormatter dates, bool html) {
    final channel = header['channel'] as Json;
    final guild = header['guild'] as Json?;
    final type = channel['type'] as int? ?? 0;
    final parentId = channel['parentId']?.toString();
    final category = channel['category'] as String?;
    final isThread = type >= 10 && type <= 12;
    final icon = (guild?['iconUrl'] ?? channel['iconUrl']) as String?;
    final ctx = ReadContext(
      channel: Channel(
        id: channel['id'].toString(),
        type: type,
        name: channel['name'] as String?,
        topic: channel['topic'] as String?,
        parentId: parentId,
        recipients: [],
      ),
      guild: guild == null
          ? null
          : Guild(
              id: guild['id'].toString(),
              name: guild['name'] as String? ?? 'Server',
            ),
      parent: isThread && parentId != null
          ? Channel(
              id: parentId,
              type: ChannelType.guildText,
              name: channel['parentName'] as String?,
              parentId: 'category',
            )
          : null,
      dates: dates,
      icon: icon == null ? null : _plain(icon, html),
    );
    if (category != null) {
      final id = isThread ? 'category' : parentId ?? 'category';
      ctx.channels[id] = Channel(
        id: id,
        type: ChannelType.guildCategory,
        name: category,
      );
    }
    return ctx;
  }

  String _url(Object? stored) => _plain(stored as String? ?? '', html);

  void _names(Json json) {
    for (final user in _maps(json['mentionedUsers'])) {
      ctx.addUser(
        DiscordUser(
          id: user['id'].toString(),
          username: user['name'] as String? ?? 'Unknown user',
        ),
      );
    }
    for (final role in _maps(json['mentionedRoles'])) {
      final id = role['id'].toString();
      ctx.roles.putIfAbsent(
        id,
        () => Role(
          id: id,
          name: role['name'] as String? ?? '',
          color: _color(role['color']) ?? 0,
        ),
      );
    }
    for (final channel in _maps(json['mentionedChannels'])) {
      final id = channel['id'].toString();
      ctx.channels.putIfAbsent(
        id,
        () => Channel(
          id: id,
          type: ChannelType.guildText,
          name: channel['name'] as String?,
        ),
      );
    }
  }

  DiscordUser _user(Json json) {
    final id = json['id'].toString();
    final name = json['name'] as String? ?? 'Unknown user';
    final shown = json['displayName'] as String?;
    final user = DiscordUser(
      id: id,
      username: name,
      globalName: shown == name ? null : shown,
      discriminator: json['discriminator'] as String? ?? '0',
      bot: json['isBot'] == true,
      system: json['isSystem'] == true,
    );
    final roles = _maps(json['roles']);
    for (final role in roles) {
      ctx.roles[role['id'].toString()] = Role(
        id: role['id'].toString(),
        name: role['name'] as String? ?? '',
        color: _color(role['color']) ?? 0,
        position: role['position'] as int? ?? 0,
      );
    }
    ctx.addMember(
      id,
      GuildMember(
        user: user,
        nick: json['nickname'] as String?,
        roleIds: [for (final role in roles) role['id'].toString()],
      ),
    );
    final avatar = json['avatarUrl'] as String?;
    if (avatar != null) ctx.avatars[id] = _url(avatar);
    return user;
  }

  PartialEmoji _emoji(Json json) {
    final emoji = PartialEmoji(
      id: json['id']?.toString(),
      name: json['name'] as String? ?? '',
      animated: json['isAnimated'] == true,
    );
    final image = json['imageUrl'] as String?;
    if (image != null) urls[emojiImageUrl(emoji)] = _url(image);
    return emoji;
  }

  Attachment _attachment(Json json) => Attachment(
    id: json['id'].toString(),
    filename: json['fileName'] as String? ?? 'file',
    url: _url(json['url']),
    description: json['description'] as String?,
    contentType: json['contentType'] as String?,
    size: json['fileSizeBytes'] as int? ?? 0,
    width: json['width'] as int?,
    height: json['height'] as int?,
    durationSecs: (json['durationSeconds'] as num?)?.toDouble(),
    waveform: json['isVoiceMessage'] == true ? '' : null,
    flags: json['isSpoiler'] == true ? 8 : 0,
  );

  EmbedMedia? _embedMedia(Object? json) => json is Json && json['url'] != null
      ? EmbedMedia(
          url: (json['originalUrl'] ?? json['url']) as String,
          proxyUrl: _url(json['url']),
          width: json['width'] as int?,
          height: json['height'] as int?,
        )
      : null;

  Embed _embed(Json json) {
    final author = json['author'] as Json?;
    final footer = json['footer'] as Json?;
    final images = _maps(json['images']).map(_embedMedia).nonNulls.toList();
    return Embed(
      type: json['type'] as String? ?? 'rich',
      title: json['title'] as String?,
      description: json['description'] as String?,
      url: json['url'] as String?,
      timestamp: _time(json['timestamp']),
      color: _color(json['color']),
      author: author == null
          ? null
          : EmbedAuthor(
              name: author['name'] as String? ?? '',
              url: author['url'] as String?,
              iconUrl: author['iconUrl'] == null
                  ? null
                  : _url(author['iconUrl']),
            ),
      footer: footer == null
          ? null
          : EmbedFooter(
              text: footer['text'] as String? ?? '',
              iconUrl: footer['iconUrl'] == null
                  ? null
                  : _url(footer['iconUrl']),
            ),
      image: images.firstOrNull,
      thumbnail: _embedMedia(json['thumbnail']),
      video: _embedMedia(json['video']),
      providerName: json['provider'] as String?,
      fields: [
        for (final field in _maps(json['fields']))
          EmbedField(
            field['name'] as String? ?? '',
            field['value'] as String? ?? '',
            field['isInline'] == true,
          ),
      ],
      images: images,
      components: _components(json['components']),
    );
  }

  StickerItem _sticker(Json json) {
    final sticker = StickerItem(
      json['id'].toString(),
      json['name'] as String? ?? 'Sticker',
      json['format'] as int? ?? 1,
    );
    final url = json['url'] as String?;
    if (url != null) urls[sticker.url] = _url(url);
    return sticker;
  }

  ComponentMedia _componentMedia(Json json) {
    final stored = _url(json['url']);
    final media = ComponentMedia(
      url: json['originalUrl'] as String? ?? stored,
      proxyUrl: stored,
      contentType: json['contentType'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      description: json['description'] as String?,
      spoiler: json['isSpoiler'] == true,
    );
    urls[media.bestUrl] = stored;
    return media;
  }

  List<Component> _components(Object? value) =>
      _maps(value).map(_component).nonNulls.toList();

  Component? _component(Json json) => switch (json['type']) {
    'ActionRow' => RowComponent(_components(json['components'])),
    'Button' => ButtonComponent(
      kind:
          ButtonKind.values.asNameMap()[json['style']] ?? ButtonKind.secondary,
      label: json['label'] as String?,
      emoji: json['emoji'] is Json ? _emoji(json['emoji'] as Json) : null,
      url: json['url'] as String?,
      disabled: json['isDisabled'] == true,
    ),
    'Select' => SelectComponent(
      placeholder: json['placeholder'] as String?,
      options: [
        for (final option in _maps(json['options']))
          SelectOption(
            option['label'] as String? ?? '',
            option['description'] as String?,
            option['isDefault'] == true,
          ),
      ],
      disabled: json['isDisabled'] == true,
    ),
    'Section' => SectionComponent(
      _components(json['components']),
      json['accessory'] is Json ? _component(json['accessory'] as Json) : null,
    ),
    'TextDisplay' => TextComponent(json['content'] as String? ?? ''),
    'Thumbnail' => ThumbnailComponent(_componentMedia(json)),
    'MediaGallery' => GalleryComponent(
      _maps(json['items']).map(_componentMedia).toList(),
    ),
    'File' => FileComponent(
      _componentMedia(json),
      name: json['fileName'] as String? ?? 'file',
      size: json['fileSizeBytes'] as int? ?? 0,
    ),
    'Separator' => SeparatorComponent(
      divider: json['hasDivider'] != false,
      large: json['spacing'] == 'large',
    ),
    'Container' => ContainerComponent(
      _components(json['components']),
      accentColor: _color(json['accentColor']),
      spoiler: json['isSpoiler'] == true,
    ),
    _ => null,
  };

  // a reply only keeps how much its target had, not the files themselves
  Message _replyTarget(Json json) {
    final id = json['id'].toString();
    return Message(
      id: id,
      channelId: ctx.channel.id,
      author: _user(json['author'] as Json),
      timestamp: snowflakeTime(id),
      content: json['content'] as String? ?? '',
      attachments: List.filled(
        json['attachments'] as int? ?? 0,
        Attachment(id: '', filename: '', url: ''),
      ),
      embeds: List.filled(json['embeds'] as int? ?? 0, Embed()),
      stickers: List.filled(
        json['stickers'] as int? ?? 0,
        StickerItem('', '', 1),
      ),
    );
  }

  Message message(Json json) {
    _names(json);
    final id = json['id'].toString();
    final typeName = json['type'] as String? ?? 'Default';
    final type =
        _typeIds[typeName] ??
        int.tryParse(typeName.replaceFirst('Unknown', '')) ??
        MessageType.normal;
    final reference = json['reference'] as Json?;
    final refers =
        reference != null &&
        (type == MessageType.reply || type == MessageType.threadStarter);
    var state = ReferenceState.none;
    Message? referenced;
    if (refers) {
      final target = json['referencedMessage'];
      if (target is Json) {
        referenced = target['attachments'] is int
            ? _replyTarget(target)
            : message(target);
      } else if (!json.containsKey('referencedMessage')) {
        referenced = _seen[reference['messageId']?.toString()];
      }
      state = referenced != null
          ? ReferenceState.present
          : json.containsKey('referencedMessage')
          ? ReferenceState.deleted
          : ReferenceState.unknown;
    }
    final interaction = json['interaction'] as Json?;
    final thread = json['thread'] as Json?;
    final poll = json['poll'] as Json?;
    final result = Message(
      id: id,
      type: type,
      channelId: ctx.channel.id,
      author: _user(json['author'] as Json),
      content: json['content'] as String? ?? '',
      timestamp: _time(json['timestamp']) ?? snowflakeTime(id),
      editedTimestamp: _time(json['timestampEdited']),
      pinned: json['isPinned'] == true,
      mentions: _maps(json['mentions']).map(_user).toList(),
      attachments: _maps(json['attachments']).map(_attachment).toList(),
      embeds: _maps(json['embeds']).map(_embed).toList(),
      reactions: [
        for (final reaction in _maps(json['reactions']))
          Reaction(
            _emoji(reaction['emoji'] as Json),
            reaction['count'] as int? ?? 0,
            burstCount: reaction['burstCount'] as int? ?? 0,
          ),
      ],
      stickers: _maps(json['stickers']).map(_sticker).toList(),
      components: _components(json['components']),
      reference: reference == null
          ? null
          : MessageReference(
              type: reference['isForward'] == true ? 1 : 0,
              messageId: reference['messageId']?.toString(),
              channelId: reference['channelId']?.toString(),
              guildId: reference['guildId']?.toString(),
            ),
      referenced: referenced,
      referenceState: state,
      forwards: [
        for (final forward in _maps(json['forwarded']))
          ForwardedMessage(
            content: forward['content'] as String? ?? '',
            timestamp: _time(forward['timestamp']),
            attachments: _maps(forward['attachments'])
                .map(_attachment)
                .toList(),
            embeds: _maps(forward['embeds']).map(_embed).toList(),
            stickers: _maps(forward['stickers']).map(_sticker).toList(),
            components: _components(forward['components']),
          ),
      ],
      webhookId: json['webhookId']?.toString(),
      interaction: interaction == null
          ? null
          : InteractionInfo(
              user: _user(interaction['user'] as Json),
              name: interaction['name'] as String?,
            ),
      thread: thread == null
          ? null
          : Channel(
              id: thread['id'].toString(),
              type: ChannelType.publicThread,
              name: thread['name'] as String?,
              messageCount: thread['messageCount'] as int?,
            ),
      poll: poll == null
          ? null
          : Poll(
              question: poll['question'] as String? ?? '',
              answers: [
                for (final answer in _maps(poll['answers']))
                  PollAnswer(
                    answer['id'] as int? ?? 0,
                    answer['text'] as String? ?? '',
                    answer['emoji'] is Json
                        ? _emoji(answer['emoji'] as Json)
                        : null,
                    answer['votes'] as int? ?? 0,
                  ),
              ],
              expiry: _time(poll['expiresAt']),
              finalized: poll['isFinalized'] == true,
            ),
      callEndedAt: _time(json['callEndedTimestamp']),
    );
    _seen[id] = result;
    if (_seen.length > _remembered) _seen.remove(_seen.keys.first);
    return result;
  }
}
