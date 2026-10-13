import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/discord/api.dart';
import '../services/secrets.dart';
import 'settings.dart';

class Session extends ChangeNotifier {
  Session({required this.settings, required this.secrets, this.httpClient});

  final AppSettings settings;
  final SecretStore secrets;
  final http.Client Function()? httpClient;
  final _apis = <String, DiscordApi>{};
  bool restored = false;

  AccountInfo? get account => settings.activeAccount;
  DiscordApi? get api => account == null ? null : _apis[account!.id];
  bool get isBot => account?.kind == TokenKind.bot;
  bool get signedIn => api != null;

  Future<void> restore() async {
    final active = account;
    if (active != null) await _connect(active);
    restored = true;
    notifyListeners();
  }

  Future<DiscordApi?> _connect(AccountInfo info) async {
    final existing = _apis[info.id];
    if (existing != null) return existing;
    final token = await secrets.read(info.tokenKey);
    if (token == null || token.isEmpty) return null;
    return _apis[info.id] = DiscordApi(
      token,
      info.kind,
      client: httpClient?.call(),
    );
  }

  Future<DiscordApi?> apiFor(String accountId) async {
    final info = settings.accounts.where((a) => a.id == accountId).firstOrNull;
    return info == null ? null : _connect(info);
  }

  Future<AccountInfo> signIn(String rawToken) async {
    final (kind, user) = await DiscordApi.identify(
      rawToken,
      client: httpClient?.call(),
    );
    final info = AccountInfo.fromUser(user, kind);
    await secrets.write(info.tokenKey, DiscordApi.cleanToken(rawToken));
    _apis.remove(info.id)?.close();
    settings.accounts
      ..removeWhere((a) => a.id == info.id)
      ..add(info);
    settings.activeAccountId = info.id;
    await settings.save();
    await _connect(info);
    notifyListeners();
    return info;
  }

  Future<void> switchTo(AccountInfo info) async {
    settings.activeAccountId = info.id;
    await settings.save();
    await _connect(info);
    notifyListeners();
  }

  // never call discord's logout here, it kills the token everywhere
  Future<void> forget(AccountInfo info) async {
    await secrets.delete(info.tokenKey);
    _apis.remove(info.id)?.close();
    settings.accounts.removeWhere((a) => a.id == info.id);
    if (settings.activeAccountId == info.id) {
      settings.activeAccountId = settings.accounts.firstOrNull?.id;
    }
    await settings.save();
    final next = account;
    if (next != null) await _connect(next);
    notifyListeners();
  }
}
