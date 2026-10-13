sealed class MdNode {
  const MdNode();
}

class TextNode extends MdNode {
  const TextNode(this.text);
  final String text;
}

enum FormatKind { bold, italic, underline, strikethrough, spoiler }

class FormatNode extends MdNode {
  const FormatNode(this.kind, this.children);
  final FormatKind kind;
  final List<MdNode> children;
}

class InlineCodeNode extends MdNode {
  const InlineCodeNode(this.code);
  final String code;
}

class CodeBlockNode extends MdNode {
  const CodeBlockNode(this.language, this.code);
  final String? language;
  final String code;
}

class QuoteNode extends MdNode {
  const QuoteNode(this.children);
  final List<MdNode> children;
}

class HeadingNode extends MdNode {
  const HeadingNode(this.level, this.children);
  final int level;
  final List<MdNode> children;
}

class SubtextNode extends MdNode {
  const SubtextNode(this.children);
  final List<MdNode> children;
}

class ListNode extends MdNode {
  const ListNode(this.ordered, this.start, this.items);
  final bool ordered;
  final int start;
  final List<List<MdNode>> items;
}

class LinkNode extends MdNode {
  const LinkNode(this.url, this.children, {this.masked = false});
  final String url;
  final List<MdNode> children;
  final bool masked;
}

enum MentionKind { user, role, channel, everyone, here }

class MentionNode extends MdNode {
  const MentionNode(this.kind, [this.id = '']);
  final MentionKind kind;
  final String id;
}

class CommandNode extends MdNode {
  const CommandNode(this.name, this.id);
  final String name;
  final String id;
}

class CustomEmojiNode extends MdNode {
  const CustomEmojiNode(this.name, this.id, {this.animated = false});
  final String name;
  final String id;
  final bool animated;
}

class EmojiNode extends MdNode {
  const EmojiNode(this.emoji);
  final String emoji;
}

class TimestampNode extends MdNode {
  const TimestampNode(this.time, this.style);
  final DateTime time;
  final String? style;
}

void visitNodes(List<MdNode> nodes, void Function(MdNode node) visit) {
  for (final node in nodes) {
    visit(node);
    switch (node) {
      case FormatNode(:final children) ||
          QuoteNode(:final children) ||
          HeadingNode(:final children) ||
          SubtextNode(:final children) ||
          LinkNode(:final children):
        visitNodes(children, visit);
      case ListNode(:final items):
        for (final item in items) {
          visitNodes(item, visit);
        }
      default:
        break;
    }
  }
}

bool isEmojiOnly(List<MdNode> nodes, {int max = 30}) {
  var count = 0;
  for (final node in nodes) {
    switch (node) {
      case EmojiNode() || CustomEmojiNode():
        count++;
      case TextNode(:final text) when text.trim().isEmpty:
        break;
      default:
        return false;
    }
  }
  return count > 0 && count <= max;
}

// Reply previews, topics and embed titles show on a single line without
// links, the way Discord renders them.
List<MdNode> singleLineNodes(List<MdNode> nodes) => [
  for (final node in nodes)
    ...switch (node) {
      TextNode(:final text) => [TextNode(text.replaceAll('\n', ' '))],
      CodeBlockNode(:final code) => [
        InlineCodeNode(code.replaceAll('\n', ' ')),
      ],
      QuoteNode(:final children) ||
      HeadingNode(:final children) ||
      SubtextNode(:final children) ||
      LinkNode(:final children) => singleLineNodes(children),
      ListNode(:final items) => [
        for (final item in items) ...[
          ...singleLineNodes(item),
          const TextNode(' '),
        ],
      ],
      FormatNode(:final kind, :final children) => [
        FormatNode(kind, singleLineNodes(children)),
      ],
      _ => [node],
    },
];
