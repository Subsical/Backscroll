import 'ast.dart';
import 'emoji.dart';

List<MdNode> parseMarkdown(String input, {bool blocks = true}) =>
    _parse(input, _Scope(blocks: blocks));

class _Scope {
  const _Scope({this.blocks = true, this.inQuote = false, this.links = true});

  final bool blocks;
  final bool inQuote;
  final bool links;

  _Scope get inline => _Scope(blocks: false, inQuote: inQuote, links: links);
  _Scope get quoted => _Scope(blocks: true, inQuote: true, links: links);
  _Scope get noLinks => _Scope(blocks: false, inQuote: inQuote, links: false);
}

typedef _Hit = (MdNode, int);

const _newline = 0x0A;
const _space = 0x20;
const _hash = 0x23;
const _closeParen = 0x29;
const _star = 0x2A;
const _dash = 0x2D;
const _less = 0x3C;
const _greater = 0x3E;
const _at = 0x40;
const _openBracket = 0x5B;
const _backslash = 0x5C;
const _underscore = 0x5F;
const _backtick = 0x60;
const _lowerH = 0x68;
const _pipe = 0x7C;
const _tilde = 0x7E;
const _variationSelector = 0xFE0F;
const _keycap = 0x20E3;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;

final _inlineCode = RegExp(r'(`{1,2})([\s\S]*?[^`])\1(?!`)');
final _codeLanguage = RegExp(r'^([A-Za-z0-9_+\-.#]+)\n');
final _heading = RegExp(r'(#{1,3}) +([^\n]*[^\s\n])[ \t]*(?:\n|$)');
final _subtext = RegExp(r'-# +([^\n]*[^\s\n])[ \t]*(?:\n|$)');
final _listItem = RegExp(
  r'( *)([-*]|\d{1,9}\.) +([^\n]*[^\s\n])[ \t]*(?:\n|$)',
);
final _maskedLink = RegExp(
  r'\[((?:\\[\s\S]|\[[^\]]*\]|[^\\\[\]]|\](?=[^\[]*\]))+)\]\(\s*<?((?:https?|discord)://[^\s()<>]+(?:\([^\s()<>]*\)[^\s()<>]*)*)>?(?:\s+"[^"]*")?\s*\)',
);
final _angleUrl = RegExp(r'<(https?://[^\s>]+)>');
final _url = RegExp('https?://[^\\s<]+[^<.,:;"\')\\]\\s]');
final _userMention = RegExp(r'<@!?(\d{1,20})>');
final _roleMention = RegExp(r'<@&(\d{1,20})>');
final _channelMention = RegExp(r'<#(\d{1,20})>');
final _command = RegExp(r'</([^:<>\n]{1,96}):(\d{1,20})>');
final _customEmoji = RegExp(r'<(a?):(\w{1,32}):(\d{1,20})>');
final _timestamp = RegExp(r'<t:(-?\d{1,13})(?::([tTdDfFR]))?>');
final _bold = RegExp(r'\*\*((?:\\[\s\S]|[^\\])+?)\*\*(?!\*)');
final _italicStar = RegExp(
  r'\*(?=\S)((?:\*\*|\\[\s\S]|\s+(?=[^\s*])|[^\s*\\])+?)\*(?!\*)',
);
final _underline = RegExp(r'__((?:\\[\s\S]|[^\\])+?)__(?!_)');
final _italicUnderscore = RegExp(
  r'_((?:__|\\[\s\S]|[^\\_])+?)_(?![\p{L}\p{N}_])',
  unicode: true,
);
final _strike = RegExp(r'~~((?:\\[\s\S]|[^\\])+?)~~(?!~)');
final _spoiler = RegExp(r'\|\|((?:\\[\s\S]|[^\\])+?)\|\|');
final _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);

List<MdNode> _parse(String s, _Scope scope) {
  final out = <MdNode>[];
  final text = StringBuffer();
  void flush() {
    if (text.isEmpty) return;
    _append(out, TextNode(text.toString()));
    text.clear();
  }

  var i = 0;
  while (i < s.length) {
    final lineStart = i == 0 || s.codeUnitAt(i - 1) == _newline;
    final hit = _match(s, i, scope, lineStart);
    if (hit != null) {
      flush();
      _append(out, hit.$1);
      i += hit.$2;
      continue;
    }
    final end = _plainRunEnd(s, i);
    text.write(s.substring(i, end));
    i = end;
  }
  flush();
  return out;
}

void _append(List<MdNode> out, MdNode node) {
  if (out.isNotEmpty) {
    final last = out.last;
    if (last is TextNode && node is TextNode) {
      out[out.length - 1] = TextNode(last.text + node.text);
      return;
    }
    if (last is QuoteNode && node is QuoteNode) {
      out[out.length - 1] = QuoteNode([
        ...last.children,
        const TextNode('\n'),
        ...node.children,
      ]);
      return;
    }
  }
  out.add(node);
}

