import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../core/convert/converter.dart';
import '../../core/convert/reader.dart';
import '../../core/export/job.dart';
import '../../core/export/options.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

bool canConvert(ExportJob job) =>
    job.status == JobStatus.done &&
    job.parts.isNotEmpty &&
    (job.options.format.isHtml || job.options.format == ExportFormat.json);

List<ExportFormat> convertTargets(ExportFormat from) => [
  for (final format in ExportFormat.values)
    if (format != from) format,
];

Future<void> convertJob(
  BuildContext context,
  ExportJob job,
  ExportFormat format,
) => _convert(
  context,
  sources: [for (final part in job.parts) File(job.partPath(part))],
  format: format,
  from: job,
);

Future<ExportFormat> _formatOf(File file) async {
  if (sourceKindOf(file.path) == SourceKind.json) return ExportFormat.json;
  final start = await file
      .openRead(0, 400)
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  return start.contains('data-theme="light"')
      ? ExportFormat.htmlLight
      : ExportFormat.htmlDark;
}

Future<void> convertFile(BuildContext context) async {
  final picked = await FilePicker.pickFile(
    dialogTitle: 'Pick an export to convert',
    type: FileType.custom,
    allowedExtensions: ['html', 'json'],
  );
  final path = picked?.path;
  if (path == null || !context.mounted) return;
  final file = File(path);
  if (sourceKindOf(path) == null) {
    showToast(context, 'Only HTML and JSON exports can be converted.');
    return;
  }
  final from = await _formatOf(file);
  if (!context.mounted) return;
  final format = await showDialog<ExportFormat>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Convert to', style: Styles.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(p.basename(path), style: Styles.small),
          ),
          for (final format in convertTargets(from))
            HoverTile(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              onTap: () => Navigator.pop(context, format),
              child: Text(format.label, style: Styles.body),
            ),
        ],
      ),
    ),
  );
  if (format == null || !context.mounted) return;
  await _convert(context, sources: exportParts(file), format: format);
}

Future<void> _convert(
  BuildContext context, {
  required List<File> sources,
  required ExportFormat format,
  ExportJob? from,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ConvertDialog(sources: sources, format: format, from: from),
);

class _ConvertDialog extends StatefulWidget {
  const _ConvertDialog({
    required this.sources,
    required this.format,
    this.from,
  });

  final List<File> sources;
  final ExportFormat format;
  final ExportJob? from;

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  int _messages = 0;
  String? _error;
  bool _stop = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run();
  }

  Future<void> _run() async {
    final exports = AppScope.of(context).exports;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final job = await exports.convert(
        sources: widget.sources,
        format: widget.format,
        from: widget.from,
        onProgress: (messages) {
          if (mounted) setState(() => _messages = messages);
        },
        stopped: () => _stop,
      );
      if (!mounted) return;
      Navigator.pop(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Saved ${job.parts.first.fileName}')),
        );
    } on ConversionStopped {
      if (mounted) Navigator.pop(context);
    } on UnreadableExport catch (e) {
      _fail(e.message);
    } on FileSystemException catch (e) {
      _fail(
        widget.sources.every((file) => file.existsSync())
            ? 'Could not write the converted file: ${e.message}'
            : 'The export is no longer where it was saved.',
      );
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final numbers = NumberFormat.decimalPattern(AppScope.of(context).locale);
    return AlertDialog(
      title: Text(
        error == null
            ? 'Converting to ${widget.format.label}'
            : "This export can't be converted",
        style: Styles.title,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: error != null
            ? Text(error, style: Styles.body)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ThinProgress(value: null),
                  const SizedBox(height: 12),
                  Text(
                    _messages == 0
                        ? 'Reading the export'
                        : '${numbers.format(_messages)} messages',
                    style: Styles.small,
                  ),
                ],
              ),
      ),
      actions: [
        DiscordButton(
          label: error == null ? 'Cancel' : 'Close',
          tone: ButtonTone.link,
          onPressed: error == null
              ? () => setState(() => _stop = true)
              : () => Navigator.pop(context),
        ),
      ],
    );
  }
}
