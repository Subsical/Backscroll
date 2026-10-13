import '../../discord/models.dart';
import '../../markdown/parser.dart';
import '../../markdown/renderers.dart';
import 'json_writer.dart' show plainSystemText;
import 'system_text.dart';
import 'writer.dart';

String _rule() => '=' * 62;

String _emojiText(PartialEmoji emoji) =>
    emoji.isCustom ? ':${emoji.name}:' : emoji.name;

// (line, whether it is a link to a file)
List<(String, bool)> _componentLines(
  List<Component> components,
  TextMarkdownRenderer text,
  String Function(String url) media,
) {
  final lines = <(String, bool)>[];
  void walk(List<Component> components) {
    for (final component in components) {
      switch (component) {
        case TextComponent(:final content):
          lines.add((text.render(parseMarkdown(content)), false));
        case ThumbnailComponent(media: final file) ||
            FileComponent(media: final file):
          lines.add((media(file.bestUrl), true));
        case GalleryComponent(:final items):
          for (final item in items) {
            lines.add((media(item.bestUrl), true));
          }
        case ButtonComponent(:final label, :final emoji, :final url):
          final name = [if (emoji != null) _emojiText(emoji), ?label].join(' ');
          lines.add((url == null ? '[$name]' : '[$name]($url)', false));
        case SelectComponent(text: final choice):
          lines.add(('[$choice]', false));
        case RowComponent(:final components):
          final start = lines.length;
          walk(components);
          final row = lines.sublist(start).map((line) => line.$1).join(' ');
          lines
            ..removeRange(start, lines.length)
            ..add((row, false));
        case SectionComponent(:final components, :final accessory):
          walk([...components, ?accessory]);
        case ContainerComponent(:final components):
          walk(components);
        case SeparatorComponent():
          break;
      }
    }
  }

  walk(components);
  return lines.where((line) => line.$1.isNotEmpty).toList();
}

class TextWriter extends MessageWriter {
  TextWriter(super.ctx, super.options);

  late final _text = TextMarkdownRenderer(ctx);

  @override
  void begin(PartInfo part) {
    final channel = ctx.channel;
    final out = StringBuffer()
      ..writeln(_rule())
      ..writeln(
        channel.isPrivate
            ? 'Direct messages: ${channel.displayName}'
            : 'Server: ${ctx.guild?.name ?? 'Unknown'}',
      )
      ..writeln(
        channel.isPrivate
            ? 'Channel id: ${channel.id}'
            : 'Channel: ${[?ctx.categoryName, channel.displayName].join(' / ')}',
      );
    if (channel.topic != null && channel.topic!.trim().isNotEmpty) {
      out.writeln('Topic: ${channel.topic}');
    }
    if (options.after != null) {
      out.writeln('After: ${ctx.dates.full(options.after!)}');
    }
    if (options.before != null) {
      out.writeln('Before: ${ctx.dates.full(options.before!)}');
    }
    if (options.pinnedOnly) out.writeln('Pinned messages only');
    if (part.index > 1) out.writeln('Part: ${part.index}');
    out
      ..writeln(_rule())
      ..writeln();
    sink.write(out.toString());
  }