bool _isSpecial(int c) => switch (c) {
  _newline ||
  _backslash ||
  _star ||
  _underscore ||
  _tilde ||
  _pipe ||
  _backtick ||
  _openBracket ||
  _less ||
  _at => true,
  _ => _mayStartEmoji(c),
};

// Emoji sit in a few places below U+FFFF (the copyright and registered
// signs, the symbol blocks, four CJK marks); the rest are surrogate pairs.
bool _mayStartEmoji(int c) =>
    c == 0xA9 ||
    c == 0xAE ||
    (c >= 0x2000 && c <= 0x2BFF) ||
    c == 0x3030 ||
    c == 0x303D ||
    c == 0x3297 ||
    c == 0x3299 ||
    _isHighSurrogate(c);

bool _keycapAhead(String s, int i) {
  if (i + 1 >= s.length) return false;
  final next = s.codeUnitAt(i + 1);
  return next == _variationSelector || next == _keycap;
}

int _plainRunEnd(String s, int start) {
  final first = s.codeUnitAt(start);
  if (_isSpecial(first)) {
    final isPair = _isHighSurrogate(first) && start + 1 < s.length;
    return start + (isPair ? 2 : 1);
  }
  var i = start + 1;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (_isSpecial(c)) break;
    if (c == _lowerH && s.startsWith('http', i)) break;
    if ((c == _hash || c == _star || _isDigit(c)) && _keycapAhead(s, i)) {
      break;
    }
    i++;
  }
  return i;
}

_Hit? _match(String s, int i, _Scope scope, bool lineStart) {
  final c = s.codeUnitAt(i);

  if (lineStart && scope.blocks) {
    final block = _blockAt(s, i, scope, c);
    if (block != null) return block;
  }

  switch (c) {
    case _backtick:
      return _codeBlockAt(s, i) ?? _inlineCodeAt(s, i);
    case _backslash:
      return _escapeAt(s, i);
    case _less:
      return _angleAt(s, i, scope);
    case _at:
      if (s.startsWith('@everyone', i)) {
        return (const MentionNode(MentionKind.everyone), 9);
      }
      if (s.startsWith('@here', i)) {
        return (const MentionNode(MentionKind.here), 5);
      }
      return null;
    case _openBracket:
      return scope.links ? _maskedLinkAt(s, i, scope) : null;
    case _lowerH:
      return scope.links ? _urlAt(s, i) : null;
    case _star:
      return _emojiAt(s, i) ??
          _format(_bold, FormatKind.bold, s, i, scope) ??
          _format(_italicStar, FormatKind.italic, s, i, scope);
    case _underscore:
      final underline = _format(_underline, FormatKind.underline, s, i, scope);
      if (underline != null) return underline;
      if (i > 0 && _wordChar.hasMatch(s[i - 1])) return null;
      return _format(_italicUnderscore, FormatKind.italic, s, i, scope);
    case _tilde:
      return _format(_strike, FormatKind.strikethrough, s, i, scope);
    case _pipe:
      return _format(_spoiler, FormatKind.spoiler, s, i, scope);
  }
  return _emojiAt(s, i);
}

_Hit? _blockAt(String s, int i, _Scope scope, int c) {
  if (c == _greater && !scope.inQuote) {
    if (s.startsWith('>>> ', i)) {
      return (
        QuoteNode(_parse(s.substring(i + 4), scope.quoted)),
        s.length - i,
      );
    }
    if (s.startsWith('> ', i)) {
      final end = s.indexOf('\n', i);
      final lineEnd = end < 0 ? s.length : end;
      final consumed = end < 0 ? s.length - i : end - i + 1;
      return (
        QuoteNode(_parse(s.substring(i + 2, lineEnd), scope.quoted)),
        consumed,
      );
    }
  }
  if (c == _hash) {
    final m = _heading.matchAsPrefix(s, i);
    if (m != null) {
      return (
        HeadingNode(m[1]!.length, _parse(m[2]!, scope.inline)),
        m.end - i,
      );
    }
  }
  if (c == _dash) {
    final m = _subtext.matchAsPrefix(s, i);
    if (m != null) {
      return (SubtextNode(_parse(m[1]!, scope.inline)), m.end - i);
    }
  }
  if (c == _dash || c == _star || c == _space || _isDigit(c)) {
    return _listAt(s, i, scope);
  }
  return null;
}

