final emojiPattern = RegExp(
  // the lint checks patterns without the unicode flag, so \p{} looks invalid
  // ignore: valid_regexps
  r'(?:\p{Regional_Indicator}{2})'
  r'|(?:[#*0-9]\u{FE0F}?\u{20E3})'
  r'|(?:\u{1F3F4}[\u{E0060}-\u{E007F}]+)'
  r'|(?:(?:\p{Emoji_Modifier_Base}\p{Emoji_Modifier}'
  r'|\p{Emoji_Presentation}\u{FE0F}?\p{Emoji_Modifier}?'
  r'|\p{Extended_Pictographic}\u{FE0F}\p{Emoji_Modifier}?)'
  r'(?:\u{200D}\p{Extended_Pictographic}\u{FE0F}?\p{Emoji_Modifier}?)*)',
  unicode: true,
);

// Twemoji names files after the code points, dropping the variation
// selector unless the sequence is joined with ZWJ.
String twemojiCode(String emoji) {
  final runes = emoji.runes.toList();
  final keepSelector = runes.contains(0x200D);
  return runes
      .where((r) => keepSelector || r != 0xFE0F)
      .map((r) => r.toRadixString(16))
      .join('-');
}

String twemojiUrl(String emoji) =>
    'https://cdn.jsdelivr.net/gh/jdecked/twemoji@latest/assets/svg/${twemojiCode(emoji)}.svg';

String twemojiPngUrl(String emoji) =>
    'https://cdn.jsdelivr.net/gh/jdecked/twemoji@latest/assets/72x72/${twemojiCode(emoji)}.png';
