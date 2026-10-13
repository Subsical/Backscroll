import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:backscroll/app/app.dart';
import 'package:backscroll/app/scope.dart';
import 'package:backscroll/app/services/paths.dart';
import 'package:backscroll/app/services/secrets.dart';
import 'package:backscroll/app/state/exports.dart';
import 'package:backscroll/app/state/library.dart';
import 'package:backscroll/app/state/session.dart';
import 'package:backscroll/app/state/settings.dart';
import 'package:backscroll/core/discord/api.dart';
import 'package:backscroll/core/discord/models.dart';
import 'package:backscroll/core/export/writers/writer.dart';
import 'package:backscroll/core/media/upload_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;

import 'sample_world.dart';

final screenshotDir = Platform.environment['SCREENSHOTS'];
final _twemojiDir = Platform.environment['TWEMOJI_DIR'];

Future<void> loadFonts() async {
  Future<ByteData> bytes(File file) async =>
      ByteData.sublistView(await file.readAsBytes());

  final figtree = FontLoader('Figtree');
  for (final file in Directory('assets/fonts').listSync().whereType<File>()) {
    if (file.path.endsWith('.ttf')) figtree.addFont(bytes(file));
  }
  await figtree.load();

  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final icons = File(
    p.join(artifacts.path, 'material_fonts', 'MaterialIcons-Regular.otf'),
  );
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(bytes(icons))).load();
  }
  final mono = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    r'C:\Windows\Fonts\consola.ttf',
  ].map(File.new).where((file) => file.existsSync()).firstOrNull;
  if (mono != null) {
    await (FontLoader('monospace')..addFont(bytes(mono))).load();
  }
  await initializeDateFormatting('en_US');
}

final _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class SampleImages {
  SampleImages(this._bytes);

  final Map<String, Uint8List> _bytes;
  final _providers = <String, ImageProvider>{};
  final missing = <String>{};

  ImageProvider resolve(String url) {
    final uri = Uri.parse(url);
    final key = uri.host == 'cdn.jsdelivr.net'
        ? 'twemoji/${uri.pathSegments.last}'
        : uri.path;
    return _providers[key] ??= MemoryImage(_load(key, url));
  }

  Uint8List _load(String key, String url) {
    final twemoji = _twemojiDir;
    if (key.startsWith('twemoji/') && twemoji != null) {
      final file = File(p.join(twemoji, key.substring(8)));
      if (file.existsSync()) return file.readAsBytesSync();
    }
    final bytes = _bytes[key];
    if (bytes != null) return bytes;
    missing.add(url);
    return _transparentPng;
  }
}

// answers like a slow S3 bucket: nothing exists yet and every PUT trickles in
http.Client fakeBucket({required int bytesPerSecond}) =>
    MockClient.streaming((request, body) async {
      if (request.method == 'HEAD') {
        await body.drain<void>();
        return http.StreamedResponse(const Stream.empty(), 404);
      }
      await for (final chunk in body) {
        await Future<void>.delayed(
          Duration(microseconds: chunk.length * 1000000 ~/ bytesPerSecond),
        );
      }
      return http.StreamedResponse(
        const Stream.empty(),
        200,
        headers: {'etag': '"5d41402abc4b2a76b9719d911017c592"'},
      );
    });

class AppHarness {
  AppHarness._(this.world, this.images, this.services, this.dir);

  final SampleWorld world;
  final SampleImages images;
  final AppServices services;
  final Directory dir;
  final key = GlobalKey();

  Library get library => services.library;
  ExportsController get exports => services.exports;

  static Future<AppHarness> create({
    required bool bot,
    bool signedIn = true,
    SampleWorld? world,
    void Function(AppSettings settings)? configure,
    Map<String, Map<String, String>> providerSecrets = const {},
    int uploadBytesPerSecond = 50000,
  }) async {
    world ??= SampleWorld()..build();
    final images = SampleImages(await world.images());
    final dir = await Directory.systemTemp.createTemp('backscroll-shots');
    final paths = AppPaths(
      support: p.join(dir.path, 'support'),
      cache: p.join(dir.path, 'cache'),
      defaultExports: p.join(dir.path, 'exports'),
    );
    final secrets = MemorySecretStore();
    final settings = AppSettings(null);
    final account = AccountInfo.fromUser(
      DiscordUser.fromJson(bot ? world.buildbot : world.sam),
      bot ? TokenKind.bot : TokenKind.user,
    );
    if (signedIn) {
      settings.accounts.add(account);
      settings.activeAccountId = account.id;
      await secrets.write(account.tokenKey, 'sample-token');
    }
    configure?.call(settings);
    for (final entry in providerSecrets.entries) {
      await secrets.writeMap('provider.${entry.key}', entry.value);
    }
    final session = Session(
      settings: settings,
      secrets: secrets,
      httpClient: world.apiClient,
    );
    final library = Library(session);
    final cdnImages = await world.images();
    final exports = ExportsController(
      paths: paths,
      settings: settings,
      secrets: secrets,
      session: session,
      assets: ExportAssets(
        fontRegular: base64Encode(
          File('assets/export/figtree.woff2').readAsBytesSync(),
        ),
        fontItalic: base64Encode(
          File('assets/export/figtree-italic.woff2').readAsBytesSync(),
        ),
      ),
      cdnClient: () => world!.cdnClient(cdnImages),
      uploadClient: () => fakeBucket(bytesPerSecond: uploadBytesPerSecond),
      locale: 'en_US',
      cache: UploadCache.memory(),
    );
    await exports.init();
    await session.restore();
    final services = AppServices(
      paths: paths,
      secrets: secrets,
      settings: settings,
      session: session,
      library: library,
      exports: exports,
      images: images.resolve,
      locale: 'en_US',
    );
    return AppHarness._(world, images, services, dir);
  }

  Widget get app => RepaintBoundary(
    key: key,
    child: BackscrollApp(services: services),
  );

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
  }

  // an export started by a tap runs on the test's fake clock, so it only
  // gets anywhere while frames are pumped
  Future<void> waitForExports(WidgetTester tester) async {
    await waitFor(
      tester,
      () => exports.jobs.isNotEmpty && !exports.queue.isBusy,
    );
    var saved = false;
    unawaited(exports.queue.waitForUploads().whenComplete(() => saved = true));
    await waitFor(tester, () => saved);
  }

  Future<void> settle(WidgetTester tester, {int frames = 12}) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    for (var round = 0; round < 2; round++) {
      final elements = find
          .byType(Image, skipOffstage: false)
          .evaluate()
          .toList();
      await tester.runAsync(
        () => Future.wait([
          for (final e in elements) precacheImage((e.widget as Image).image, e),
        ]),
      );
      await tester.pump();
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final out = screenshotDir;
    if (out == null) return;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File(p.join(out, '$name.png'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    });
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final job in exports.jobs.where((j) => j.isActive).toList()) {
        await exports.queue.cancel(job);
      }
      while (exports.queue.isBusy) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await exports.queue.waitForUploads();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    if (images.missing.isNotEmpty) {
      debugPrint('Missing sample images:\n${images.missing.join('\n')}');
    }
    await tester.runAsync(() async {
      for (var attempt = 0; ; attempt++) {
        try {
          return await dir.delete(recursive: true);
        } on FileSystemException {
          if (attempt == 5) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    });
  }
}
