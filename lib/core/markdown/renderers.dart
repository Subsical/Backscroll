import '../discord/cdn.dart';
import '../util/html.dart';
import 'ast.dart';
import 'emoji.dart';

class RoleInfo {
  const RoleInfo(this.name, this.color);
  final String name;
  final int color;
}

abstract class MarkdownResolver {
  String? userName(String id);
  RoleInfo? role(String id);
  String? channelName(String id);
  String media(String url);
  String timestamp(DateTime time, String? style);
  String fullTimestamp(DateTime time);
}

class HtmlMarkdownRenderer {
  HtmlMarkdownRenderer(this.resolver);

  final MarkdownResolver resolver;

  String render(List<MdNode> nodes, {bool jumbo = false}) {
    final out = StringBuffer();
    _writeAll(nodes, out, jumbo);
    return out.toString();
  }

  void _writeAll(List<MdNode> nodes, StringBuffer out, bool jumbo) {
    for (final node in nodes) {
      _write(node, out, jumbo);
    }
  }

  void _write(MdNode node, StringBuffer out, bool jumbo) {
    switch (node) {
      case TextNode(:final text):
        out.write(escapeHtml(text));
      case FormatNode(:final kind, :final children):
        final (open, close) = switch (kind) {
          FormatKind.bold => ('<strong>', '</strong>'),
          FormatKind.italic => ('<em>', '</em>'),
          FormatKind.underline => ('<u>', '</u>'),
          FormatKind.strikethrough => ('<s>', '</s>'),
          FormatKind.spoiler => (
            '<span class="spoiler" tabindex="0">',
            '</span>',
          ),
        };
        out.write(open);
        _writeAll(children, out, jumbo);
        out.write(close);
      case InlineCodeNode(:final code):
        out.write('<code class="inline">${escapeHtml(code)}</code>');
      case CodeBlockNode(:final language, :final code):
        final cls = language == null
            ? 'nohighlight'
            : 'language-${escapeAttr(language.toLowerCase())}';
        out.write(
          '<pre class="codeblock"><code class="$cls">'
          '${escapeHtml(code)}</code></pre>',
        );
      case QuoteNode(:final children):
        out.write('<blockquote>');
        _writeAll(children, out, jumbo);
        out.write('</blockquote>');
      case HeadingNode(:final level, :final children):
        out.write('<h$level>');
        _writeAll(children, out, jumbo);
        out.write('</h$level>');
      case SubtextNode(:final children):
        out.write('<small class="subtext">');
        _writeAll(children, out, jumbo);
        out.write('</small>');
      case ListNode(:final ordered, :final start, :final items):
        out.write(
          ordered ? (start == 1 ? '<ol>' : '<ol start="$start">') : '<ul>',
        );
        for (final item in items) {
          out.write('<li>');
          _writeAll(item, out, jumbo);
          out.write('</li>');
        }
        out.write(ordered ? '</ol>' : '</ul>');
      case LinkNode(:final url, :final children, :final masked):
        if (!isSafeLink(url)) {
          _writeAll(children, out, jumbo);
          return;
        }
        final title = masked ? ' title="${escapeAttr(url)}"' : '';
        out.write(
          '<a href="${escapeAttr(url)}"$title target="_blank" '
          'rel="noopener noreferrer">',
        );
        _writeAll(children, out, jumbo);
        out.write('</a>');
      case MentionNode(:final kind, :final id):
        _writeMention(kind, id, out);
      case CommandNode(:final name):
        out.write('<span class="mention">/${escapeHtml(name)}</span>');
      case CustomEmojiNode(:final name, :final id, :final animated):
        final src = resolver.media(customEmojiUrl(id, animated: animated));
        out.write(
          '<img class="emoji${jumbo ? ' jumbo' : ''}" '
          'src="${escapeAttr(src)}" alt=":${escapeAttr(name)}:" '
          'title=":${escapeAttr(name)}:" loading="lazy">',
        );
      case EmojiNode(:final emoji):
        final src = resolver.media(twemojiUrl(emoji));
        out.write(
          '<img class="emoji${jumbo ? ' jumbo' : ''}" '
          'src="${escapeAttr(src)}" alt="${escapeAttr(emoji)}" '
          'loading="lazy">',
        );
      case TimestampNode(:final time, :final style):
        out.write(
          '<span class="timestamp-mention" '
          'title="${escapeAttr(resolver.fullTimestamp(time))}">'
          '${escapeHtml(resolver.timestamp(time, style))}</span>',
        );
    }
  }

