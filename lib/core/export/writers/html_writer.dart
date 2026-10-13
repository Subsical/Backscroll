import 'dart:convert';
import 'dart:math';

import '../../discord/cdn.dart';
import '../../discord/models.dart';
import '../../markdown/ast.dart';
import '../../markdown/emoji.dart';
import '../../markdown/parser.dart';
import '../../markdown/renderers.dart';
import '../../util/html.dart';
import '../dates.dart';
import '../options.dart';
import '../packed.dart';
import 'html_template.dart';
import 'json_writer.dart';
import 'system_text.dart';
import 'writer.dart';

class HtmlWriter extends MessageWriter {
  HtmlWriter(
    super.ctx,
    super.options, {
    required this.assets,
    required this.links,
  });

  final ExportAssets assets;
  final ExportLinks links;
  final _group = <Message>[];
  final _held = <Message>[];
  final _pending = StringBuffer();
  String? _lastDay;
  String? _writtenDay;
  late final _md = HtmlMarkdownRenderer(ctx);
  late final _json = JsonWriter(ctx, options);

  static const _maxGroup = 50;
  static const _blockSize = 64;
  static final _marker = RegExp(r'@@bs-[0-9a-f]+:([A-Za-z0-9_]+)@@');

  String _media(String url) => escapeAttr(ctx.media(url));

  String _color(int? color) =>
      color == null ? '' : ' style="color:${cssColor(color)}"';

  String _href(String fileName) => Uri.encodeComponent(fileName);

  @override
  Map<String, Object?> saveState() => {'lastDay': _writtenDay};

  @override
  void restoreState(Map<String, Object?> state) {
    _lastDay = _writtenDay = state['lastDay'] as String?;
  }

  @override
  void begin(PartInfo part) {
    _lastDay = _writtenDay = null;
    final channel = ctx.channel;
    final guild = ctx.guild;
    final theme = options.format == ExportFormat.htmlLight ? 'light' : 'dark';
    final title = channel.isPrivate
        ? channel.displayName
        : '${guild?.name ?? 'Server'} - ${channel.displayName}';
    final out = StringBuffer()
      ..write(
        '<!DOCTYPE html>\n<html lang="en" data-theme="$theme">\n<head>\n'
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        '<meta name="generator" content="Backscroll">\n'
        '<title>${escapeHtml(title)}</title>\n'
        '<script>$headScript</script>\n'
        '<style>${fontFaces(assets.fontRegular, assets.fontItalic)}$css</style>\n'
        '</head>\n<body>\n',
      )
      ..write(_topbar(part))
      ..write('<!--bs-head:${packData(jsonEncode(_json.header(part)))}-->\n')
      ..write('<main class="chat">\n')
      ..write(_intro(part));
    sink.write(out.toString());
  }

  String get _channelIcon {
    final channel = ctx.channel;
    if (channel.isPrivate) return 'at';
    if (channel.isThread) return 'thread';
    return 'hash';
  }