  @override
  void add(Message m) {
    final out = StringBuffer();
    final author = m.author;
    final name = ctx.displayName(author);
    out.write('[${ctx.dates.short(m.timestamp)}] $name');
    if (name != author.tag) out.write(' (${author.tag})');
    if (m.pinned) out.write(' (pinned)');
    out.writeln();

    final system = systemLine(m, guildName: ctx.guild?.name);
    if (system != null) {
      out.writeln(plainSystemText(system, ctx.displayName));
    } else {
      if (m.isReply && m.referenced != null) {
        final ref = m.referenced!;
        final snippet = _text
            .render(parseMarkdown(ref.content, blocks: false))
            .replaceAll('\n', ' ');
        out.writeln(
          '{Reply to ${ctx.displayName(ref.author)}: '
          '${snippet.length > 80 ? '${snippet.substring(0, 80)}...' : snippet}}',
        );
      }
      if (m.interaction != null) {
        out.writeln(
          '{Used /${m.interaction!.name ?? 'command'} by '
          '${ctx.displayName(m.interaction!.user)}}',
        );
      }
      if (m.content.isNotEmpty) {
        out.write(_text.render(parseMarkdown(m.content)));
        if (m.editedTimestamp != null) out.write(' (edited)');
        out.writeln();
      }
      for (final f in m.forwards) {
        out.writeln('{Forwarded}');
        if (f.content.isNotEmpty) {
          out.writeln(_text.render(parseMarkdown(f.content)));
        }
        _writeAttachments(out, f.attachments);
        _writeComponents(out, f.components);
      }
      _writeAttachments(out, m.attachments);
      for (final e in m.embeds) {
        out.writeln('{Embed}');
        if (e.author != null) out.writeln(e.author!.name);
        if (e.title != null) out.writeln(e.title);
        if (e.url != null) out.writeln(e.url);
        if (e.description != null) {
          out.writeln(_text.render(parseMarkdown(e.description!)));
        }
        for (final f in e.fields) {
          out
            ..writeln(f.name)
            ..writeln(_text.render(parseMarkdown(f.value)));
        }
        for (final image in e.images) {
          out.writeln(ctx.media(image.bestUrl));
        }
        _writeComponents(out, e.components);
        if (e.footer != null) out.writeln(e.footer!.text);
      }
      if (m.stickers.isNotEmpty) {
        out.writeln('{Stickers}');
        for (final s in m.stickers) {
          out.writeln('${s.name} ${ctx.media(s.url)}');
        }
      }
      if (m.poll != null) {
        out.writeln('{Poll} ${m.poll!.question}');
        for (final a in m.poll!.answers) {
          out.writeln('- ${a.text} (${a.votes})');
        }
      }
      _writeComponents(out, m.components);
      if (m.thread != null) out.writeln('{Thread} ${m.thread!.displayName}');
    }
    if (m.reactions.isNotEmpty) {
      out
        ..writeln('{Reactions}')
        ..writeln(
          m.reactions
              .map((r) => '${_emojiText(r.emoji)} (${r.count})')
              .join(' '),
        );
    }
    out.writeln();
    sink.write(out.toString());
    commit(m);
  }

  void _writeAttachments(StringBuffer out, List<Attachment> attachments) {
    if (attachments.isEmpty) return;
    out.writeln('{Attachments}');
    for (final a in attachments) {
      out.writeln(ctx.media(a.url));
    }
  }

  void _writeComponents(StringBuffer out, List<Component> components) {
    for (final (line, _) in _componentLines(components, _text, ctx.media)) {
      out.writeln(line);
    }
  }

  @override
  void end(PartInfo part, {String? nextFileName}) {
    final out = StringBuffer()
      ..writeln(_rule())
      ..writeln(
        '$committedCount message${committedCount == 1 ? '' : 's'} '
        'in this file',
      );
    if (nextFileName != null) out.writeln('Continued in $nextFileName');
    out.writeln(_rule());
    sink.write(out.toString());
  }
}

class CsvWriter extends MessageWriter {
  CsvWriter(super.ctx, super.options);

  late final _text = TextMarkdownRenderer(ctx);

  static String _field(String value) => '"${value.replaceAll('"', '""')}"';

  @override
  void begin(PartInfo part) {
    // bom so excel reads the file as utf-8
    sink.write(
      '\u{FEFF}MessageID,AuthorID,Author,Date,Content,Attachments,'
      'Reactions,ReplyTo,Pinned\r\n',
    );
  }

  @override
  void add(Message m) {
    final system = systemLine(m, guildName: ctx.guild?.name);
    final parts = _componentLines(m.components, _text, ctx.media);
    final content = system != null
        ? plainSystemText(system, ctx.displayName)
        : [
            if (m.content.isNotEmpty) _text.render(parseMarkdown(m.content)),
            for (final (line, isFile) in parts)
              if (!isFile) line,
          ].join('\n');
    final row = [
      m.id,
      m.author.id,
      ctx.displayName(m.author),
      m.timestamp.toIso8601String(),
      content,
      [
        for (final a in m.attachments) ctx.media(a.url),
        for (final (line, isFile) in parts)
          if (isFile) line,
      ].join(','),
      m.reactions.map((r) => '${_emojiText(r.emoji)} (${r.count})').join(','),
      m.reference?.messageId ?? '',
      m.pinned ? 'true' : 'false',
    ];
    sink.write('${row.map(_field).join(',')}\r\n');
    commit(m);
  }

  @override
  void end(PartInfo part, {String? nextFileName}) {}
}
