import 'dart:convert';

import '../../discord/api.dart';
import '../../discord/cdn.dart';
import '../../discord/models.dart';
import '../../markdown/emoji.dart';
import '../../markdown/parser.dart';
import '../../markdown/renderers.dart';
import '../../util/html.dart';
import '../context.dart';
import 'system_text.dart';
import 'writer.dart';

const messageTypeNames = {
  0: 'Default',
  1: 'RecipientAdd',
  2: 'RecipientRemove',
  3: 'Call',
  4: 'ChannelNameChange',
  5: 'ChannelIconChange',
  6: 'ChannelPinnedMessage',
  7: 'GuildMemberJoin',
  8: 'GuildBoost',
  9: 'GuildBoostTier1',
  10: 'GuildBoostTier2',
  11: 'GuildBoostTier3',
  12: 'ChannelFollowAdd',
  18: 'ThreadCreated',
  19: 'Reply',
  20: 'ChatInputCommand',
  21: 'ThreadStarterMessage',
  23: 'ContextMenuCommand',
  24: 'AutoModerationAction',
  27: 'StageStart',
  28: 'StageEnd',
  29: 'StageSpeaker',
  31: 'StageTopic',
  46: 'PollResult',
};

String plainSystemText(SystemLine line, String Function(DiscordUser) name) =>
    line.parts
        .map(
          (part) => switch (part) {
            DiscordUser user => name(user),
            Strong(:final text) => text,
            MessageLink(:final label) => label,
            ThreadLink(:final thread) => thread.displayName,
            _ => part.toString(),
          },
        )
        .join();

class JsonWriter extends MessageWriter {
  JsonWriter(super.ctx, super.options);

  late final _text = TextMarkdownRenderer(ctx);

  static final _userIds = RegExp(r'<@!?(\d{1,20})>');
  static final _roleIds = RegExp(r'<@&(\d{1,20})>');
  static final _channelIds = RegExp(r'<#(\d{1,20})>');

  Map<String, Object?> header(PartInfo part) {
    final channel = ctx.channel;
    final guild = ctx.guild;
    final iconUrl = ctx.iconUrl;
    final topic = channel.topic;
    return {
      'exporter': 'Backscroll $appVersion',
      'exportedAt': ctx.dates.now.toUtc().toIso8601String(),
      'guild': guild == null || channel.isPrivate
          ? null
          : {
              'id': guild.id,
              'name': guild.name,
              'iconUrl': iconUrl == null ? null : ctx.media(iconUrl),
            },
      'channel': {
        'id': channel.id,
        'type': channel.type,
        'name': channel.displayName,
        'category': ctx.categoryName,
        'parentId': channel.parentId,
        if (ctx.parent != null) 'parentName': ctx.parent!.displayName,
        'topic': topic,
        if (channel.isPrivate) ...{
          'iconUrl': iconUrl == null ? null : ctx.media(iconUrl),
          'recipients': channel.recipients.map(_user).toList(),
        },
        if (topic != null) ..._mentioned([topic]),
      },
      'dateRange': {
        'after': options.after?.toUtc().toIso8601String(),
        'before': options.before?.toUtc().toIso8601String(),
      },
      if (options.pinnedOnly) 'pinnedOnly': true,
      'part': part.index,
      if (part.previousFileName != null) 'previousPart': part.previousFileName,
    };
  }

