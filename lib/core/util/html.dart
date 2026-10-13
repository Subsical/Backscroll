import 'dart:convert';

const _element = HtmlEscape(HtmlEscapeMode.element);
const _attribute = HtmlEscape(
  HtmlEscapeMode(
    name: 'attribute',
    escapeLtGt: true,
    escapeQuot: true,
    escapeApos: true,
  ),
);

String escapeHtml(String text) => _element.convert(text);

String escapeAttr(String text) => _attribute.convert(text);

bool isSafeLink(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.scheme == 'https' ||
          uri.scheme == 'http' ||
          uri.scheme == 'discord');
}

String cssColor(int color) =>
    '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String cssRgba(int color, double alpha) =>
    'rgba(${(color >> 16) & 0xFF}, ${(color >> 8) & 0xFF}, ${color & 0xFF}, $alpha)';