  String _topbar(PartInfo part) {
    final channel = ctx.channel;
    final topic = channel.topic;
    final out =
        StringBuffer('<header class="topbar"><div class="topbar-title">')
          ..write(icon(_channelIcon))
          ..write(
            '<span class="name-text">${escapeHtml(channel.displayName)}</span>',
          );
    if (topic != null && topic.trim().isNotEmpty) {
      out.write(
        '<span class="topic">'
        '${_md.render(singleLineNodes(parseMarkdown(topic, blocks: false)))}'
        '</span>',
      );
    }
    out.write('</div><nav class="topbar-actions">');
    if (part.previousFileName != null) {
      out.write(
        '<a href="${_href(part.previousFileName!)}">'
        '${icon('chevron-left')}Part ${part.index - 1}</a>',
      );
    }
    out.write(
      '<button id="find-toggle" type="button" title="Search this file">'
      '${icon('search')}</button>',
    );
    if (!options.pinnedOnly) {
      out.write(
        '<button id="pins-toggle" type="button" title="Pinned messages" '
        'aria-expanded="false" hidden>${icon('pin')}<span class="count">'
        '</span></button>',
      );
    }
    out.write(
      '<button id="theme-toggle" type="button" title="Switch theme">'
      '${icon('sun', cls: 'show-dark')}${icon('moon', cls: 'show-light')}'
      '</button></nav>',
    );
    if (!options.pinnedOnly) {
      out.write(
        '<div id="pins-panel" class="pins-panel" hidden>'
        '<div class="pins-head">Pinned messages</div>'
        '<div class="pins-list"></div></div>',
      );
    }
    out.write(
      '</header>\n<div id="find-bar" class="find-bar" hidden>'
      '<input id="find-input" type="search" placeholder="Search this file" '
      'aria-label="Search this file" autocomplete="off">'
      '<span id="find-count" class="find-count"></span>'
      '<button id="find-prev" type="button" title="Previous match">'
      '${icon('chevron-up')}</button>'
      '<button id="find-next" type="button" title="Next match">'
      '${icon('chevron-down')}</button>'
      '<button id="find-close" type="button" title="Close search">'
      '${icon('close')}</button></div>\n',
    );
    return out.toString();
  }

