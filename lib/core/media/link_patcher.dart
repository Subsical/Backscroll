import 'dart:convert';
import 'dart:io';

import '../export/options.dart';
import '../util/html.dart';

String mediaMarker(String nonce, String key) => '@@bs-$nonce:$key@@';

String _escapeFor(ExportFormat format, String url) => switch (format) {
  ExportFormat.htmlDark || ExportFormat.htmlLight => escapeAttr(url),
  ExportFormat.json => () {
    final quoted = jsonEncode(url);
    return quoted.substring(1, quoted.length - 1);
  }(),
  ExportFormat.csv => url.replaceAll('"', '""'),
  ExportFormat.txt => url,
};

// Markers never contain a line break, so patching line by line keeps memory
// flat no matter how big the part is.
Future<void> patchMarkers({
  required File input,
  required File output,
  required Map<String, String> replacements,
  required String nonce,
  required ExportFormat format,
}) async {
  final pattern = RegExp('@@bs-${RegExp.escape(nonce)}:([A-Za-z0-9_]+)@@');
  String patch(String text) => text.replaceAllMapped(pattern, (m) {
    final url = replacements[m[1]];
    return url == null ? '' : _escapeFor(format, url);
  });

  final temp = File('${output.path}.patching');
  final sink = temp.openWrite();
  var carry = '';
  try {
    await for (final chunk in input.openRead().transform(utf8.decoder)) {
      final text = carry + chunk;
      final cut = text.lastIndexOf('\n');
      if (cut < 0) {
        carry = text;
        continue;
      }
      sink.write(patch(text.substring(0, cut + 1)));
      carry = text.substring(cut + 1);
    }
    sink.write(patch(carry));
  } finally {
    await sink.close();
  }
  await temp.rename(output.path);
}
