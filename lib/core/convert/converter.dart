import 'dart:io';

import 'package:path/path.dart' as p;

import '../discord/models.dart';
import '../discord/snowflake.dart';
import '../export/dates.dart';
import '../export/naming.dart';
import '../export/options.dart';
import '../export/part_sink.dart';
import '../export/writers/html_writer.dart';
import '../export/writers/json_writer.dart';
import '../export/writers/text_writer.dart';
import '../export/writers/writer.dart';
import '../media/media_refs.dart';
import '../media/pipeline.dart';
import '../util/files.dart';
import 'decode.dart';
import 'reader.dart';

class ConversionStopped implements Exception {
  @override
  String toString() => 'Conversion stopped';
}

class ConvertedExport {
  const ConvertedExport({
    required this.header,
    required this.baseName,
    required this.files,
    required this.counts,
  });

  final Map<String, dynamic> header;
  final String baseName;
  final List<String> files;
  final List<int> counts;

  int get messages => counts.fold(0, (sum, count) => sum + count);
}

final _partSuffix = RegExp(r' \[part (\d+)\]$');

String exportBaseOf(String path) =>
    p.basenameWithoutExtension(path).replaceFirst(_partSuffix, '');

// every part of the export a file belongs to, in order
List<File> exportParts(File file) {
  final extension = p.extension(file.path).substring(1);
  final base = exportBaseOf(file.path);
  final parts = <File>[];
  for (var index = 1; ; index++) {
    final part = File(
      p.join(file.parent.path, partFileName(base, index, extension)),
    );
    if (!part.existsSync()) break;
    parts.add(part);
  }
  return parts.isEmpty ? [file] : parts;
}

class _Links implements ExportLinks {
  final _done = <(String, String, String)>[];
  String? first;
  String? last;

  void finish(String fileName) {
    if (first != null) _done.add((first!, last!, fileName));
    first = last = null;
  }

  @override
  String? messageHref(String messageId) {
    if (first != null && compareSnowflakes(messageId, first!) >= 0) {
      return '#m-$messageId';
    }
    for (final (from, to, fileName) in _done.reversed) {
      if (compareSnowflakes(messageId, from) < 0) continue;
      return compareSnowflakes(messageId, to) > 0
          ? null
          : '${Uri.encodeComponent(fileName)}#m-$messageId';
    }
    return null;
  }

  @override
  String? threadHref(Channel thread) => null;
}

String _freeBase(String dir, String base, int parts, String extension) {
  bool taken(String name) => [
    for (var index = 1; index <= parts; index++)
      File(p.join(dir, partFileName(name, index, extension))),
  ].any((file) => file.existsSync());

  if (!taken(base)) return base;
  for (var n = 1; ; n++) {
    final name = n == 1 ? '$base (converted)' : '$base (converted $n)';
    if (!taken(name)) return name;
  }
}

Future<ConvertedExport> convertExport({
  required List<File> sources,
  required ExportFormat target,
  ExportAssets assets = const ExportAssets(),
  String? locale,
  bool useUtc = false,
  void Function(int messages)? onProgress,
  bool Function()? stopped,
}) async {
  final dir = sources.first.parent.path;
  final sourceBase = exportBaseOf(sources.first.path);
  final base = _freeBase(dir, sourceBase, sources.length, target.extension);
  final names = [
    for (var index = 1; index <= sources.length; index++)
      partFileName(base, index, target.extension),
  ];

  final mediaDir = mediaDirName(sourceBase);
  final saved = <String>{};
  final folder = Directory(p.join(dir, mediaDir));
  if (folder.existsSync()) {
    for (final entity in folder.listSync()) {
      if (entity is File) saved.add(p.basename(entity.path));
    }
  }
  final local = <String, String?>{};
  String? savedCopy(String url) => local.putIfAbsent(url, () {
    final name = mediaBaseName(MediaRef(url));
    final found = saved.contains(name)
        ? name
        : saved.where((file) => file.startsWith('$name.')).firstOrNull;
    return found == null ? null : '$mediaDir/$found';
  });

  final links = _Links();
  final counts = <int>[];
  final written = <String>[];
  Map<String, dynamic>? firstHeader;
  ExportDecoder? decoder;
  MessageWriter? writer;
  var total = 0;
  PartSink? sink;

  try {
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      final info = PartInfo(
        index: index + 1,
        fileName: names[index],
        previousFileName: index == 0 ? null : names[index - 1],
      );
      final path = p.join(dir, names[index]);
      final open = sink = PartSink.open('$path.partial');
      var count = 0;
      await readExport(
        source,
        onHeader: (header) {
          if (decoder == null) {
            firstHeader = header;
            final range = header['dateRange'] as Map<String, dynamic>?;
            final options = ExportOptions(
              outputDir: dir,
              format: target,
              after: DateTime.tryParse('${range?['after']}'),
              before: DateTime.tryParse('${range?['before']}'),
              partitionSize: sources.length > 1 ? 1 : 0,
              pinnedOnly: header['pinnedOnly'] == true,
              useUtc: useUtc,
              locale: locale,
            );
            final made = decoder = ExportDecoder(
              header,
              dates: DateFormatter(
                locale: locale,
                utc: useUtc,
                now: DateTime.tryParse('${header['exportedAt']}'),
              ),
              html: sourceKindOf(source.path) == SourceKind.html,
            );
            made.ctx.mediaLookup = (url) {
              final stored = made.urls[url] ?? url;
              final link = isRelativeUrl(stored)
                  ? stored
                  : savedCopy(stored) ?? stored;
              return target.isHtml && isRelativeUrl(link)
                  ? encodeRelativeUrl(link)
                  : link;
            };
            writer = switch (target) {
              ExportFormat.htmlDark || ExportFormat.htmlLight => HtmlWriter(
                made.ctx,
                options,
                assets: assets,
                links: links,
              ),
              ExportFormat.json => JsonWriter(made.ctx, options),
              ExportFormat.txt => TextWriter(made.ctx, options),
              ExportFormat.csv => CsvWriter(made.ctx, options),
            };
          }
          writer!
            ..startPart(open)
            ..begin(info);
        },
        onMessage: (json) {
          if (stopped?.call() ?? false) throw ConversionStopped();
          final message = decoder!.message(json);
          links
            ..first ??= message.id
            ..last = message.id;
          writer!.add(message);
          count++;
          total++;
          if (total % 500 == 0) onProgress?.call(total);
        },
      );
      writer!.end(
        info,
        nextFileName: index + 1 < names.length ? names[index + 1] : null,
      );
      open.close();
      sink = null;
      await moveFile('$path.partial', path);
      links.finish(names[index]);
      counts.add(count);
      written.add(path);
    }
  } on Object {
    sink?.discard();
    for (final name in names) {
      final partial = File('${p.join(dir, name)}.partial');
      if (partial.existsSync()) partial.deleteSync();
    }
    for (final path in written) {
      File(path).deleteSync();
    }
    rethrow;
  }
  onProgress?.call(total);
  return ConvertedExport(
    header: firstHeader!,
    baseName: base,
    files: written,
    counts: counts,
  );
}
