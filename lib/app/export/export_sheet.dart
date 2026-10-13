import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/discord/models.dart';
import '../../core/export/options.dart';
import '../scope.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<bool> showExportSheet(
  BuildContext context, {
  required List<Channel> channels,
  GuildState? guild,
  DateTime? after,
  DateTime? before,
}) async {
  final sheet = ExportSheet(
    channels: channels,
    guild: guild,
    after: after,
    before: before,
  );
  final result = isCompact(context)
      ? await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) =>
              FractionallySizedBox(heightFactor: 0.92, child: sheet),
        )
      : await showDialog<bool>(
          context: context,
          builder: (_) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
              child: sheet,
            ),
          ),
        );
  return result ?? false;
}

class ExportSheet extends StatefulWidget {
  const ExportSheet({
    super.key,
    required this.channels,
    this.guild,
    this.after,
    this.before,
  });

  final List<Channel> channels;
  final GuildState? guild;
  final DateTime? after;
  final DateTime? before;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  ExportOptions? _options;
  bool _busy = false;
  String? _error;
  late final _partition = TextEditingController();

  ExportOptions get options => _options!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_options != null) return;
    _options = AppScope.of(context).exports
        .defaultOptions()
        .copyWith(after: () => widget.after, before: () => widget.before);
    _partition.text = options.partitionSize == 0
        ? ''
        : '${options.partitionSize}';
  }

  @override
  void dispose() {
    _partition.dispose();
    super.dispose();
  }

  void _set(ExportOptions next) => setState(() => _options = next);

  String get _title {
    if (widget.channels.length == 1) {
      final c = widget.channels.single;
      return 'Export ${c.isPrivate ? c.displayName : '#${c.displayName}'}';
    }
    return 'Export ${widget.channels.length} channels';
  }

  Future<void> _pickDate({required bool after}) async {
    final current = after ? options.after : options.before;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme
              .copyWith(surface: Palette.panel),
          datePickerTheme: const DatePickerThemeData(
            backgroundColor: Palette.panel,
            surfaceTintColor: Colors.transparent,
            headerBackgroundColor: Palette.blurple,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    _set(
      after
          ? options.copyWith(after: () => picked)
          : options.copyWith(before: () => picked),
    );
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Where should the export go?',
      initialDirectory: options.outputDir,
    );
    if (path != null) _set(options.copyWith(outputDir: path));
  }

  Future<void> _start() async {
    final services = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await services.exports.start(
        channels: widget.channels,
        options: options.copyWith(
          partitionSize: int.tryParse(_partition.text) ?? 0,
        ),
        guild: widget.guild?.guild,
        categoryOf: widget.guild?.categoryOf,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FileSystemException catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not write to ${options.outputDir}: ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final providers = services.settings.enabledProviders;
    final threads = widget.channels.any((c) => c.canHaveThreads);
    final date = DateFormat.yMMMd();
    String when(DateTime time) =>
        time == DateTime(time.year, time.month, time.day)
        ? date.format(time)
        : '${date.format(time)}, ${DateFormat.jm().format(time)}';
    final desktop = !isMobileOS;

    return Material(
      color: Palette.panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: Styles.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.guild?.guild.name ?? 'Direct messages',
                        style: Styles.small,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded, color: Palette.muted),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                const SectionLabel('Format'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final format in ExportFormat.values)
                      _Choice(
                        label: format.label,
                        selected: options.format == format,
                        onTap: () => _set(options.copyWith(format: format)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionLabel('Messages'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Choice(
                      label: 'Everything',
                      selected: !options.pinnedOnly,
                      onTap: () => _set(options.copyWith(pinnedOnly: false)),
                    ),
                    _Choice(
                      label: 'Pinned only',
                      selected: options.pinnedOnly,
                      onTap: () => _set(options.copyWith(pinnedOnly: true)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionLabel('Date range'),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _DateButton(
                          label: 'After',
                          value: options.after == null
                              ? 'From the start'
                              : when(options.after!),
                          onTap: () => _pickDate(after: true),
                          onClear: options.after == null
                              ? null
                              : () => _set(options.copyWith(after: () => null)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DateButton(
                          label: 'Before',
                          value: options.before == null
                              ? 'Up to now'
                              : when(options.before!),
                          onTap: () => _pickDate(after: false),
                          onClear: options.before == null
                              ? null
                              : () =>
                                    _set(options.copyWith(before: () => null)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Messages per file'),
                TextField(
                  controller: _partition,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    hintText: 'Leave empty to keep everything in one file',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Big exports open faster in a browser when split into parts of a few thousand messages.',
                  style: Styles.tiny,
                ),
                const SizedBox(height: 20),
                const SectionLabel('Attachments'),
                _RadioCard(
                  title: MediaMode.links.label,
                  subtitle: 'Discord links stop working after about a day.',
                  selected: options.mediaMode == MediaMode.links,
                  onTap: () =>
                      _set(options.copyWith(mediaMode: MediaMode.links)),
                ),
                _RadioCard(
                  title: MediaMode.local.label,
                  subtitle: 'Downloads every file into a folder beside the export so it works offline.',
                  selected: options.mediaMode == MediaMode.local,
                  onTap: () =>
                      _set(options.copyWith(mediaMode: MediaMode.local)),
                ),
                _RadioCard(
                  title: MediaMode.rehost.label,
                  subtitle: providers.isEmpty
                      ? 'Add Catbox, ImgBB, S3 or a ShareX uploader in Settings first.'
                      : providers.length == 1
                      ? 'Uploads to ${providers.first.name}.'
                      : 'Tries ${providers.map((p) => p.name).join(', then ')}.',
                  selected: options.mediaMode == MediaMode.rehost,
                  onTap: providers.isEmpty
                      ? null
                      : () =>
                            _set(options.copyWith(mediaMode: MediaMode.rehost)),
                ),
                if (options.mediaMode == MediaMode.rehost)
                  _ToggleRow(
                    title: 'Also keep a local copy',
                    subtitle: 'Used for files no host accepts, and kept next to the export.',
                    value: options.keepLocalCopy,
                    onChanged: (v) => _set(options.copyWith(keepLocalCopy: v)),
                  ),
                if (threads) ...[
                  const SizedBox(height: 12),
                  _ToggleRow(
                    title: 'Include threads',
                    subtitle: 'Active and archived threads are queued as their own exports.',
                    value: options.includeThreads,
                    onChanged: (v) => _set(options.copyWith(includeThreads: v)),
                  ),
                ],
                _ToggleRow(
                  title: 'Show times in UTC',
                  subtitle: 'Otherwise times use this device\'s time zone.',
                  value: options.useUtc,
                  onChanged: (v) => _set(options.copyWith(useUtc: v)),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Save to'),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: Styles.inset,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_outlined,
                        size: 20,
                        color: Palette.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          options.outputDir,
                          style: Styles.small,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (desktop)
                        DiscordButton(
                          label: 'Change',
                          tone: ButtonTone.secondary,
                          dense: true,
                          onPressed: _pickFolder,
                        ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Palette.red),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Palette.divider)),
            ),
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  const Spacer(),
                  DiscordButton(
                    label: 'Cancel',
                    tone: ButtonTone.link,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  DiscordButton(
                    label: 'Export',
                    icon: Icons.download_rounded,
                    busy: _busy,
                    onPressed: _start,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? Palette.blurple : Palette.hover,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Palette.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.input,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: Palette.selected),
    ),
    child: InkWell(
      onTap: onTap,
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Styles.tiny),
                  Text(
                    value,
                    style: const TextStyle(color: Palette.text, fontSize: 15),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Palette.muted,
                ),
                tooltip: 'Clear',
              )
            else
              const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: Palette.muted,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: selected ? Palette.selected : Palette.hover,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Palette.divider),
        ),
        child: InkWell(
          onTap: onTap,
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? Palette.header : Palette.muted,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Palette.header,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: Styles.small),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Palette.header,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(subtitle, style: Styles.small),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}
