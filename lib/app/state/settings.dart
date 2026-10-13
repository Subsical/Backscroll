import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/discord/api.dart';
import '../../core/discord/models.dart';
import '../../core/export/options.dart';
import '../../core/media/providers/registry.dart';
import '../../core/util/files.dart';

class AccountInfo {
  AccountInfo({
    required this.id,
    required this.kind,
    required this.username,
    this.globalName,
    this.avatar,
    this.discriminator = '0',
  });

  factory AccountInfo.fromUser(DiscordUser user, TokenKind kind) => AccountInfo(
    id: user.id,
    kind: kind,
    username: user.username,
    globalName: user.globalName,
    avatar: user.avatar,
    discriminator: user.discriminator,
  );

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
    id: json['id'] as String,
    kind: TokenKind.values.byName(json['kind'] as String),
    username: json['username'] as String,
    globalName: json['globalName'] as String?,
    avatar: json['avatar'] as String?,
    discriminator: json['discriminator'] as String? ?? '0',
  );

  final String id;
  final TokenKind kind;
  final String username;
  final String? globalName;
  final String? avatar;
  final String discriminator;

  DiscordUser get user => DiscordUser(
    id: id,
    username: username,
    globalName: globalName,
    avatar: avatar,
    discriminator: discriminator,
    bot: kind == TokenKind.bot,
  );

  String get displayName => user.displayName;
  String get tokenKey => 'token.$id';

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'username': username,
    'globalName': globalName,
    'avatar': avatar,
    'discriminator': discriminator,
  };
}

class ExportDefaults {
  ExportFormat format = ExportFormat.htmlDark;
  int partitionSize = 10000;
  MediaMode? mediaMode;
  bool keepLocalCopy = false;
  bool includeThreads = true;
  bool useUtc = false;
  String? outputDir;

  void read(Map<String, dynamic> json) {
    format = ExportFormat.values.asNameMap()[json['format']] ?? format;
    partitionSize = json['partitionSize'] as int? ?? partitionSize;
    mediaMode = MediaMode.values.asNameMap()[json['mediaMode']];
    keepLocalCopy = json['keepLocalCopy'] == true;
    includeThreads = json['includeThreads'] != false;
    useUtc = json['useUtc'] == true;
    outputDir = json['outputDir'] as String?;
  }

  Map<String, dynamic> toJson() => {
    'format': format.name,
    'partitionSize': partitionSize,
    'mediaMode': mediaMode?.name,
    'keepLocalCopy': keepLocalCopy,
    'includeThreads': includeThreads,
    'useUtc': useUtc,
    'outputDir': outputDir,
  };
}

class AppSettings extends ChangeNotifier {
  AppSettings(this._file);

  final File? _file;
  final accounts = <AccountInfo>[];
  String? activeAccountId;
  final defaults = ExportDefaults();
  final providers = <ProviderConfig>[];
  int? maxUploadMb;
  final notices = <String>{};

  AccountInfo? get activeAccount =>
      accounts.where((a) => a.id == activeAccountId).firstOrNull;

  List<ProviderConfig> get enabledProviders =>
      providers.where((p) => p.enabled).toList();

  MediaMode get defaultMediaMode =>
      defaults.mediaMode ??
      (enabledProviders.isEmpty ? MediaMode.links : MediaMode.rehost);

  Future<void> load() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      accounts
        ..clear()
        ..addAll(
          ((json['accounts'] as List?) ?? const []).map(
            (a) => AccountInfo.fromJson(a as Map<String, dynamic>),
          ),
        );
      activeAccountId = json['activeAccountId'] as String?;
      defaults.read((json['defaults'] as Map<String, dynamic>?) ?? const {});
      providers
        ..clear()
        ..addAll(
          ((json['providers'] as List?) ?? const []).map(
            (p) => ProviderConfig.fromJson(p as Map<String, dynamic>),
          ),
        );
      maxUploadMb = json['maxUploadMb'] as int?;
      notices
        ..clear()
        ..addAll(((json['notices'] as List?) ?? const []).cast<String>());
    } on FormatException {
      return;
    }
  }

  Future<void> save() async {
    notifyListeners();
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await writeAtomic(
      file,
      jsonEncode({
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'activeAccountId': activeAccountId,
        'defaults': defaults.toJson(),
        'providers': providers.map((p) => p.toJson()).toList(),
        'maxUploadMb': maxUploadMb,
        'notices': notices.toList(),
      }),
    );
  }
}
