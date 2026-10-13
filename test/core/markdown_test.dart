import 'package:backscroll/core/markdown/ast.dart';
import 'package:backscroll/core/markdown/emoji.dart';
import 'package:backscroll/core/markdown/parser.dart';
import 'package:backscroll/core/markdown/renderers.dart';
import 'package:flutter_test/flutter_test.dart';

class _Resolver implements MarkdownResolver {
  @override
  String? userName(String id) => id == '1' ? 'Nick' : null;
  @override
  RoleInfo? role(String id) =>
      id == '2' ? const RoleInfo('Mods', 0x3498DB) : null;
  @override
  String? channelName(String id) => id == '3' ? 'general' : null;
  @override
  String media(String url) => url;
  @override
  String timestamp(DateTime time, String? style) => 'T(${style ?? 'f'})';
  @override
  String fullTimestamp(DateTime time) => 'FULL';
}

String html(String input) =>
    HtmlMarkdownRenderer(_Resolver()).render(parseMarkdown(input));

String text(String input) =>
    TextMarkdownRenderer(_Resolver()).render(parseMarkdown(input));

void main() {
  group('inline formatting', () {
    test('plain text stays a single node', () {
      final nodes = parseMarkdown('hello there, friend');
      expect(nodes, hasLength(1));
      expect((nodes.single as TextNode).text, 'hello there, friend');
    });

    test('bold, italic, underline, strike and spoiler', () {
      expect(
        html('**b** *i* _u_ __x__ ~~s~~ ||p||'),
        '<strong>b</strong> <em>i</em> <em>u</em> <u>x</u> <s>s</s> '
        '<span class="spoiler" tabindex="0">p</span>',
      );
    });

    test('bold italic nests', () {
      expect(html('***wow***'), '<strong><em>wow</em></strong>');
    });

    test('snake_case words are not italic', () {
      expect(html('my_var_name'), 'my_var_name');
    });

    test('unclosed markers are literal', () {
      expect(html('2 * 3 = 6 and *nope'), '2 * 3 = 6 and *nope');
    });

    test('escapes', () {
      expect(html(r'\*not italic\*'), '*not italic*');
    });
  });

  group('code', () {
    test('inline code is not formatted', () {
      expect(html('`**x**`'), '<code class="inline">**x**</code>');
      expect(html('``a`b``'), '<code class="inline">a`b</code>');
    });

    test('code block with a language', () {
      final node = parseMarkdown('```dart\nvoid main() {}\n```').single;
      expect(node, isA<CodeBlockNode>());
      expect((node as CodeBlockNode).language, 'dart');
      expect(node.code, 'void main() {}');
    });

    test('single line code block has no language', () {
      final node = parseMarkdown('```js```').single as CodeBlockNode;
      expect(node.language, isNull);
      expect(node.code, 'js');
    });
  });

  group('blocks', () {
    test('consecutive quotes merge', () {
      final nodes = parseMarkdown('> one\n> two\nafter');
      expect(nodes.first, isA<QuoteNode>());
      expect(
        html('> one\n> two\nafter'),
        '<blockquote>one\ntwo</blockquote>after',
      );
    });

    test('multi line quote takes the rest', () {
      expect(html('>>> a\nb'), '<blockquote>a\nb</blockquote>');
    });

    test('headings need a space', () {
      expect(html('# Title\nbody'), '<h1>Title</h1>body');
      expect(html('#hashtag'), '#hashtag');
    });

    test('subtext', () {
      expect(html('-# tiny'), '<small class="subtext">tiny</small>');
    });

    test('lists, ordered and nested', () {
      expect(html('- a\n- b'), '<ul><li>a</li><li>b</li></ul>');
      expect(html('3. x\n4. y'), '<ol start="3"><li>x</li><li>y</li></ol>');
      expect(
        html('- a\n  - b\n- c'),
        '<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>',
      );
    });

    test('quotes do not nest', () {
      expect(html('> > x'), '<blockquote>&gt; x</blockquote>');
    });
  });

  group('links', () {
    test('masked links', () {
      expect(
        html('[docs](https://example.com/a)'),
        '<a href="https://example.com/a" title="https://example.com/a" '
        'target="_blank" rel="noopener noreferrer">docs</a>',
      );
    });

    test('masked links can have square brackets in their text', () {
      final heading =
          parseMarkdown(
                '## [[RANKED!] Night Soccer](https://example.com/games/1)',
              ).single
              as HeadingNode;
      final link = heading.children.single as LinkNode;
      expect(link.url, 'https://example.com/games/1');
      expect(link.masked, isTrue);
      expect((link.children.single as TextNode).text, '[RANKED!] Night Soccer');

      final stray =
          parseMarkdown('[a] b](https://example.com/x)').single as LinkNode;
      expect((stray.children.single as TextNode).text, 'a] b');

      final nodes = parseMarkdown('[a] and [b](https://example.com/x)');
      expect((nodes.first as TextNode).text, '[a] and ');
      expect(((nodes.last as LinkNode).children.single as TextNode).text, 'b');
    });

    test('javascript urls are never links', () {
      expect(html('[x](javascript:alert(1))'), '[x](javascript:alert(1))');
    });

    test('auto links keep balanced parentheses', () {
      final node = parseMarkdown('see https://en.wikipedia.org/wiki/A_(b), ok')
          .whereType<LinkNode>()
          .single;
      expect(node.url, 'https://en.wikipedia.org/wiki/A_(b)');
    });

    test('auto links stop before closing punctuation', () {
      final node = parseMarkdown('(https://example.com/x_y).')
          .whereType<LinkNode>()
          .single;
      expect(node.url, 'https://example.com/x_y');
    });

    test('angle bracket links', () {
      expect(parseMarkdown('<https://x.dev>').single, isA<LinkNode>());
    });
  });

  group('mentions and emoji', () {
    test('resolves mentions', () {
      expect(
        text('<@1> <@!9> <@&2> <#3> @everyone </ban user:5>'),
        '@Nick @unknown-user @Mods #general @everyone /ban user',
      );
    });

    test('role colors show in html', () {
      expect(html('<@&2>'), contains('color: #3498db'));
    });

    test('custom and unicode emoji', () {
      final nodes = parseMarkdown('<a:dance:42> \u{1F600}\u{1F44D}\u{1F3FD}');
      expect(nodes.whereType<CustomEmojiNode>().single.animated, isTrue);
      expect(nodes.whereType<EmojiNode>().map((e) => e.emoji), [
        '\u{1F600}',
        '\u{1F44D}\u{1F3FD}',
      ]);
    });

    test('text style symbols stay text', () {
      expect(parseMarkdown('\u{A9} 2024').single, isA<TextNode>());
    });

    test('flags, keycaps and zwj sequences', () {
      final nodes = parseMarkdown(
        '\u{1F1FA}\u{1F1F8} 1\u{FE0F}\u{20E3} \u{1F3F3}\u{FE0F}\u{200D}\u{1F308}',
      );
      expect(nodes.whereType<EmojiNode>(), hasLength(3));
    });

    test('jumbo detection', () {
      expect(isEmojiOnly(parseMarkdown('\u{1F600} <:x:1>')), isTrue);
      expect(isEmojiOnly(parseMarkdown('hi \u{1F600}')), isFalse);
    });

    test('twemoji file names', () {
      expect(twemojiCode('\u{2764}\u{FE0F}'), '2764');
      expect(
        twemojiCode('\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}'),
        '1f3f3-fe0f-200d-1f308',
      );
      expect(twemojiCode('1\u{FE0F}\u{20E3}'), '31-20e3');
    });

    test('timestamps', () {
      expect(
        html('<t:1618953630:R>'),
        '<span class="timestamp-mention" title="FULL">T(R)</span>',
      );
    });
  });

  test('html is escaped', () {
    expect(html('<b>hi</b> & "you"'), '&lt;b&gt;hi&lt;/b&gt; &amp; "you"');
  });

  test('text renderer keeps structure', () {
    expect(text('> quoted\nplain'), '> quoted\nplain');
    expect(text('```py\nx = 1\n```\nafter'), '```py\nx = 1\n```\nafter');
  });
}
