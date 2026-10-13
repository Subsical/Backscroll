import 'package:flutter/material.dart';

import '../../core/export/job.dart';
import '../../core/media/providers/registry.dart';
import '../../core/media/providers/s3.dart';
import '../../core/media/providers/sharex.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<ProviderConfig?> editProvider(
  BuildContext context, {
  ProviderKind? kind,
  ProviderConfig? existing,
  String? sxcu,
}) {
  final editor = ProviderEditor(
    kind: existing?.kind ?? kind!,
    existing: existing,
    sxcu: sxcu,
  );
  if (isCompact(context)) {
    return Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => editor));
  }
  return showDialog<ProviderConfig>(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: editor,
      ),
    ),
  );
}

class ProviderEditor extends StatefulWidget {
  const ProviderEditor({
    super.key,
    required this.kind,
    this.existing,
    this.sxcu,
  });

  final ProviderKind kind;
  final ProviderConfig? existing;
  final String? sxcu;

  @override
  State<ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<ProviderEditor> {
  final _fields = <String, TextEditingController>{};
  late double _concurrency;
  bool _pathStyle = true;
  String? _error;
  String? _sxcu;
  ShareXConfig? _parsed;

  ProviderConfig? get existing => widget.existing;

  TextEditingController _field(String key, [String initial = '']) =>
      _fields.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fields.isNotEmpty) return;
    final config = existing;
    final secrets = config == null
        ? <String, String>{}
        : AppScope.of(context).exports.providerSecrets(config.id);
    final settings = config?.settings ?? const {};
    _sxcu = widget.sxcu ?? secrets['sxcu'];
    if (_sxcu != null) _parsed = ShareXConfig.parse(_sxcu!);
    _field('name', config?.name ?? (_parsed?.name ?? widget.kind.label));
    _field(
      'maxMb',
      config?.maxBytes == null ? '' : '${config!.maxBytes! ~/ 1048576}',
    );
    _field('userhash', secrets['userhash'] ?? '');
    _field('apiKey', secrets['apiKey'] ?? '');
    _field('accessKey', secrets['accessKey'] ?? '');
    _field('secretKey', secrets['secretKey'] ?? '');
    for (final key in ['endpoint', 'region', 'bucket', 'publicUrl', 'prefix']) {
      _field(key, settings[key] ?? '');
    }
    _pathStyle = settings['pathStyle'] != 'false';
    final probe = ProviderConfig(id: '', kind: widget.kind, name: '');
    _concurrency = (config?.concurrency ?? probe.defaultConcurrency).toDouble();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _fields[key]!.text.trim();

  Future<void> _save() async {
    final exports = AppScope.of(context).exports;
    final kind = widget.kind;
    final secrets = <String, String>{};
    final settings = <String, String>{};
    switch (kind) {
      case ProviderKind.catbox:
        if (_text('userhash').isNotEmpty) {
          secrets['userhash'] = _text('userhash');
        }
      case ProviderKind.imgbb:
        if (_text('apiKey').isEmpty) {
          return setState(() => _error = 'Enter your ImgBB API key');
        }
        secrets['apiKey'] = _text('apiKey');
      case ProviderKind.s3:
        final s3 = S3Settings(
          endpoint: _text('endpoint'),
          bucket: _text('bucket'),
          region: _text('region'),
          prefix: _text('prefix'),
          publicBaseUrl: _text('publicUrl'),
          accessKey: _text('accessKey'),
          secretKey: _text('secretKey'),
          pathStyle: _pathStyle,
        );
        final problem = s3.problem();
        if (problem != null) return setState(() => _error = problem);
        for (final key in [
          'endpoint',
          'region',
          'bucket',
          'publicUrl',
          'prefix',
        ]) {
          settings[key] = _text(key);
        }
        settings['pathStyle'] = '$_pathStyle';
        secrets['accessKey'] = _text('accessKey');
        secrets['secretKey'] = _text('secretKey');
      case ProviderKind.sharex:
        if (_sxcu == null) {
          return setState(() => _error = 'Import a .sxcu file first');
        }
        secrets['sxcu'] = _sxcu!;
        settings['host'] = _parsed?.host ?? '';
    }
    final maxMb = int.tryParse(_text('maxMb'));
    final config = ProviderConfig(
      id: existing?.id ?? newId(),
      kind: kind,
      name: _text('name').isEmpty ? kind.label : _text('name'),
      enabled: existing?.enabled ?? true,
      concurrency: _concurrency.round(),
      maxBytes: maxMb == null ? null : maxMb * 1024 * 1024,
      settings: settings,
    );
    await exports.saveProvider(config, secrets);
    if (mounted) Navigator.of(context).pop(config);
  }

