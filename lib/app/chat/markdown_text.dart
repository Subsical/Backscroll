import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/discord/cdn.dart';
import '../../core/markdown/ast.dart';
import '../../core/markdown/emoji.dart';
import '../../core/markdown/parser.dart';
import '../../core/markdown/renderers.dart';
import '../../core/util/html.dart';
import '../scope.dart';
import '../theme.dart';

class MarkdownText extends StatefulWidget {
  const MarkdownText(
    this.source, {
    super.key,
    required this.resolver,
    this.style = Styles.body,
    this.singleLine = false,
    this.trailing,
  });

  final String source;
  final MarkdownResolver resolver;
  final TextStyle style;
  final bool singleLine;
  final InlineSpan? trailing;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  final _recognizers = <GestureRecognizer>[];
  final _revealed = <int>{};
  var _spoilerIndex = 0;

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    _spoilerIndex = 0;
    var nodes = parseMarkdown(widget.source, blocks: !widget.singleLine);
    if (widget.singleLine) {
      final spans = _spans(singleLineNodes(nodes), widget.style, false);
      return Text.rich(
        TextSpan(children: spans, style: widget.style),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final jumbo = isEmojiOnly(nodes);
    final blocks = _blocks(
      nodes,
      widget.style,
      jumbo,
      trailing: widget.trailing,
    );
    if (blocks.length == 1) return blocks.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  List<Widget> _blocks(
    List<MdNode> nodes,
    TextStyle style,
    bool jumbo, {
    InlineSpan? trailing,
  }) {
    final widgets = <Widget>[];
    final inline = <MdNode>[];

    void flush({bool beforeBlock = false, InlineSpan? tail}) {
      if (inline.isNotEmpty && beforeBlock) {
        final last = inline.last;
        if (last is TextNode && last.text.endsWith('\n')) {
          inline[inline.length - 1] = TextNode(
            last.text.substring(0, last.text.length - 1),
          );
        }
      }
      final hasContent = inline.any(
        (n) => n is! TextNode || n.text.trim().isNotEmpty,
      );
      if (hasContent || tail != null) {
        widgets.add(
          Text.rich(
            TextSpan(
              style: style,
              children: [..._spans(inline, style, jumbo), ?tail],
            ),
          ),
        );
      }
      inline.clear();
    }

    for (final node in nodes) {
      switch (node) {
        case CodeBlockNode(:final code):
          flush(beforeBlock: true);
          widgets.add(_codeBlock(code));
        case QuoteNode(:final children):
          flush(beforeBlock: true);
          widgets.add(
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.only(left: 12),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Palette.spine, width: 4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _blocks(children, style, false),
              ),
            ),
          );
        case HeadingNode(:final level, :final children):
          flush(beforeBlock: true);
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text.rich(
                TextSpan(
                  children: _spans(children, style, false),
                  style: style.copyWith(
                    fontSize: switch (level) {
                      1 => 24,
                      2 => 20,
                      _ => 16,
                    },
                    fontWeight: FontWeight.w700,
                    color: Palette.header,
                  ),
                ),
              ),
            ),
          );
        case SubtextNode(:final children):
          flush(beforeBlock: true);
          widgets.add(
            Text.rich(
              TextSpan(
                children: _spans(children, style, false),
                style: style.copyWith(fontSize: 13, color: Palette.muted),
              ),
            ),
          );
        case ListNode(:final ordered, :final start, :final items):
          flush(beforeBlock: true);
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            ordered ? '${start + i}.' : '\u{2022}',
                            style: style,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _blocks(items[i], style, false),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        default:
          inline.add(node);
      }
    }
    flush(tail: trailing);
    return widgets;
  }

  Widget _codeBlock(String code) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 4, bottom: 2),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Palette.code,
      border: Border.all(color: Palette.selected),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      code,
      style: const TextStyle(
        fontFamily: Fonts.mono,
        fontFamilyFallback: Fonts.monoFallback,
        fontSize: 13.5,
        height: 1.35,
        color: Palette.text,
      ),
    ),
  );

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  TextStyle get _mentionStyle => const TextStyle(
    color: Palette.mentionText,
    backgroundColor: Palette.mention,
    fontWeight: FontWeight.w500,
  );

  List<InlineSpan> _spans(List<MdNode> nodes, TextStyle style, bool jumbo) {
    final resolver = widget.resolver;
    final images = AppScope.of(context).images;
    final emojiSize = jumbo ? 48.0 : (style.fontSize ?? 16) * 1.375;
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      switch (node) {
        case TextNode(:final text):
          spans.add(TextSpan(text: text));
        case FormatNode(:final kind, :final children):
          if (kind == FormatKind.spoiler) {
            final index = _spoilerIndex++;
            final open = _revealed.contains(index);
            spans.add(
              TextSpan(
                children: _spans(children, style, jumbo),
                recognizer: open
                    ? null
                    : _tap(() => setState(() => _revealed.add(index))),
                style: open
                    ? const TextStyle(backgroundColor: Palette.hover)
                    : const TextStyle(
                        color: Palette.spoiler,
                        backgroundColor: Palette.spoiler,
                      ),
              ),
            );
            continue;
          }
          spans.add(
            TextSpan(
              children: _spans(children, style, jumbo),
              style: switch (kind) {
                FormatKind.bold => const TextStyle(fontWeight: FontWeight.w700),
                FormatKind.italic => const TextStyle(
                  fontStyle: FontStyle.italic,
                ),
                FormatKind.underline => const TextStyle(
                  decoration: TextDecoration.underline,
                ),
                _ => const TextStyle(decoration: TextDecoration.lineThrough),
              },
            ),
          );
        case InlineCodeNode(:final code):
          spans.add(
            TextSpan(
              text: code,
              style: const TextStyle(
                fontFamily: Fonts.mono,
                fontFamilyFallback: Fonts.monoFallback,
                fontSize: 13.5,
                backgroundColor: Palette.code,
              ),
            ),
          );
        case LinkNode(:final url, :final children):
          spans.add(
            TextSpan(
              children: _spans(children, style, jumbo),
              style: const TextStyle(color: Palette.link),
              recognizer: isSafeLink(url)
                  ? _tap(
                      () => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                    )
                  : null,
            ),
          );
        case MentionNode(:final kind, :final id):
          final text = switch (kind) {
            MentionKind.everyone => '@everyone',
            MentionKind.here => '@here',
            MentionKind.user => '@${resolver.userName(id) ?? 'unknown-user'}',
            MentionKind.channel => '#${resolver.channelName(id) ?? 'unknown'}',
            MentionKind.role => '@${resolver.role(id)?.name ?? 'deleted-role'}',
          };
          final roleColor = kind == MentionKind.role
              ? resolver.role(id)?.color
              : null;
          spans.add(
            TextSpan(
              text: text,
              style: roleColor != null && roleColor != 0
                  ? TextStyle(
                      color: Color(0xFF000000 | roleColor),
                      backgroundColor: Color(0x1A000000 | roleColor),
                      fontWeight: FontWeight.w500,
                    )
                  : _mentionStyle,
            ),
          );
        case CommandNode(:final name):
          spans.add(TextSpan(text: '/$name', style: _mentionStyle));
        case CustomEmojiNode(:final id, :final animated, :final name):
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Tooltip(
                message: ':$name:',
                child: Image(
                  image: images(customEmojiUrl(id, animated: animated)),
                  width: emojiSize,
                  height: emojiSize,
                  errorBuilder: (_, _, _) => Text(':$name:'),
                ),
              ),
            ),
          );
        case EmojiNode(:final emoji):
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Image(
                  image: images(twemojiPngUrl(emoji)),
                  width: emojiSize,
                  height: emojiSize,
                  errorBuilder: (_, _, _) => Text(
                    emoji,
                    style: TextStyle(fontSize: jumbo ? 40 : style.fontSize),
                  ),
                ),
              ),
            ),
          );
        case TimestampNode(:final time, :final style):
          spans.add(
            TextSpan(
              text: resolver.timestamp(time, style),
              style: const TextStyle(backgroundColor: Palette.hover),
            ),
          );
        case CodeBlockNode() ||
            QuoteNode() ||
            HeadingNode() ||
            SubtextNode() ||
            ListNode():
          break;
      }
    }
    return spans;
  }
}
