import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../export/packed.dart';

enum SourceKind { json, html }

SourceKind? sourceKindOf(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.json' => SourceKind.json,
      '.html' || '.htm' => SourceKind.html,
      _ => null,
    };

class UnreadableExport implements Exception {
  const UnreadableExport(this.message);
  final String message;

  @override
  String toString() => message;
}

typedef OnHeader = void Function(Map<String, dynamic> header);
typedef OnMessage = FutureOr<void> Function(Map<String, dynamic> message);

Stream<String> _lines(File file) =>
    file.openRead().transform(utf8.decoder).transform(const LineSplitter());

Map<String, dynamic> _checked(Object? header) {
  if (header is Map<String, dynamic> &&
      header['channel'] is Map &&
      '${header['exporter']}'.startsWith('Backscroll')) {
    return header;
  }
  throw const UnreadableExport('This file is not a Backscroll export.');
}

Future<void> readExport(
  File file, {
  required OnHeader onHeader,
  required OnMessage onMessage,
}) => switch (sourceKindOf(file.path)) {
  SourceKind.json => _readJson(file, onHeader, onMessage),
  SourceKind.html => _readHtml(file, onHeader, onMessage),
  null => throw const UnreadableExport(
    'Only HTML and JSON exports can be converted.',
  ),
};

Future<void> _readJson(
  File file,
  OnHeader onHeader,
  OnMessage onMessage,
) async {
  final head = StringBuffer();
  var inHeader = true;
  var inMessages = false;
  try {
    await for (final line in _lines(file)) {
      if (inHeader) {
        if (line.startsWith('  "messages": [')) {
          final text = head.toString().trimRight();
          onHeader(
            _checked(jsonDecode('${text.substring(0, text.length - 1)}}')),
          );
          inHeader = false;
          inMessages = !line.contains(']');
        } else {
          head.writeln(line);
          // one message per line is how the exporter writes them
          if (head.length > 1 << 20) break;
        }
        continue;
      }
      if (!inMessages) continue;
      final text = line.trim();
      if (text.startsWith(']')) {
        inMessages = false;
      } else if (text.isNotEmpty) {
        await onMessage(
          jsonDecode(
            text.endsWith(',') ? text.substring(0, text.length - 1) : text,
          ) as Map<String, dynamic>,
        );
      }
    }
  } on FormatException {
    throw const UnreadableExport('This file is not a Backscroll export.');
  }
  if (!inHeader) return;

  // rewritten by another tool, so read it in one go
  final Object? whole;
  try {
    whole = jsonDecode(await file.readAsString());
  } on FormatException {
    throw const UnreadableExport('This file is not a Backscroll export.');
  }
  onHeader(_checked(whole));
  for (final message in ((whole as Map)['messages'] as List?) ?? const []) {
    if (message is Map<String, dynamic>) await onMessage(message);
  }
}

final _marker = RegExp(r'@@bs-[0-9a-f]+:([A-Za-z0-9_]+)@@');

String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

String _inner(String line) => line.substring(12, line.length - 3);

Future<void> _readHtml(
  File file,
  OnHeader onHeader,
  OnMessage onMessage,
) async {
  var sawHeader = false;
  List<String>? block;
  Map<String, String>? links;

  Future<void> flush() async {
    final lines = block;
    if (lines == null) return;
    final uploaded = links ?? const {};
    block = null;
    links = null;
    for (final line in lines) {
      final text = line.replaceAllMapped(_marker, (m) {
        final quoted = jsonEncode(uploaded[m[1]] ?? '');
        return quoted.substring(1, quoted.length - 1);
      });
      await onMessage(jsonDecode(text) as Map<String, dynamic>);
    }
  }

  var inLinks = false;
  try {
    await for (final line in _lines(file)) {
      if (inLinks) {
        final cut = line.indexOf('=');
        if (line == '-->' || cut < 0) {
          inLinks = false;
        } else {
          links![line.substring(0, cut)] = _unescape(line.substring(cut + 1));
        }
        continue;
      }
      if (line == '<!--bs-media:' && block != null) {
        links = {};
        inLinks = true;
        continue;
      }
      await flush();
      if (!line.endsWith('-->')) continue;
      if (line.startsWith('<!--bs-head:')) {
        onHeader(_checked(jsonDecode(unpackData(_inner(line)))));
        sawHeader = true;
      } else if (line.startsWith('<!--bs-data:') && sawHeader) {
        block = unpackData(_inner(line)).split('\n');
      }
    }
    await flush();
  } on FormatException {
    throw const UnreadableExport('The data inside this page is damaged.');
  }
  if (!sawHeader) {
    throw const UnreadableExport(
      'This page was exported by an older version of Backscroll, which '
      'did not keep the data needed to convert it. Export the conversation '
      'again to get a page that can be converted.',
    );
  }
}
