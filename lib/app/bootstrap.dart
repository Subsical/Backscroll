import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../core/export/writers/writer.dart';
import 'scope.dart';
import 'services/keep_alive.dart';
import 'services/paths.dart';
import 'services/secrets.dart';
import 'state/exports.dart';
import 'state/library.dart';
import 'state/session.dart';
import 'state/settings.dart';

String systemLocale() {
  final tag = PlatformDispatcher.instance.locale.toLanguageTag();
  final canonical = Intl.canonicalizedLocale(tag);
  if (DateFormat.localeExists(canonical)) return canonical;
  final language = canonical.split('_').first;
  return DateFormat.localeExists(language) ? language : 'en_US';
}

Future<ExportAssets> loadExportAssets() async {
  Future<String> font(String name) async => base64Encode(
    (await rootBundle.load('assets/export/$name')).buffer.asUint8List(),
  );
  return ExportAssets(
    fontRegular: await font('figtree.woff2'),
    fontItalic: await font('figtree-italic.woff2'),
  );
}

Future<AppServices> bootstrap() async {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Figtree',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  await initializeDateFormatting();
  final locale = systemLocale();
  final paths = await AppPaths.resolve();
  final secrets = SecretStore();
  final settings = AppSettings(File(paths.settings));
  await settings.load();
  final session = Session(settings: settings, secrets: secrets);
  final library = Library(session);
  final exports = ExportsController(
    paths: paths,
    settings: settings,
    secrets: secrets,
    session: session,
    assets: await loadExportAssets(),
    keepAlive: KeepAlive(),
    locale: locale,
  );
  await exports.init();
  await session.restore();
  return AppServices(
    paths: paths,
    secrets: secrets,
    settings: settings,
    session: session,
    library: library,
    exports: exports,
    locale: locale,
  );
}
