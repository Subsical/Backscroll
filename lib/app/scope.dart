import 'package:flutter/widgets.dart';

import 'services/paths.dart';
import 'services/secrets.dart';
import 'state/exports.dart';
import 'state/library.dart';
import 'state/session.dart';
import 'state/settings.dart';

typedef ImageResolver = ImageProvider Function(String url);

ImageProvider networkImage(String url) => NetworkImage(url);

class AppServices {
  AppServices({
    required this.paths,
    required this.secrets,
    required this.settings,
    required this.session,
    required this.library,
    required this.exports,
    this.images = networkImage,
    this.webviewLogin = true,
    this.locale,
  });

  final AppPaths paths;
  final SecretStore secrets;
  final AppSettings settings;
  final Session session;
  final Library library;
  final ExportsController exports;
  final ImageResolver images;
  final bool webviewLogin;
  final String? locale;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
