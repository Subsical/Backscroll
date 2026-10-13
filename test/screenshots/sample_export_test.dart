import 'dart:convert';
import 'dart:io';

import 'package:backscroll/core/convert/converter.dart';
import 'package:backscroll/core/discord/api.dart';
import 'package:backscroll/core/discord/models.dart';
import 'package:backscroll/core/export/exporter.dart';
import 'package:backscroll/core/export/job.dart';
import 'package:backscroll/core/export/options.dart';
import 'package:backscroll/core/export/writers/writer.dart';
import 'package:backscroll/core/media/downloader.dart';
import 'package:backscroll/core/media/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sample_world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sample export', () async {
    final world = SampleWorld()..build();
    final images = await world.images();
    final out = Directory('build/screenshots/export');
    if (out.existsSync()) out.deleteSync(recursive: true);
    final assets = ExportAssets(
      fontRegular: base64Encode(
        File('assets/export/figtree.woff2').readAsBytesSync(),
      ),
      fontItalic: base64Encode(
        File('assets/export/figtree-italic.woff2').readAsBytesSync(),
      ),
    );
    final channel = Channel.fromJson(
      world.studioChannels.firstWhere((c) => c['id'] == SampleWorld.devLogId),
    );
    for (final format in [
      ExportFormat.htmlDark,
      ExportFormat.htmlLight,
      ExportFormat.json,
      ExportFormat.txt,
    ]) {
      final job = ExportJob.create(
        accountId: 'bot',
        guild: Guild.fromJson(world.guilds.first),
        channel: channel,
        category: 'Development',
        options: ExportOptions(
          outputDir: '${out.path}/${format.name}',
          format: format,
          mediaMode: MediaMode.local,
          useUtc: true,
        ),
      )..startedAt = SampleWorld.exportTime;
      final exporter = ChannelExporter(
        api: DiscordApi('token', TokenKind.bot, client: world.apiClient()),
        job: job,
        media: StandardMediaPipeline(
          job: job,
          downloader: MediaDownloader(client: world.cdnClient(images)),
          stagingDir: '${out.path}/staging',
        ),
        store: JobStore(Directory('${out.path}/jobs')),
        assets: assets,
      );
      await exporter.run(CancelToken());
      await exporter.drain();
      expect(job.messages, world.messages(SampleWorld.devLogId).length);
    }

    File only(ExportFormat format) =>
        Directory('${out.path}/${format.name}')
            .listSync()
            .whereType<File>()
            .firstWhere((file) => file.path.endsWith('.${format.extension}'));
    for (final (from, to) in [
      (ExportFormat.json, ExportFormat.htmlDark),
      (ExportFormat.json, ExportFormat.txt),
      (ExportFormat.htmlDark, ExportFormat.json),
      (ExportFormat.htmlLight, ExportFormat.txt),
    ]) {
      final converted = await convertExport(
        sources: [only(from)],
        target: to,
        assets: assets,
        useUtc: true,
      );
      final file = File(converted.files.single);
      expect(
        file.readAsStringSync() == only(to).readAsStringSync(),
        isTrue,
        reason: '${from.name} to ${to.name}',
      );
      file.deleteSync();
    }
  });
}