_Hit? _listAt(String s, int start, _Scope scope) {
  final first = _listItem.matchAsPrefix(s, start);
  if (first == null) return null;
  final baseIndent = first[1]!.length;
  final ordered = first[2]!.endsWith('.');
  final startNumber = ordered
      ? int.parse(first[2]!.substring(0, first[2]!.length - 1))
      : 1;
  final items = <List<MdNode>>[];
  final nested = StringBuffer();
  var pos = start;

  void flushNested() {
    if (nested.isEmpty || items.isEmpty) return;
    items.last.addAll(_parse(nested.toString(), scope));
    nested.clear();
  }

  while (pos < s.length) {
    final m = _listItem.matchAsPrefix(s, pos);
    if (m == null) break;
    final indent = m[1]!.length;
    if (indent >= baseIndent + 2 && items.isNotEmpty) {
      nested.write('${s.substring(pos + baseIndent + 2, m.end).trimRight()}\n');
    } else {
      if (indent != baseIndent || m[2]!.endsWith('.') != ordered) break;
      flushNested();
      items.add(_parse(m[3]!, scope.inline));
    }
    pos = m.end;
  }
  flushNested();
  return (ListNode(ordered, startNumber, items), pos - start);
}

_Hit? _codeBlockAt(String s, int i) {
  if (!s.startsWith('```', i)) return null;
  final close = s.indexOf('```', i + 3);
  if (close < 0) return null;
  var body = s.substring(i + 3, close);
  if (body.trim().isEmpty) return null;
  String? language;
  final lang = _codeLanguage.firstMatch(body);
  if (lang != null) {
    language = lang[1];
    body = body.substring(lang.end);
  } else if (body.startsWith('\n')) {
    body = body.substring(1);
  }
  body = body.replaceFirst(RegExp(r'\n+$'), '');
  var end = close + 3;
  if (end < s.length && s.codeUnitAt(end) == _newline) end++;
  return (CodeBlockNode(language, body), end - i);
}

_Hit? _inlineCodeAt(String s, int i) {
  final m = _inlineCode.matchAsPrefix(s, i);
  if (m == null) return null;
  return (InlineCodeNode(m[2]!), m.end - i);
}

_Hit? _escapeAt(String s, int i) {
  if (i + 1 >= s.length) return null;
  final next = s.codeUnitAt(i + 1);
  final isWordOrSpace =
      _isDigit(next) || _isLetter(next) || next == _space || next == _newline;
  if (isWordOrSpace) return null;
  final width = _isHighSurrogate(next) && i + 2 < s.length ? 2 : 1;
  return (TextNode(s.substring(i + 1, i + 1 + width)), 1 + width);
}

_Hit? _angleAt(String s, int i, _Scope scope) {
  Match? m;
  if ((m = _userMention.matchAsPrefix(s, i)) != null) {
    return (MentionNode(MentionKind.user, m![1]!), m.end - i);
  }
  if ((m = _roleMention.matchAsPrefix(s, i)) != null) {
    return (MentionNode(MentionKind.role, m![1]!), m.end - i);
  }
  if ((m = _channelMention.matchAsPrefix(s, i)) != null) {
    return (MentionNode(MentionKind.channel, m![1]!), m.end - i);
  }
  if ((m = _customEmoji.matchAsPrefix(s, i)) != null) {
    return (CustomEmojiNode(m![2]!, m[3]!, animated: m[1] == 'a'), m.end - i);
  }
  if ((m = _timestamp.matchAsPrefix(s, i)) != null) {
    final seconds = int.parse(m![1]!);
    if (seconds.abs() > 8640000000000) return null;
    return (
      TimestampNode(
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
        m[2],
      ),
      m.end - i,
    );
  }
  if ((m = _command.matchAsPrefix(s, i)) != null) {
    return (CommandNode(m![1]!, m[2]!), m.end - i);
  }
  if (scope.links && (m = _angleUrl.matchAsPrefix(s, i)) != null) {
    final url = m![1]!;
    return (LinkNode(url, [TextNode(url)]), m.end - i);
  }
  return null;
}

_Hit? _maskedLinkAt(String s, int i, _Scope scope) {
  final m = _maskedLink.matchAsPrefix(s, i);
  if (m == null) return null;
  return (
    LinkNode(m[2]!, _parse(m[1]!, scope.noLinks), masked: true),
    m.end - i,
  );
}

_Hit? _urlAt(String s, int i) {
  final m = _url.matchAsPrefix(s, i);
  if (m == null) return null;
  var url = m[0]!;
  // the pattern stops before ")", give it back when the url opened one
  var end = m.end;
  while (end < s.length &&
      s.codeUnitAt(end) == _closeParen &&
      '('.allMatches(url).length > ')'.allMatches(url).length) {
    url += ')';
    end++;
  }
  return (LinkNode(url, [TextNode(url)]), end - i);
}

_Hit? _emojiAt(String s, int i) {
  final m = emojiPattern.matchAsPrefix(s, i);
  if (m == null || m[0]!.isEmpty) return null;
  return (EmojiNode(m[0]!), m.end - i);
}

_Hit? _format(RegExp pattern, FormatKind kind, String s, int i, _Scope scope) {
  final m = pattern.matchAsPrefix(s, i);
  if (m == null) return null;
  return (FormatNode(kind, _parse(m[1]!, scope.inline)), m.end - i);
}
