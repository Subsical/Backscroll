import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _storage = MethodChannel('backscroll/storage');

Future<bool> showInFileManager(String folder, {String? file}) async {
  try {
    if (Platform.isAndroid) {
      return await _storage.invokeMethod<bool>('openFolder', {
            'path': folder,
          }) ??
          false;
    }
    if (file != null) {
      if (Platform.isWindows) {
        // explorer returns 1 even on success
        await Process.run('explorer.exe', ['/select,', file]);
        return true;
      }
      if (Platform.isLinux && await _showItemOnLinux(file)) return true;
    }
    return await launchUrl(Uri.directory(folder));
  } on Exception {
    return false;
  }
}

// dbus-send splits arrays on commas, hence the %2C
Future<bool> _showItemOnLinux(String file) async {
  try {
    final result = await Process.run('dbus-send', [
      '--session',
      '--print-reply',
      '--reply-timeout=5000',
      '--dest=org.freedesktop.FileManager1',
      '--type=method_call',
      '/org/freedesktop/FileManager1',
      'org.freedesktop.FileManager1.ShowItems',
      'array:string:${Uri.file(file).toString().replaceAll(',', '%2C')}',
      'string:',
    ]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