  Widget _input(
    String key,
    String label, {
    String? hint,
    bool secret = false,
    String? help,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label, padding: const EdgeInsets.only(bottom: 6)),
        TextField(
          controller: _field(key),
          obscureText: secret,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(hintText: hint),
        ),
        if (help != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(help, style: Styles.tiny),
          ),
      ],
    ),
  );

  List<Widget> _kindFields() => switch (widget.kind) {
    ProviderKind.catbox => [
      _input(
        'userhash',
        'Userhash',
        hint: 'Optional',
        secret: true,
        help: 'With a userhash, uploads show up in your Catbox account so you can delete them later.',
      ),
    ],
    ProviderKind.imgbb => [
      _input(
        'apiKey',
        'API key',
        secret: true,
        help:
            'Get a key at api.imgbb.com. ImgBB only takes images up to 32 MB.',
      ),
    ],
    ProviderKind.s3 => [
      _input(
        'endpoint',
        'Endpoint',
        hint: 'https://<account>.r2.cloudflarestorage.com',
      ),
      _input('bucket', 'Bucket'),
      _input(
        'region',
        'Region',
        hint: _fields['endpoint']?.text.isNotEmpty == true
            ? S3Settings.guessRegion(_fields['endpoint']!.text)
            : 'Worked out from the endpoint',
      ),
      _input('accessKey', 'Access key ID', secret: true),
      _input('secretKey', 'Secret access key', secret: true),
      _input(
        'publicUrl',
        'Public base URL',
        hint: 'https://files.example.com',
        help: 'The address files are served from, like an R2 custom domain or a B2 friendly URL.',
      ),
      _input(
        'prefix',
        'Folder in the bucket',
        hint: 'Optional, for example discord/',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Path style addresses',
          style: TextStyle(color: Palette.header),
        ),
        subtitle: const Text(
          'Turn off for hosts that need bucket.endpoint addresses.',
          style: Styles.tiny,
        ),
        value: _pathStyle,
        onChanged: (v) => setState(() => _pathStyle = v),
      ),
    ],
    ProviderKind.sharex => [
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: Styles.card.copyWith(color: Palette.hover),
        child: Text(
          _parsed == null
              ? 'No uploader imported.'
              : 'Uploads to ${_parsed!.host} with ${_parsed!.method} '
                    '(${_parsed!.body == 'Binary' ? 'raw body' : 'form upload'}). '
                    '${_parsed!.imagesOnly ? 'Images only.' : 'Any file type.'}',
          style: Styles.small,
        ),
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final probe = ProviderConfig(id: '', kind: widget.kind, name: '');
    return Material(
      color: isCompact(context) ? Palette.chat : Palette.panel,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      existing == null
                          ? 'Add ${widget.kind.label}'
                          : 'Edit ${existing!.name}',
                      style: Styles.title,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Palette.muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  _input('name', 'Name'),
                  ..._kindFields(),
                  _input('maxMb', 'Largest file (MB)', hint: 'No extra limit'),
                  SectionLabel(
                    'Uploads at once: ${_concurrency.round()}',
                    padding: const EdgeInsets.only(top: 4),
                  ),
                  Slider(
                    value: _concurrency,
                    min: 1,
                    max: probe.maxConcurrency.toDouble(),
                    divisions: probe.maxConcurrency - 1,
                    onChanged: (v) => setState(() => _concurrency = v),
                  ),
                  if (widget.kind == ProviderKind.catbox)
                    const Text(
                      'Catbox runs on donations, so please keep this low.',
                      style: Styles.tiny,
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
              child: Row(
                children: [
                  const Spacer(),
                  DiscordButton(
                    label: 'Cancel',
                    tone: ButtonTone.link,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  DiscordButton(label: 'Save', onPressed: _save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