  void _writeMention(MentionKind kind, String id, StringBuffer out) {
    switch (kind) {
      case MentionKind.everyone:
        out.write('<span class="mention">@everyone</span>');
      case MentionKind.here:
        out.write('<span class="mention">@here</span>');
      case MentionKind.user:
        final name = resolver.userName(id);
        out.write(
          '<span class="mention" title="${escapeAttr(id)}">'
          '@${escapeHtml(name ?? 'unknown-user')}</span>',
        );
      case MentionKind.channel:
        final name = resolver.channelName(id);
        out.write(
          '<span class="mention channel-mention">'
          '#${escapeHtml(name ?? 'unknown')}</span>',
        );
      case MentionKind.role:
        final role = resolver.role(id);
        if (role == null) {
          out.write('<span class="mention">@deleted-role</span>');
        } else if (role.color == 0) {
          out.write('<span class="mention">@${escapeHtml(role.name)}</span>');
        } else {
          out.write(
            '<span class="mention" style="color: '
            '${cssColor(role.color)}; background-color: '
            '${cssRgba(role.color, 0.1)}">@${escapeHtml(role.name)}</span>',
          );
        }
    }
  }
}

class TextMarkdownRenderer {
  TextMarkdownRenderer(this.resolver);

  final MarkdownResolver resolver;

  String render(List<MdNode> nodes) {
    final out = StringBuffer();
    _writeAll(nodes, out);
    return out.toString().trimRight();
  }

  void _writeAll(List<MdNode> nodes, StringBuffer out) {
    for (final node in nodes) {
      _write(node, out);
    }
  }

  void _wrap(String marker, List<MdNode> children, StringBuffer out) {
    out.write(marker);
    _writeAll(children, out);
    out.write(marker);
  }

  void _write(MdNode node, StringBuffer out) {
    switch (node) {
      case TextNode(:final text):
        out.write(text);
      case FormatNode(:final kind, :final children):
        _wrap(
          switch (kind) {
            FormatKind.bold => '**',
            FormatKind.italic => '*',
            FormatKind.underline => '__',
            FormatKind.strikethrough => '~~',
            FormatKind.spoiler => '||',
          },
          children,
          out,
        );
      case InlineCodeNode(:final code):
        out.write('`$code`');
      case CodeBlockNode(:final language, :final code):
        out.write('```${language ?? ''}\n$code\n```\n');
      case QuoteNode(:final children):
        final inner = TextMarkdownRenderer(resolver).render(children);
        out.write(inner.split('\n').map((line) => '> $line').join('\n'));
        out.write('\n');
      case HeadingNode(:final level, :final children):
        out.write('${'#' * level} ');
        _writeAll(children, out);
        out.write('\n');
      case SubtextNode(:final children):
        out.write('-# ');
        _writeAll(children, out);
        out.write('\n');
      case ListNode(:final ordered, :final start, :final items):
        for (var i = 0; i < items.length; i++) {
          out.write(ordered ? '${start + i}. ' : '- ');
          _writeAll(items[i], out);
          out.write('\n');
        }
      case LinkNode(:final url, :final children, :final masked):
        if (masked) {
          out.write('[');
          _writeAll(children, out);
          out.write(']($url)');
        } else {
          out.write(url);
        }
      case MentionNode(:final kind, :final id):
        out.write(switch (kind) {
          MentionKind.everyone => '@everyone',
          MentionKind.here => '@here',
          MentionKind.user => '@${resolver.userName(id) ?? 'unknown-user'}',
          MentionKind.channel => '#${resolver.channelName(id) ?? 'unknown'}',
          MentionKind.role => '@${resolver.role(id)?.name ?? 'deleted-role'}',
        });
      case CommandNode(:final name):
        out.write('/$name');
      case CustomEmojiNode(:final name):
        out.write(':$name:');
      case EmojiNode(:final emoji):
        out.write(emoji);
      case TimestampNode(:final time, :final style):
        out.write(resolver.timestamp(time, style));
    }
  }
}
