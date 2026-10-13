import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  AppPaths({
    required this.support,
    required this.cache,
    required this.defaultExports,
  });

  final String support;
  final String cache;
  final String defaultExports;

  static const _storage = MethodChannel('backscroll/storage');

  String get jobs => p.join(support, 'jobs');
  String get settings => p.join(support, 'settings.json');
  String get uploadCache => p.join(support, 'upload-cache.sqlite');
  String get staging => p.join(cache, 'staging');
  String get webviewData => p.join(support, 'login-webview');

  static Future<AppPaths> resolve() async {
    final support = (await getApplicationSupportDirectory()).path;
    final cache = (await getApplicationCacheDirectory()).path;
    return AppPaths(
      support: support,
      cache: cache,
      defaultExports: await _defaultExports(),
    );
  }

  static Future<String> _defaultExports() async {
    if (Platform.isAndroid) {
      final downloads = await _storage.invokeMethod<String>('downloadsDir');
      if (downloads != null) return p.join(downloads, 'Backscroll');
      return p.join(
        (await getApplicationDocumentsDirectory()).path,
        'Backscroll',
      );
    }
    // minimal Linux setups have no XDG user folders at all
    for (final folder in [
      getDownloadsDirectory,
      getApplicationDocumentsDirectory,
    ]) {
      try {
        final dir = await folder();
        if (dir != null) return p.join(dir.path, 'Backscroll');
      } on MissingPlatformDirectoryException {
        continue;
      }
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) return p.join(home, 'Backscroll');
    return p.join((await getApplicationSupportDirectory()).path, 'Exports');
  }

  // Exports land in the shared Downloads folder on Android, which needs the
  // old storage permission up to Android 10.
  static Future<bool> ensureWriteAccess() async {
    if (!Platform.isAndroid) return true;
    return await _storage.invokeMethod<bool>('ensureWriteAccess') ?? false;
  }
}
