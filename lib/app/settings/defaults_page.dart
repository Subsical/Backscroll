import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/export/options.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DefaultsPage extends StatefulWidget {
  const DefaultsPage({super.key});

  @override
  State<DefaultsPage> createState() => _DefaultsPageState();
}

class _DefaultsPageState extends State<DefaultsPage> {
  late final _partition = TextEditingController(
    text: () {
      final size = AppScope.of(context).settings.defaults.partitionSize;
      return size == 0 ? '' : '$size';
    }(),
  );

  @override
  void dispose() {
    _partition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final settings = services.settings;
    final d = settings.defaults;
    final desktop = !isMobileOS;
    void save() => settings.save();

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionLabel('Format'),
          _Dropdown<ExportFormat>(
            value: d.format,
            choices: [for (final f in ExportFormat.values) (f, f.label)],
            onChanged: (f) {
              d.format = f;
              save();
            },
          ),
          const SizedBox(height: 20),
          const SectionLabel('Messages per file'),
          TextField(
            controller: _partition,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: 'Empty means one file per channel',
            ),
            onChanged: (v) {
              d.partitionSize = int.tryParse(v) ?? 0;
              save();
            },
          ),
          const SizedBox(height: 20),
          const SectionLabel('Attachments'),
          _Dropdown<MediaMode?>(
            value: d.mediaMode,
            choices: [
              (null, 'Re-host if a host is set up, else keep links'),
              for (final m in MediaMode.values) (m, m.label),
            ],
            onChanged: (m) {
              d.mediaMode = m;
              save();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Keep a local copy when re-hosting',
              style: TextStyle(color: Palette.header),
            ),
            value: d.keepLocalCopy,
            onChanged: (v) {
              d.keepLocalCopy = v;
              save();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Include threads',
              style: TextStyle(color: Palette.header),
            ),
            value: d.includeThreads,
            onChanged: (v) {
              d.includeThreads = v;
              save();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Show times in UTC',
              style: TextStyle(color: Palette.header),
            ),
            value: d.useUtc,
            onChanged: (v) {
              d.useUtc = v;
              save();
            },
          ),
          const SizedBox(height: 12),
          const SectionLabel('Export folder'),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: Styles.inset,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    d.outputDir ?? services.paths.defaultExports,
                    style: Styles.small,
                  ),
                ),
                if (desktop) ...[
                  if (d.outputDir != null)
                    DiscordButton(
                      label: 'Reset',
                      tone: ButtonTone.link,
                      dense: true,
                      onPressed: () {
                        d.outputDir = null;
                        save();
                      },
                    ),
                  DiscordButton(
                    label: 'Change',
                    tone: ButtonTone.secondary,
                    dense: true,
                    onPressed: () async {
                      final path = await FilePicker.getDirectoryPath(
                        dialogTitle: 'Default export folder',
                      );
                      if (path == null) return;
                      d.outputDir = path;
                      save();
                    },
                  ),
                ],
              ],
            ),
          ),
          if (!desktop)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Exports go to your Downloads folder, where any file manager can open them.',
                style: Styles.small,
              ),
            ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    itemHeight: null,
    mouseCursor: SystemMouseCursors.click,
    dropdownMenuItemMouseCursor: SystemMouseCursors.click,
    dropdownColor: Palette.floating,
    selectedItemBuilder: (context) => [
      for (final (_, label) in choices)
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ],
    items: [
      for (final (choice, label) in choices)
        DropdownMenuItem(value: choice, child: Text(label)),
    ],
    onChanged: (choice) => onChanged(choice as T),
  );
}