  String _intro(PartInfo part) {
    final channel = ctx.channel;
    final guild = ctx.guild;
    final name = escapeHtml(channel.displayName);
    final iconUrl = ctx.iconUrl;
    final out = StringBuffer('<div class="intro"><div class="intro-icon">');
    out.write(
      iconUrl == null
          ? icon(_channelIcon)
          : '<img src="${_media(iconUrl)}" alt="">',
    );
    out.write('</div>');
    if (channel.isDm) {
      out.write(
        '<h1>$name</h1><p>This is the beginning of your direct '
        'message history with <strong>$name</strong>.</p>',
      );
    } else if (channel.isGroupDm) {
      out.write(
        '<h1>$name</h1><p>Welcome to the beginning of the '
        '<strong>$name</strong> group.</p>',
      );
    } else if (channel.isThread) {
      final parent = ctx.parent?.displayName;
      out.write(
        '<h1>$name</h1><p>${parent == null ? 'A thread' : 'A thread in '
                  '<strong>#${escapeHtml(parent)}</strong>'}.</p>',
      );
    } else {
      out.write(
        '<h1>Welcome to #$name!</h1><p>This is the start of the '
        '#$name channel.</p>',
      );
    }
    final meta = <String>[
      if (!channel.isPrivate && guild != null)
        escapeHtml([guild.name, ?ctx.categoryName].join(' / ')),
      if (options.pinnedOnly) 'Pinned messages only',
      if (options.after != null || options.before != null)
        'Messages ${options.after == null ? 'from the start' : 'after ${escapeHtml(ctx.dates.short(options.after!))}'}'
            '${options.before == null ? '' : ' and before ${escapeHtml(ctx.dates.short(options.before!))}'}',
      'Exported ${escapeHtml(ctx.dates.short(ctx.dates.now))}',
      if (part.index > 1 || options.partitionSize > 0) 'Part ${part.index}',
    ];
    out.write('<div class="intro-meta">');
    for (final item in meta) {
      out.write('<span>$item</span>');
    }
    out.write('</div></div>\n');
    return out.toString();
  }

  @override
  void add(Message message) {
    if (_group.isNotEmpty && !_continues(_group.last, message)) _flushGroup();
    _group.add(message);
  }

  bool _continues(Message previous, Message next) {
    if (_group.length >= _maxGroup) return false;
    if (!previous.isRegular || !next.isRegular) return false;
    if (next.isReply || next.interaction != null || next.pinned) return false;
    if (previous.author.id != next.author.id) return false;
    if (previous.webhookId != null &&
        previous.author.username != next.author.username) {
      return false;
    }
    if (next.timestamp.difference(previous.timestamp).inMinutes >= 7) {
      return false;
    }
    return ctx.dates.dayKey(previous.timestamp) ==
        ctx.dates.dayKey(next.timestamp);
  }

  void _flushGroup() {
    if (_group.isEmpty) return;
    final first = _group.first;
    final day = ctx.dates.dayKey(first.timestamp);
    final out = StringBuffer();
    if (day != _lastDay) {
      out.write(
        '<div class="divider" role="separator">'
        '${escapeHtml(ctx.dates.day(first.timestamp))}</div>\n',
      );
      _lastDay = day;
    }
    out.write('<div class="group">');
    for (var i = 0; i < _group.length; i++) {
      out.write(_message(_group[i], i == 0));
    }
    out.write('</div>\n');
    _pending.write(out);
    _held.addAll(_group);
    _group.clear();
    if (_held.length >= _blockSize) _flushBlock();
  }

  // the same messages once more as data, for converting the page later
  void _flushBlock() {
    if (_held.isEmpty) return;
    final data = _held.map((m) => jsonEncode(_json.message(m))).join('\n');
    final markers = {
      for (final match in _marker.allMatches(data)) match[1]!: match[0]!,
    };
    sink.write('$_pending<!--bs-data:${packData(data)}-->\n');
    if (markers.isNotEmpty) {
      // uploads are still running, so their links get patched in here
      sink.write(
        '<!--bs-media:\n'
        '${markers.entries.map((e) => '${e.key}=${e.value}\n').join()}-->\n',
      );
    }
    _held.forEach(commit);
    _held.clear();
    _pending.clear();
    _writtenDay = _lastDay;
  }

  String _message(Message m, bool first) {
    final line = systemLine(m, guildName: ctx.guild?.name);
    if (line != null) return _system(m, line);
    final shown = m.type == MessageType.threadStarter && m.referenced != null
        ? m.referenced!
        : m;
    final hasReply = first && (m.isReply || m.interaction != null);
    final out = StringBuffer(
      '<div class="msg${first ? ' first' : ''}'
      '${hasReply ? ' has-reply' : ''}${m.pinned ? ' pinned' : ''}" '
      'id="m-${m.id}">',
    );
    if (first) {
      if (m.isReply) {
        out.write(_reply(m));
      } else if (m.interaction != null) {
        out.write(_interaction(m.interaction!));
      }
      out.write(
        '<img class="avatar" src="${_media(ctx.avatarUrl(shown.author))}" '
        'alt="" loading="lazy">',
      );
      out.write(_header(shown, pinned: m.pinned));
    } else {
      out.write(
        '<time class="side" datetime="${m.timestamp.toIso8601String()}" '
        'title="${escapeAttr(ctx.dates.full(m.timestamp))}">'
        '${escapeHtml(ctx.dates.time(m.timestamp))}</time>',
      );
    }
    out
      ..write('<div class="body">')
      ..write(_content(shown))
      ..write(_forwards(shown))
      ..write(_attachments(shown.attachments))
      ..write(_embeds(shown.embeds))
      ..write(_stickers(shown.stickers))
      ..write(_poll(shown.poll))
      ..write(_components(shown.components))
      ..write(_thread(m.thread))
      ..write(_reactions(shown.reactions))
      ..write('</div></div>');
    return out.toString();
  }

  String _nameSpan(DiscordUser user) =>
      '<span class="name"${_color(ctx.nameColor(user.id))} '
      'title="${escapeAttr(user.tag)}">${escapeHtml(ctx.displayName(user))}</span>';

  String _header(Message m, {bool pinned = false}) {
    final author = m.author;
    final badge = author.bot || m.webhookId != null
        ? '<span class="badge">APP</span>'
        : author.system
        ? '<span class="badge">SYSTEM</span>'
        : '';
    return '<h3 class="author">${_nameSpan(author)}$badge'
        '<time datetime="${m.timestamp.toIso8601String()}" '
        'title="${escapeAttr(ctx.dates.full(m.timestamp))}">'
        '${escapeHtml(ctx.dates.short(m.timestamp))}</time>'
        '${pinned ? '<span class="pin-mark" title="Pinned">${icon('pin')}</span>' : ''}'
        '</h3>';
  }

  String _reply(Message m) {
    final ref = m.referenced;
    final out = StringBuffer('<div class="reply"><span class="spine"></span>');
    if (ref == null) {
      out.write(
        '${icon('blocked')}<span class="reply-text"><em>'
        '${m.referenceState == ReferenceState.deleted ? 'Original message was deleted' : 'Original message could not be loaded'}'
        '</em></span></div>',
      );
      return out.toString();
    }
    final pinged = m.mentions.any((u) => u.id == ref.author.id);
    out.write(
      '<img class="reply-avatar" src="${_media(ctx.avatarUrl(ref.author))}" '
      'alt="" loading="lazy">'
      '<span class="reply-name"${_color(ctx.nameColor(ref.author.id))}>'
      '${pinged ? '@' : ''}${escapeHtml(ctx.displayName(ref.author))}</span>',
    );
    final href = links.messageHref(ref.id);
    final preview = _replyPreview(ref);
    out.write(
      href == null
          ? '<span class="reply-text">$preview</span>'
          : '<a class="reply-text" href="${escapeAttr(href)}">$preview</a>',
    );
    out.write('</div>');
    return out.toString();
  }

  String _replyPreview(Message ref) {
    if (ref.content.isNotEmpty) {
      return _md.render(
        singleLineNodes(parseMarkdown(ref.content, blocks: false)),
      );
    }
    if (ref.attachments.isNotEmpty || ref.embeds.isNotEmpty) {
      return '<em>Click to see attachment</em> ${icon('image')}';
    }
    if (ref.stickers.isNotEmpty) return '<em>Sticker</em>';
    return '<em>Click to see message</em>';
  }

  String _interaction(InteractionInfo interaction) {
    final user = interaction.user;
    final command = interaction.name == null
        ? 'a command'
        : '<span class="command">/${escapeHtml(interaction.name!)}</span>';
    return '<div class="reply"><span class="spine"></span>'
        '<img class="reply-avatar" src="${_media(ctx.avatarUrl(user))}" alt="" '
        'loading="lazy"><span class="reply-name"${_color(ctx.nameColor(user.id))}>'
        '${escapeHtml(ctx.displayName(user))}</span>'
        '<span class="reply-text"> used $command</span></div>';
  }

  String _text(String source, {String suffix = ''}) {
    final nodes = parseMarkdown(source);
    return '<div class="content">'
        '${_md.render(nodes, jumbo: isEmojiOnly(nodes))}$suffix</div>';
  }

  String _content(Message m) {
    if (m.content.isEmpty) return '';
    final edited = m.editedTimestamp == null
        ? ''
        : '<span class="edited" title="${escapeAttr(ctx.dates.full(m.editedTimestamp!))}">'
              '(edited)</span>';
    return _text(m.content, suffix: edited);
  }

  (int?, int?) _fit(int? width, int? height, int maxWidth, int maxHeight) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return (null, null);
    }
    final scale = min(1.0, min(maxWidth / width, maxHeight / height));
    return ((width * scale).round(), (height * scale).round());
  }

  String _size(int? width, int? height, int maxWidth, int maxHeight) {
    final (w, h) = _fit(width, height, maxWidth, maxHeight);
    return w == null ? '' : ' width="$w" height="$h"';
  }

  String _mediaBlock(
    String url, {
    required bool video,
    bool spoiler = false,
    String alt = '',
    String size = '',
    String cls = '',
  }) {
    final classes = 'media$cls${spoiler ? ' spoiler-media' : ''}';
    return video
        ? '<div class="$classes"><video src="$url" controls '
              'preload="metadata"$size></video></div>'
        : '<div class="$classes"><a href="$url" target="_blank" '
              'rel="noopener"><img src="$url" alt="$alt"'
              '$size loading="lazy"></a></div>';
  }

  String _fileCard(
    String url,
    String name,
    String detail, {
    bool audio = false,
  }) =>
      '<div class="file">${icon(audio ? 'audio' : 'file')}'
      '<div class="file-info"><a href="$url" target="_blank" rel="noopener">'
      '${escapeHtml(name)}</a>'
      '<span class="file-size">$detail</span></div>'
      '${audio ? '<audio src="$url" controls preload="metadata"></audio>' : ''}'
      '</div>';

  String _attachments(List<Attachment> attachments) {
    if (attachments.isEmpty) return '';
    final out = StringBuffer('<div class="attachments">');
    for (final a in attachments) {
      final url = _media(a.url);
      if (a.isImage || a.isVideo) {
        out.write(
          _mediaBlock(
            url,
            video: !a.isImage,
            spoiler: a.isSpoiler,
            alt: escapeAttr(a.description ?? a.displayName),
            size: _size(a.width, a.height, 550, 350),
          ),
        );
      } else {
        final duration = a.durationSecs == null
            ? ''
            : ' · ${formatDuration(Duration(milliseconds: (a.durationSecs! * 1000).round()))}';
        out.write(
          _fileCard(
            url,
            a.isVoiceMessage ? 'Voice message' : a.displayName,
            '${formatBytes(a.size)}$duration',
            audio: a.isAudio,
          ),
        );
      }
    }
    out.write('</div>');
    return out.toString();
  }

  String _components(List<Component> components) => components.isEmpty
      ? ''
      : '<div class="components">${components.map(_component).join()}</div>';

  String _component(Component component) => switch (component) {
    TextComponent(:final content) => _text(content),
    ContainerComponent(:final components, :final accentColor, :final spoiler) =>
      '<div class="container${accentColor == null ? '' : ' accent'}'
          '${spoiler ? ' spoiler-media' : ''}"'
          '${accentColor == null ? '' : ' style="border-left-color:${cssColor(accentColor)}"'}>'
          '${components.map(_component).join()}</div>',
    SectionComponent(:final components, :final accessory) =>
      '<div class="section"><div class="section-main">'
          '${components.map(_component).join()}</div>'
          '${accessory == null ? '' : _component(accessory)}</div>',
    ThumbnailComponent(:final media) => _mediaBlock(
      _media(media.bestUrl),
      video: false,
      spoiler: media.spoiler,
      alt: escapeAttr(media.description ?? ''),
      cls: ' thumb',
    ),
    GalleryComponent(:final items) => _gallery(items),
    FileComponent(:final media, :final name, :final size) => _fileCard(
      _media(media.bestUrl),
      name,
      formatBytes(size),
      audio: media.isAudio,
    ),
    SeparatorComponent(:final divider, :final large) =>
      '<div class="sep${large ? ' large' : ''}${divider ? '' : ' blank'}" '
          'role="separator"></div>',
    RowComponent(:final components) =>
      '<div class="row">${components.map(_component).join()}</div>',
    ButtonComponent() => _button(component),
    SelectComponent(:final text, :final disabled) =>
      '<div class="select${disabled ? ' disabled' : ''}">'
          '<span>${escapeHtml(text)}</span>${icon('chevron-down')}</div>',
  };

  String _gallery(List<ComponentMedia> items) {
    String block(ComponentMedia item, String size) => _mediaBlock(
      _media(item.bestUrl),
      video: item.isVideo,
      spoiler: item.spoiler,
      alt: escapeAttr(item.description ?? ''),
      size: size,
    );
    if (items.length < 2) {
      return items
          .map((item) => block(item, _size(item.width, item.height, 550, 350)))
          .join();
    }
    final columns = items.length == 2 || items.length == 4 ? '' : ' wide';
    return '<div class="gallery$columns">'
        '${items.map((item) => block(item, '')).join()}</div>';
  }

  String _button(ButtonComponent button) {
    final url = button.url;
    final classes =
        'button ${button.kind.name}${button.disabled ? ' disabled' : ''}';
    final body =
        '${button.emoji == null ? '' : _emojiImage(button.emoji!)}'
        '${button.label == null ? '' : '<span>${escapeHtml(button.label!)}</span>'}';
    return url != null && isSafeLink(url)
        ? '<a class="$classes" href="${escapeAttr(url)}" target="_blank" '
              'rel="noopener noreferrer">$body${icon('external')}</a>'
        : '<span class="$classes">$body</span>';
  }

  String _embeds(List<Embed> embeds) {
    if (embeds.isEmpty) return '';
    final out = StringBuffer('<div class="embeds">');
    for (final embed in mergeGalleryEmbeds(embeds)) {
      if (embed.type == 'poll_result') continue;
      out.write(_embed(embed));
    }
    out.write('</div>');
    return out.toString();
  }

  String _embed(Embed e) {
    if (e.components.isNotEmpty) return e.components.map(_component).join();
    if (e.isGifv) {
      final video = e.video!;
      return '<div class="media"><video src="${_media(video.bestUrl)}" autoplay '
          'loop muted playsinline${_size(video.width, video.height, 400, 300)}>'
          '</video></div>';
    }
    if (e.isPlainImage) {
      final image = e.thumbnail!;
      final link = isSafeLink(e.url ?? '') ? e.url! : image.url;
      return '<div class="media"><a href="${escapeAttr(link)}" target="_blank" '
          'rel="noopener"><img src="${_media(image.bestUrl)}" alt=""'
          '${_size(image.width, image.height, 550, 350)} loading="lazy"></a></div>';
    }
    final border = e.color == null
        ? ''
        : ' style="border-left-color:${cssColor(e.color!)}"';
    final out = StringBuffer(
      '<div class="embed"$border><div class="embed-main">',
    );
    if (e.providerName != null) {
      out.write(
        '<div class="embed-provider">${escapeHtml(e.providerName!)}</div>',
      );
    }
    final author = e.author;
    if (author != null) {
      out.write('<div class="embed-author">');
      if (author.iconUrl != null) {
        out.write(
          '<img src="${_media(author.iconUrl!)}" alt="" loading="lazy">',
        );
      }
      out.write(
        author.url != null && isSafeLink(author.url!)
            ? '<a href="${escapeAttr(author.url!)}" target="_blank" rel="noopener">'
                  '${escapeHtml(author.name)}</a>'
            : '<span>${escapeHtml(author.name)}</span>',
      );
      out.write('</div>');
    }
    if (e.title != null) {
      final title = _md.render(
        singleLineNodes(parseMarkdown(e.title!, blocks: false)),
      );
      out.write('<div class="embed-title">');
      out.write(
        e.url != null && isSafeLink(e.url!)
            ? '<a href="${escapeAttr(e.url!)}" target="_blank" rel="noopener">$title</a>'
            : title,
      );
      out.write('</div>');
    }
    if (e.description != null && e.description!.isNotEmpty) {
      out.write(
        '<div class="embed-desc">'
        '${_md.render(parseMarkdown(e.description!))}</div>',
      );
    }
    if (e.fields.isNotEmpty) out.write(_fields(e.fields));
    final isVideo = e.type == 'video' && e.thumbnail != null;
    if (isVideo) {
      final link = e.url ?? e.video?.url ?? '';
      out.write(
        '<a class="embed-video" href="${escapeAttr(isSafeLink(link) ? link : '#')}" '
        'target="_blank" rel="noopener"><img src="${_media(e.thumbnail!.bestUrl)}" '
        'alt="" loading="lazy"><span class="play"></span></a>',
      );
    } else if (e.images.isNotEmpty) {
      out.write(
        '<div class="embed-images${e.images.length == 1 ? ' single' : ''}">',
      );
      for (final image in e.images) {
        out.write(
          '<a href="${escapeAttr(image.url)}" target="_blank" rel="noopener">'
          '<img src="${_media(image.bestUrl)}" alt="" loading="lazy"></a>',
        );
      }
      out.write('</div>');
    }
    if (e.footer != null || e.timestamp != null) {
      out.write('<div class="embed-footer">');
      if (e.footer?.iconUrl != null) {
        out.write(
          '<img src="${_media(e.footer!.iconUrl!)}" alt="" loading="lazy">',
        );
      }
      final parts = [
        if (e.footer != null) escapeHtml(e.footer!.text),
        if (e.timestamp != null) escapeHtml(ctx.dates.short(e.timestamp!)),
      ];
      out.write('<span>${parts.join(' • ')}</span></div>');
    }
    out.write('</div>');
    if (!isVideo && e.thumbnail != null) {
      out.write(
        '<img class="embed-thumb" src="${_media(e.thumbnail!.bestUrl)}" '
        'alt="" loading="lazy">',
      );
    }
    out.write('</div>');
    return out.toString();
  }

  String _fields(List<EmbedField> fields) {
    final out = StringBuffer('<div class="embed-fields">');
    void write(EmbedField field, int start, int end) {
      out.write(
        '<div class="embed-field" style="grid-column:$start / $end">'
        '<div class="field-name">'
        '${_md.render(parseMarkdown(field.name, blocks: false))}</div>'
        '<div class="field-value">${_md.render(parseMarkdown(field.value))}</div>'
        '</div>',
      );
    }

    var i = 0;
    while (i < fields.length) {
      if (!fields[i].inline) {
        write(fields[i], 1, 13);
        i++;
        continue;
      }
      var j = i;
      while (j < fields.length && fields[j].inline && j - i < 3) {
        j++;
      }
      final span = 12 ~/ (j - i);
      for (var k = i; k < j; k++) {
        write(fields[k], 1 + (k - i) * span, 1 + (k - i + 1) * span);
      }
      i = j;
    }
    out.write('</div>');
    return out.toString();
  }

  String _stickers(List<StickerItem> stickers) {
    if (stickers.isEmpty) return '';
    final out = StringBuffer('<div class="stickers">');
    for (final s in stickers) {
      final name = escapeAttr(s.name);
      out.write(
        s.isLottie
            ? '<div class="sticker lottie" data-src="${_media(s.url)}" title="$name"></div>'
            : '<img class="sticker" src="${_media(s.url)}" alt="$name" title="$name" '
                  'width="160" height="160" loading="lazy">',
      );
    }
    out.write('</div>');
    return out.toString();
  }

  String _emojiImage(PartialEmoji emoji) {
    final url = emoji.isCustom
        ? customEmojiUrl(emoji.id!, animated: emoji.animated)
        : twemojiUrl(emoji.name);
    final alt = emoji.isCustom ? ':${emoji.name}:' : emoji.name;
    return '<img class="emoji" src="${_media(url)}" alt="${escapeAttr(alt)}" '
        'loading="lazy">';
  }

  String _reactions(List<Reaction> reactions) {
    if (reactions.isEmpty) return '';
    final out = StringBuffer('<div class="reactions">');
    for (final r in reactions) {
      final title = r.emoji.isCustom ? ':${r.emoji.name}:' : r.emoji.name;
      out.write(
        '<span class="reaction${r.burstCount > 0 ? ' burst' : ''}" '
        'title="${escapeAttr(title)}">${_emojiImage(r.emoji)}'
        '<span>${r.count}</span></span>',
      );
    }
    out.write('</div>');
    return out.toString();
  }

  String _poll(Poll? poll) {
    if (poll == null) return '';
    final total = poll.totalVotes;
    final out = StringBuffer(
      '<div class="poll"><div class="poll-question">'
      '${escapeHtml(poll.question)}</div>',
    );
    for (final answer in poll.answers) {
      final percent = total == 0 ? 0 : (answer.votes * 100 / total).round();
      out.write(
        '<div class="poll-answer"><div class="poll-bar" '
        'style="width:$percent%"></div><span>',
      );
      if (answer.emoji != null) out.write('${_emojiImage(answer.emoji!)} ');
      out.write(
        '${escapeHtml(answer.text)}</span>'
        '<span>${answer.votes} · $percent%</span></div>',
      );
    }
    final status =
        poll.finalized ||
            (poll.expiry != null && poll.expiry!.isBefore(ctx.dates.now))
        ? 'Poll closed'
        : poll.expiry == null
        ? 'Poll open'
        : 'Ends ${escapeHtml(ctx.dates.short(poll.expiry!))}';
    out.write(
      '<div class="poll-meta">$total vote${total == 1 ? '' : 's'} · '
      '$status</div></div>',
    );
    return out.toString();
  }

  String _thread(Channel? thread) {
    if (thread == null) return '';
    final href = links.threadHref(thread);
    final count = thread.messageCount;
    final body =
        '<span class="thread-name">${escapeHtml(thread.displayName)}</span>'
        '<span class="thread-count">'
        '${count == null ? 'View thread' : '$count message${count == 1 ? '' : 's'}'}'
        '</span>';
    return href == null
        ? '<div class="thread">$body</div>'
        : '<a class="thread" href="${escapeAttr(href)}">$body</a>';
  }

  String _forwards(Message m) {
    if (!m.isForward) return '';
    final out = StringBuffer();
    for (final f in m.forwards) {
      out.write(
        '<div class="forward"><div class="forward-label">'
        '${icon('forward')}Forwarded</div>',
      );
      if (f.content.isNotEmpty) {
        out.write(
          '<div class="content">'
          '${_md.render(parseMarkdown(f.content))}</div>',
        );
      }
      out
        ..write(_attachments(f.attachments))
        ..write(_embeds(f.embeds))
        ..write(_stickers(f.stickers))
        ..write(_components(f.components));
      if (f.timestamp != null) {
        out.write(
          '<div class="forward-meta">'
          '${escapeHtml(ctx.dates.short(f.timestamp!))}</div>',
        );
      }
      out.write('</div>');
    }
    return out.toString();
  }

  String _system(Message m, SystemLine line) {
    final out = StringBuffer(
      '<div class="msg system first" id="m-${m.id}">'
      '${icon(line.icon, cls: 'sys-icon ${line.tone}')}<div class="body">',
    );
    for (final part in line.parts) {
      out.write(switch (part) {
        DiscordUser user => _nameSpan(user),
        Strong(:final text) => '<strong>${escapeHtml(text)}</strong>',
        MessageLink(:final messageId, :final label) => () {
          final href = messageId == null ? null : links.messageHref(messageId);
          return href == null
              ? escapeHtml(label)
              : '<a href="${escapeAttr(href)}">${escapeHtml(label)}</a>';
        }(),
        ThreadLink(:final thread) => () {
          final href = links.threadHref(thread);
          final name = '<strong>${escapeHtml(thread.displayName)}</strong>';
          return href == null
              ? name
              : '<a href="${escapeAttr(href)}">$name</a>';
        }(),
        _ => escapeHtml(part.toString()),
      });
    }
    out.write(
      '<time datetime="${m.timestamp.toIso8601String()}" '
      'title="${escapeAttr(ctx.dates.full(m.timestamp))}">'
      '${escapeHtml(ctx.dates.short(m.timestamp))}</time></div></div>',
    );
    return out.toString();
  }

  @override
  void end(PartInfo part, {String? nextFileName}) {
    _flushGroup();
    _flushBlock();
    final out = StringBuffer();
    if (committedCount == 0) {
      out.write(
        '<p class="empty">No ${options.pinnedOnly ? 'pinned ' : ''}messages'
        '${options.after != null || options.before != null ? ' in this date range' : ''}'
        '.</p>\n',
      );
    }
    out.write(
      '</main>\n<footer class="footer"><span>$committedCount '
      'message${committedCount == 1 ? '' : 's'} in this file</span>'
      '<span>Exported with Backscroll on '
      '${escapeHtml(ctx.dates.full(ctx.dates.now))}</span>',
    );
    if (nextFileName != null) {
      out.write(
        '<a class="next-part" href="${_href(nextFileName)}">Part '
        '${part.index + 1}${icon('chevron-right')}</a>',
      );
    }
    out.write('</footer>\n<script>$bodyScript</script>\n</body>\n</html>\n');
    sink.write(out.toString());
  }
}
