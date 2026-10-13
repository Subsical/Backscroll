import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/smooth_wheel.dart';

Future<void> main(List<String> args) async {
  AppBinding.ensureInitialized();
  // second engine for the login window's title bar
  if (runWebViewTitleBarWidget(args)) return;
  if (Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
    // android 15 already does this on its own
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  runApp(BackscrollApp(services: await bootstrap()));
}
