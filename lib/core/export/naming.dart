import '../discord/models.dart';

final _invalid = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
final _reserved = RegExp(
  r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$',
  caseSensitive: false,
);

String sanitizeFileName(String name, {int maxLength = 140}) {
  var result = name.replaceAll(_invalid, '_').replaceAll(RegExp(r'\s+'), ' ');
  result = result.trim().replaceAll(RegExp(r'[. ]+$'), '');
  final runes = result.runes.toList();
  if (runes.length > maxLength) {
    result = String.fromCharCodes(runes.take(maxLength)).trimRight();
  }
  if (result.isEmpty) return '_';
  return _reserved.hasMatch(result) ? '_$result' : result;
}

String _day(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String exportBaseName({
  required Channel channel,
  Guild? guild,
  String? category,
  String? parentName,
  DateTime? after,
  DateTime? before,
  bool pinnedOnly = false,
}) {
  final names = <String>[
    if (channel.isPrivate) 'Direct Messages' else guild?.name ?? 'Server',
    if (!channel.isPrivate && parentName != null)
      parentName
    else if (!channel.isPrivate && category != null)
      category,
  ];
  // The channel name gets most of the length budget; the server and
  // category parts are trimmed first.
  final prefix = names
      .map((n) => sanitizeFileName(n, maxLength: 40))
      .join(' - ');
  final title = sanitizeFileName(channel.displayName, maxLength: 60);
  var name = '$prefix - $title [${channel.id}]';
  if (pinnedOnly) name += ' (pinned)';
  if (after != null || before != null) {
    name +=
        ' (${after == null ? 'start' : _day(after)} to '
        '${before == null ? 'now' : _day(before)})';
  }
  return sanitizeFileName(name, maxLength: 200);
}

String partFileName(String baseName, int part, String extension) =>
    part <= 1 ? '$baseName.$extension' : '$baseName [part $part].$extension';

String mediaDirName(String baseName) => '${baseName}_files';
