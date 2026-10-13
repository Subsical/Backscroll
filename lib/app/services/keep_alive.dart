import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../theme.dart';

@pragma('vm:entry-point')
void startKeepAliveTask() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

// only keeps the process alive, the export runs in the main isolate
class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class KeepAlive {
  bool _active = false;
  bool _initialized = false;
  String _lastText = '';

  bool get _android => Platform.isAndroid;

  Future<void> _init() async {
    if (_initialized || !_android) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'exports',
        channelName: 'Exports',
        channelDescription: 'Shown while an export is running',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  Future<void> update({required bool busy, required String text}) async {
    if (busy && !_active) {
      _active = true;
      _lastText = text;
      try {
        await WakelockPlus.enable();
      } on Exception {
        // no idle inhibitor on some desktops
      }
      if (_android) {
        await _init();
        await FlutterForegroundTask.startService(
          serviceId: 4100,
          notificationTitle: 'Backscroll is exporting',
          notificationText: text,
          notificationIcon: const NotificationIcon(
            metaDataName: 'io.github.subsical.backscroll.NOTIFICATION_ICON',
            backgroundColor: Palette.blurple,
          ),
          callback: startKeepAliveTask,
        );
      }
    } else if (!busy && _active) {
      _active = false;
      try {
        await WakelockPlus.disable();
      } on Exception {
        // same
      }
      if (_android) await FlutterForegroundTask.stopService();
    } else if (busy && _android && text != _lastText) {
      _lastText = text;
      await FlutterForegroundTask.updateService(notificationText: text);
    }
  }
}
