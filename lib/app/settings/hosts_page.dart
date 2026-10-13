import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/media/providers/registry.dart';
import '../../core/media/providers/sharex.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'provider_editor.dart';

Future<void> maybeShowPublicNotice(
  BuildContext context,
  ProviderConfig config,
) async {
  final settings = AppScope.of(context).settings;
  if (!config.enabled ||
      !config.isPublicHost ||
      settings.notices.contains('public-host')) {
    return;
  }
  settings.notices.add('public-host');
  await settings.save();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Before you upload', style: Styles.title),
      content: Text(
        'Files on ${config.name} are public: anyone with a link can open them.',
        style: Styles.body,
      ),
      actions: [
        DiscordButton(label: 'Got it', onPressed: () => Navigator.pop(context)),
      ],
    ),
  );
}

IconData providerIcon(ProviderKind kind) => switch (kind) {
  ProviderKind.catbox => Icons.pets_rounded,
  ProviderKind.imgbb => Icons.image_outlined,
  ProviderKind.s3 => Icons.storage_rounded,
  ProviderKind.sharex => Icons.extension_outlined,
};

class HostsPage extends StatefulWidget {
  const HostsPage({super.key});

  @override
  State<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends State<HostsPage> {
  late final _maxSize = TextEditingController(
    text: AppScope.of(context).settings.maxUploadMb?.toString() ?? '',
  );

  @override
  void dispose() {
    _maxSize.dispose();
    super.dispose();
  }

  Future<void> _add(ProviderKind kind) async {
    String? sxcu;
    if (kind == ProviderKind.sharex) {
      sxcu = await _pickSxcu();
      if (sxcu == null) return;
    }
    if (!mounted) return;
    final saved = await editProvider(context, kind: kind, sxcu: sxcu);
    if (saved != null && mounted) await maybeShowPublicNotice(context, saved);
  }

  Future<String?> _pickSxcu() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Pick a ShareX uploader (.sxcu)',
    );
    if (file == null) return null;
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    try {
      ShareXConfig.parse(text);
      return text;
    } on FormatException catch (e) {
      if (mounted) showToast(context, e.message);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final settings = services.settings;
    final exports = services.exports;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, exports]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const Text(
            'Discord attachment links stop working about a day after they are fetched. '
            'When you re-host, each file goes to the first host below that accepts it, '
            'so drag them into the order you want. Credentials stay in the keychain.',
            style: Styles.small,
          ),
          const SizedBox(height: 16),
          if (settings.providers.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: Styles.card,
              child: const Text(
                'No hosts yet. Exports keep the Discord links until you add one.',
                style: Styles.small,
              ),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) {
                settings.providers.insert(
                  to,
                  settings.providers.removeAt(from),
                );
                settings.save();
              },
              children: [
                for (var i = 0; i < settings.providers.length; i++)
                  _ProviderTile(
                    key: ValueKey(settings.providers[i].id),
                    index: i,
                    config: settings.providers[i],
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<ProviderKind>(
              tooltip: 'Add a host',
              popUpAnimationStyle: AnimationStyle.noAnimation,
              onSelected: _add,
              itemBuilder: (_) => [
                for (final kind in ProviderKind.values)
                  PopupMenuItem(
                    value: kind,
                    child: Row(
                      children: [
                        Icon(
                          providerIcon(kind),
                          size: 18,
                          color: Palette.muted,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          kind == ProviderKind.sharex
                              ? 'Import a ShareX uploader (.sxcu)'
                              : kind.label,
                        ),
                      ],
                    ),
                  ),
              ],
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: IgnorePointer(
                  child: DiscordButton(
                    label: 'Add a host',
                    icon: Icons.add_rounded,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const SectionLabel('Largest file to upload (MB)'),
          TextField(
            controller: _maxSize,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(hintText: 'No limit'),
            onChanged: (v) {
              settings.maxUploadMb = int.tryParse(v);
              settings.save();
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'Bigger files keep their Discord link, or the local copy if you keep one.',
            style: Styles.tiny,
          ),
          const SizedBox(height: 28),
          const SectionLabel('Upload cache'),
          Row(
            children: [
              Expanded(
                child: Text(switch (exports.cache.hostedCount) {
                  0 =>
                    'Nothing uploaded yet. Uploaded files are remembered, so '
                        'exporting the same attachments again reuses their links.',
                  1 =>
                    '1 uploaded file is remembered, so exporting it again '
                        'reuses its link.',
                  final n =>
                    '$n uploaded files are remembered, so exporting the same '
                        'attachments again reuses their links.',
                }, style: Styles.small),
              ),
              const SizedBox(width: 12),
              DiscordButton(
                label: 'Clear',
                tone: ButtonTone.secondary,
                dense: true,
                onPressed: () {
                  exports.cache.clearHosted();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({super.key, required this.index, required this.config});

  final int index;
  final ProviderConfig config;

  @override
  Widget build(BuildContext context) {
    final exports = AppScope.of(context).exports;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: Styles.card,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_indicator_rounded, color: Palette.faint),
            ),
          ),
          Icon(providerIcon(config.kind), color: Palette.blurple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.name,
                  style: const TextStyle(
                    color: Palette.header,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    if (config.name != config.kind.label) config.kind.label,
                    config.limitSummary,
                  ].join(' · '),
                  style: Styles.tiny,
                ),
              ],
            ),
          ),
          Switch(
            value: config.enabled,
            onChanged: (value) async {
              config.enabled = value;
              await exports.settings.save();
              if (value && context.mounted) {
                await maybeShowPublicNotice(context, config);
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Palette.muted),
            popUpAnimationStyle: AnimationStyle.noAnimation,
            onSelected: (value) async {
              if (value == 'edit') {
                await editProvider(context, existing: config);
              } else {
                await exports.removeProvider(config);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'remove',
                child: Text('Remove', style: TextStyle(color: Palette.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