  @override
  void begin(PartInfo part) {
    final encoded = const JsonEncoder.withIndent('  ').convert(header(part));
    sink.write(
      '${encoded.substring(0, encoded.lastIndexOf('}')).trimRight()},'
      '\n  "messages": [',
    );
  }

  @override
  void add(Message message) {
    sink.write(committedCount == 0 ? '\n    ' : ',\n    ');
    sink.write(jsonEncode(this.message(message)));
    commit(message);
  }

  // names for the ids in the text, so the file can be rendered again later
  Map<String, Object?> _mentioned(
    List<String> texts, [
    Set<String> listed = const {},
  ]) {
    Set<String> ids(RegExp pattern) => {
      for (final text in texts)
        for (final match in pattern.allMatches(text)) match[1]!,
    };
    final users = [
      for (final id in ids(_userIds))
        if (!listed.contains(id))
          if (ctx.userName(id) case final name?) {'id': id, 'name': name},
    ];
    final roles = [
      for (final id in ids(_roleIds))
        if (ctx.role(id) case final role?)
          {
            'id': id,
            'name': role.name,
            'color': role.color == 0 ? null : cssColor(role.color),
          },
    ];
    final channels = [
      for (final id in ids(_channelIds))
        if (ctx.channelName(id) case final name?) {'id': id, 'name': name},
    ];
    return {
      if (users.isNotEmpty) 'mentionedUsers': users,
      if (roles.isNotEmpty) 'mentionedRoles': roles,
      if (channels.isNotEmpty) 'mentionedChannels': channels,
    };
  }

  @override
  void end(PartInfo part, {String? nextFileName}) {
    sink.write(
      '${committedCount == 0 ? '' : '\n  '}],\n'
      '  "messageCount": $committedCount'
      '${nextFileName == null ? '' : ',\n  "nextPart": ${jsonEncode(nextFileName)}'}'
      '\n}\n',
    );
  }

  Map<String, Object?> _user(DiscordUser user) {
    final color = ctx.nameColor(user.id);
    return {
      'id': user.id,
      'name': user.username,
      'discriminator': user.discriminator,
      'displayName': user.displayName,
      'nickname': ctx.memberOf(user.id)?.nick,
      'color': color == null ? null : cssColor(color),
      'isBot': user.bot,
      if (user.system) 'isSystem': true,
      'roles': [
        for (final role in ctx.memberRoles(user.id))
          {
            'id': role.id,
            'name': role.name,
            'color': role.color == 0 ? null : cssColor(role.color),
            'position': role.position,
          },
      ],
      'avatarUrl': ctx.media(ctx.avatarUrl(user)),
    };
  }

  Map<String, Object?> _emoji(PartialEmoji emoji) => {
    'id': emoji.id,
    'name': emoji.name,
    'isAnimated': emoji.animated,
    'imageUrl': ctx.media(
      emoji.isCustom
          ? customEmojiUrl(emoji.id!, animated: emoji.animated)
          : twemojiUrl(emoji.name),
    ),
  };

  Map<String, Object?> _attachment(Attachment a) => {
    'id': a.id,
    'url': ctx.media(a.url),
    'fileName': a.filename,
    'fileSizeBytes': a.size,
    'contentType': a.contentType,
    'width': a.width,
    'height': a.height,
    'description': a.description,
    'isSpoiler': a.isSpoiler,
    if (a.durationSecs != null) 'durationSeconds': a.durationSecs,
    if (a.isVoiceMessage) 'isVoiceMessage': true,
  };

  Map<String, Object?> _sticker(StickerItem s) => {
    'id': s.id,
    'name': s.name,
    'format': s.formatType,
    'url': ctx.media(s.url),
  };

  Map<String, Object?>? _media(EmbedMedia? media) => media == null
      ? null
      : {
          'url': ctx.media(media.bestUrl),
          'originalUrl': media.url,
          'width': media.width,
          'height': media.height,
        };

  Map<String, Object?> _embed(Embed e) => {
    'type': e.type,
    if (e.providerName != null) 'provider': e.providerName,
    'title': e.title,
    'url': e.url,
    'timestamp': e.timestamp?.toIso8601String(),
    'description': e.description,
    'color': e.color == null ? null : cssColor(e.color!),
    'author': e.author == null
        ? null
        : {
            'name': e.author!.name,
            'url': e.author!.url,
            'iconUrl': e.author!.iconUrl == null
                ? null
                : ctx.media(e.author!.iconUrl!),
          },
    'thumbnail': _media(e.thumbnail),
    'images': e.images.map(_media).toList(),
    'video': _media(e.video),
    'footer': e.footer == null
        ? null
        : {
            'text': e.footer!.text,
            'iconUrl': e.footer!.iconUrl == null
                ? null
                : ctx.media(e.footer!.iconUrl!),
          },
    'fields': [
      for (final f in e.fields)
        {'name': f.name, 'value': f.value, 'isInline': f.inline},
    ],
    if (e.components.isNotEmpty) 'components': _components(e.components),
  };

  Map<String, Object?> _componentMedia(ComponentMedia media) => {
    'url': ctx.media(media.bestUrl),
    'originalUrl': media.url,
    'contentType': media.contentType,
    'width': media.width,
    'height': media.height,
    'description': media.description,
    'isSpoiler': media.spoiler,
  };

  List<Map<String, Object?>> _components(List<Component> components) =>
      components.map(_component).toList();

  Map<String, Object?> _component(Component component) => switch (component) {
    RowComponent(:final components) => {
      'type': 'ActionRow',
      'components': _components(components),
    },
    ButtonComponent(
      :final kind,
      :final label,
      :final emoji,
      :final url,
      :final disabled,
    ) =>
      {
        'type': 'Button',
        'style': kind.name,
        'label': label,
        'emoji': emoji == null ? null : _emoji(emoji),
        'url': url,
        'isDisabled': disabled,
      },
    SelectComponent(:final placeholder, :final options, :final disabled) => {
      'type': 'Select',
      'placeholder': placeholder,
      'options': [
        for (final option in options)
          {
            'label': option.label,
            'description': option.description,
            'isDefault': option.selected,
          },
      ],
      'isDisabled': disabled,
    },
    SectionComponent(:final components, :final accessory) => {
      'type': 'Section',
      'components': _components(components),
      'accessory': accessory == null ? null : _component(accessory),
    },
    TextComponent(:final content) => {
      'type': 'TextDisplay',
      'content': content,
      'text': _text.render(parseMarkdown(content)),
    },
    ThumbnailComponent(:final media) => {
      'type': 'Thumbnail',
      ..._componentMedia(media),
    },
    GalleryComponent(:final items) => {
      'type': 'MediaGallery',
      'items': items.map(_componentMedia).toList(),
    },
    FileComponent(:final media, :final name, :final size) => {
      'type': 'File',
      'url': ctx.media(media.bestUrl),
      'fileName': name,
      'fileSizeBytes': size,
      'contentType': media.contentType,
      'isSpoiler': media.spoiler,
    },
    SeparatorComponent(:final divider, :final large) => {
      'type': 'Separator',
      'hasDivider': divider,
      'spacing': large ? 'large' : 'small',
    },
    ContainerComponent(:final components, :final accentColor, :final spoiler) =>
      {
        'type': 'Container',
        'accentColor': accentColor == null ? null : cssColor(accentColor),
        'isSpoiler': spoiler,
        'components': _components(components),
      },
  };

  Map<String, Object?> message(Message m) {
    final system = systemLine(m, guildName: ctx.guild?.name);
    final ref = m.referenced;
    return {
      'id': m.id,
      'type': messageTypeNames[m.type] ?? 'Unknown${m.type}',
      'timestamp': m.timestamp.toIso8601String(),
      'timestampEdited': m.editedTimestamp?.toIso8601String(),
      'isPinned': m.pinned,
      'content': m.content,
      'text': system != null
          ? plainSystemText(system, ctx.displayName)
          : _text.render(parseMarkdown(m.content)),
      'author': _user(m.author),
      if (m.webhookId != null) 'webhookId': m.webhookId,
      'attachments': m.attachments.map(_attachment).toList(),
      'embeds': m.embeds.map(_embed).toList(),
      'stickers': m.stickers.map(_sticker).toList(),
      'reactions': [
        for (final r in m.reactions)
          {
            'emoji': _emoji(r.emoji),
            'count': r.count,
            if (r.burstCount > 0) 'burstCount': r.burstCount,
          },
      ],
      if (m.components.isNotEmpty) 'components': _components(m.components),
      'mentions': m.mentions.map(_user).toList(),
      'reference': m.reference == null
          ? null
          : {
              'messageId': m.reference!.messageId,
              'channelId': m.reference!.channelId,
              'guildId': m.reference!.guildId,
              'isForward': m.reference!.isForward,
            },
      if (m.referenceState == ReferenceState.deleted) 'referencedMessage': null,
      if (ref != null)
        'referencedMessage': m.type == MessageType.threadStarter
            ? message(ref)
            : {
                'id': ref.id,
                'author': _user(ref.author),
                'content': ref.content,
                'attachments': ref.attachments.length,
                'embeds': ref.embeds.length,
                'stickers': ref.stickers.length,
              },
      ..._mentioned(
        [...messageTexts(m), if (ref != null) ref.content],
        {for (final user in m.mentions) user.id},
      ),
      if (m.callEndedAt != null)
        'callEndedTimestamp': m.callEndedAt!.toIso8601String(),
      if (m.interaction != null)
        'interaction': {
          'name': m.interaction!.name,
          'user': _user(m.interaction!.user),
        },
      if (m.thread != null)
        'thread': {
          'id': m.thread!.id,
          'name': m.thread!.displayName,
          'messageCount': m.thread!.messageCount,
        },
      if (m.poll != null)
        'poll': {
          'question': m.poll!.question,
          'answers': [
            for (final a in m.poll!.answers)
              {
                'id': a.id,
                'text': a.text,
                'emoji': a.emoji == null ? null : _emoji(a.emoji!),
                'votes': a.votes,
              },
          ],
          'expiresAt': m.poll!.expiry?.toIso8601String(),
          'isFinalized': m.poll!.finalized,
        },
      if (m.forwards.isNotEmpty)
        'forwarded': [
          for (final f in m.forwards)
            {
              'content': f.content,
              'timestamp': f.timestamp?.toIso8601String(),
              'attachments': f.attachments.map(_attachment).toList(),
              'embeds': f.embeds.map(_embed).toList(),
              'stickers': f.stickers.map(_sticker).toList(),
              if (f.components.isNotEmpty)
                'components': _components(f.components),
            },
        ],
    };
  }
}
