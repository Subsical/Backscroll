import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:backscroll/app/chat/message_list.dart';
import 'package:backscroll/app/chat/message_search.dart';
import 'package:backscroll/app/chat/message_skeleton.dart';
import 'package:backscroll/app/chat/pinned_messages.dart';
import 'package:backscroll/app/export/export_sheet.dart';
import 'package:backscroll/app/export/queue_view.dart';
import 'package:backscroll/app/settings/settings_screen.dart';
import 'package:backscroll/app/shell/desktop_shell.dart';
import 'package:backscroll/app/shell/server_rail.dart';
import 'package:backscroll/app/shell/sidebar.dart';
import 'package:backscroll/app/state/library.dart';
import 'package:backscroll/app/state/settings.dart';
import 'package:backscroll/app/widgets/common.dart';
import 'package:backscroll/app/widgets/document_page.dart';
import 'package:backscroll/core/discord/models.dart';
import 'package:backscroll/core/discord/snowflake.dart';
import 'package:backscroll/core/export/job.dart';
import 'package:backscroll/core/export/options.dart';
import 'package:backscroll/core/media/providers/registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'app_harness.dart';
import 'sample_world.dart';

void main() {
  setUpAll(loadFonts);

  void desktopView(WidgetTester tester, {double scale = 2}) {
    tester.view.physicalSize = const Size(1440, 900) * scale;
    tester.view.devicePixelRatio = scale;
    addTearDown(tester.view.reset);
  }

  void phoneView(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  }

  void r2Bucket(AppSettings settings) => settings.providers.add(
    ProviderConfig(
      id: 'r2',
      kind: ProviderKind.s3,
      name: 'R2 bucket',
      settings: {
        'endpoint': 'https://4f1c7a.r2.cloudflarestorage.com',
        'bucket': 'pixel-garden',
        'region': 'auto',
        'publicUrl': 'https://files.pixelgarden.dev',
      },
    ),
  );
  const r2Secrets = {
    'r2': {'accessKey': 'sample', 'secretKey': 'sample'},
  };

  // tests default to android and its phone sized buttons
  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

  testWidgets('desktop with a running export', variant: desktop, (
    tester,
  ) async {
    desktopView(tester);
    final world = SampleWorld()
      ..build()
      ..fillHistory();
    world.pageDelay[SampleWorld.artShowcaseId] = const Duration(
      milliseconds: 120,
    );
    final h = (await tester.runAsync(
      () => AppHarness.create(
        bot: true,
        world: world,
        configure: r2Bucket,
        providerSecrets: r2Secrets,
      ),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    final guild = h.library.selectedGuild!;
    Channel channel(String id) => guild.channels.firstWhere((c) => c.id == id);
    h.library.selectChannel(channel(SampleWorld.devLogId));
    await h.settle(tester);
    final chat = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(MessageList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    chat.position.jumpTo(chat.position.maxScrollExtent - 250);

    await tester.runAsync(() async {
      final base = h.exports.defaultOptions();
      Future<void> export(String id, ExportOptions options) => h.exports.start(
        channels: [channel(id)],
        options: options,
        guild: guild.guild,
        categoryOf: guild.categoryOf,
      );
      await export(
        SampleWorld.announcementsId,
        base.copyWith(format: ExportFormat.json, mediaMode: MediaMode.links),
      );
      await export(
        SampleWorld.devLogId,
        base.copyWith(mediaMode: MediaMode.local),
      );
      await export(SampleWorld.artShowcaseId, base);
    });
    final art = h.exports.jobs.last;
    await h.waitFor(tester, () => art.progress > 0.5);
    expect(h.exports.jobs.first.status, JobStatus.done);
    expect(h.exports.uploadStats.total, greaterThan(0));
    await h.settle(tester, frames: 1);
    await h.shoot(tester, 'desktop');

    await tester.tap(find.text('Export').last);
    await h.settle(tester, frames: 6);
    expect(find.byType(ExportSheet), findsOneWidget);
    await h.shoot(tester, 'export-options');
    await h.dispose(tester);
  });

  testWidgets('attachment host settings', variant: desktop, (tester) async {
    desktopView(tester);
    final h = (await tester.runAsync(
      () => AppHarness.create(
        bot: true,
        configure: (settings) {
          r2Bucket(settings);
          settings.providers
            ..add(
              ProviderConfig(
                id: 'catbox',
                kind: ProviderKind.catbox,
                name: 'Catbox',
              ),
            )
            ..add(
              ProviderConfig(
                id: 'imgbb',
                kind: ProviderKind.imgbb,
                name: 'ImgBB',
                enabled: false,
              ),
            );
        },
        providerSecrets: {
          ...r2Secrets,
          'imgbb': {'apiKey': 'sample'},
        },
      ),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    final context = tester.element(find.byType(DesktopShell));
    unawaited(openSettings(context, page: SettingsPage.hosts));
    await h.settle(tester, frames: 8);
    expect(find.text('R2 bucket'), findsOneWidget);
    await h.shoot(tester, 'settings-hosts');
    await h.dispose(tester);
  });

  testWidgets('phone with direct messages', (tester) async {
    phoneView(tester);
    final world = SampleWorld()
      ..build()
      ..fillHistory();
    world.pageDelay[SampleWorld.crewDmId] = const Duration(milliseconds: 120);
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: false, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    await h.settle(tester);
    await h.shoot(tester, 'phone-messages');

    await tester.tap(find.text('Nick').first);
    await h.settle(tester);
    await h.shoot(tester, 'phone-chat');

    await tester.tap(find.byTooltip('Export this channel'));
    await h.settle(tester);
    await h.shoot(tester, 'phone-export');

    Navigator.of(tester.element(find.byType(ExportSheet))).pop();
    await h.settle(tester, frames: 4);
    Navigator.of(tester.element(find.byTooltip('Export this channel'))).pop();
    await h.settle(tester, frames: 4);

    final crew = h.library.dms.firstWhere((c) => c.id == SampleWorld.crewDmId);
    await tester.runAsync(
      () => h.exports.start(
        channels: [crew],
        options: h.exports.defaultOptions().copyWith(
          mediaMode: MediaMode.local,
        ),
      ),
    );
    await tester.tap(find.text('Exports'));
    await h.waitFor(tester, () => h.exports.jobs.first.progress > 0.4);
    await h.settle(tester, frames: 1);
    await h.shoot(tester, 'phone-exports');
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone search jumps to a result', (tester) async {
    phoneView(tester);
    final world = SampleWorld()
      ..build()
      ..fillHistory();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: false, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    await h.settle(tester);
    await tester.tap(find.text('expo booth').first);
    await h.settle(tester);
    await tester.tap(find.byTooltip('Search messages'));
    await h.settle(tester);
    await tester.enterText(find.byType(TextField), 'booth');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await h.settle(tester);
    expect(find.textContaining('booth shifts'), findsOneWidget);
    await h.shoot(tester, 'phone-search');

    await tester.tap(
      find
          .ancestor(
            of: find.text('booth layout v2 attached').at(1),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await h.settle(tester);
    expect(find.byType(MessageSearch), findsNothing);
    expect(
      tester
          .widgetList<MessageTile>(find.byType(MessageTile))
          .where((t) => t.highlight)
          .single
          .message
          .content,
      'booth layout v2 attached',
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester
          .widgetList<MessageTile>(find.byType(MessageTile))
          .where((t) => t.highlight),
      isEmpty,
    );
    await tester.tap(find.text('Jump to present'));
    await h.settle(tester);
    expect(find.text('Jump to present'), findsNothing);
    expect(
      find.text('the aisle, people walk past and see the trailer'),
      findsOneWidget,
    );
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop search opens beside the chat', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()
      ..build()
      ..fillHistory();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    h.library.selectChannel(
      h.library.selectedGuild!.channels.firstWhere(
        (c) => c.id == SampleWorld.artShowcaseId,
      ),
    );
    await h.settle(tester);
    await tester.tap(find.byTooltip('Search messages'));
    await h.settle(tester);
    expect(find.byType(MessageSearch), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'trailer');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await h.settle(tester);
    await tester.tap(
      find
          .ancestor(
            of: find
                .descendant(
                  of: find.byType(MessageSearch),
                  matching: find.text('can we use this for the trailer?'),
                )
                .at(3),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await h.settle(tester);
    expect(find.byType(MessageSearch), findsOneWidget);
    expect(find.text('Jump to present'), findsOneWidget);
    await tester.tap(find.byTooltip('Close search'));
    await h.settle(tester);
    expect(find.byType(MessageSearch), findsNothing);
    await h.dispose(tester);
  });

  testWidgets(
    'jumping to the newest message leaves nothing to load',
    variant: desktop,
    (tester) async {
      desktopView(tester, scale: 1);
      final world = SampleWorld()
        ..build()
        ..fillHistory();
      final h = (await tester.runAsync(
        () => AppHarness.create(bot: false, world: world),
      ))!;
      await tester.pumpWidget(h.app);
      await h.waitFor(tester, () => h.library.state == LoadState.ready);
      await h.settle(tester);
      await tester.tap(find.text('expo booth').first);
      await h.settle(tester);
      await tester.tap(find.byTooltip('Search messages'));
      await h.settle(tester);
      await tester.enterText(find.byType(TextField).last, 'aisle');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await h.settle(tester);
      await tester.tap(
        find
            .ancestor(
              of: find.descendant(
                of: find.byType(MessageSearch),
                matching: find.text(
                  'the aisle, people walk past and see the trailer',
                ),
              ),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await h.settle(tester);
      expect(
        tester
            .widgetList<MessageTile>(
              find.descendant(
                of: find.byType(MessageList),
                matching: find.byType(MessageTile),
              ),
            )
            .where((t) => t.highlight)
            .single
            .message
            .content,
        'the aisle, people walk past and see the trailer',
      );
      expect(find.text('Jump to present'), findsNothing);
      await h.dispose(tester);
    },
  );

  testWidgets('the edited tag shows its time on hover', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    h.library.selectChannel(
      h.library.selectedGuild!.channels.firstWhere(
        (c) => c.id == SampleWorld.generalId,
      ),
    );
    await h.settle(tester);
    final tag = find.text(' (edited)');
    final tooltip = find.ancestor(of: tag, matching: find.byType(Tooltip));
    expect(tooltip, findsOneWidget);
    final time = tester.widget<Tooltip>(tooltip).message!;
    expect(time, contains('2026'));
    expect(time, contains(':20:00'));
    expect(find.text(time), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(tag));
    await h.settle(tester, frames: 8);
    expect(find.text(time), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('the hover time has room for am and pm', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()..build();
    final general = world.messages(SampleWorld.generalId);
    final time = DateTime.parse(general.last['timestamp'] as String)
        .add(const Duration(minutes: 1));
    general.add({
      ...general.last,
      'id': snowflakeAt(time),
      'timestamp': time.toIso8601String(),
      'edited_timestamp': null,
      'content': 'the role menu is pinned there',
    });
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    h.library.selectChannel(
      h.library.selectedGuild!.channels.firstWhere(
        (c) => c.id == SampleWorld.generalId,
      ),
    );
    await h.settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.text('the role menu is pinned there')),
    );
    await tester.pump();
    final label = find.byWidgetPredicate(
      (w) => w is Text && w.style?.fontSize == 10.5,
    );
    expect(tester.widget<Text>(label).data, endsWith('M'));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)),
    );
    expect(paragraph.size.width, greaterThan(40));
    expect(
      paragraph.size.width,
      closeTo(paragraph.getMaxIntrinsicWidth(double.infinity), 0.5),
    );
    await h.shoot(tester, 'hover-time');
    await h.dispose(tester);
  });

  testWidgets(
    'a finished export converts to another format',
    variant: desktop,
    (tester) async {
      desktopView(tester);
      final world = SampleWorld()..build();
      final h = (await tester.runAsync(
        () => AppHarness.create(bot: true, world: world),
      ))!;
      await tester.pumpWidget(h.app);
      await h.waitFor(
        tester,
        () => h.library.selectedGuild?.state == LoadState.ready,
      );
      final guild = h.library.selectedGuild!;
      final channel = guild.channels.firstWhere(
        (c) => c.id == SampleWorld.playtestingId,
      );
      h.library.selectChannel(channel);
      await tester.runAsync(
        () => h.exports.start(
          channels: [channel],
          options: h.exports.defaultOptions().copyWith(
            format: ExportFormat.json,
            mediaMode: MediaMode.local,
          ),
          guild: guild.guild,
          categoryOf: guild.categoryOf,
        ),
      );
      await h.waitFor(
        tester,
        () => h.exports.jobs.single.status == JobStatus.done,
      );
      await h.waitFor(
        tester,
        () => find.byTooltip('More').evaluate().isNotEmpty,
      );

      expect(find.byTooltip('Convert a file'), findsOneWidget);
      await tester.tap(find.byTooltip('More'));
      await h.settle(tester, frames: 8);
      expect(find.text('Convert to'), findsOneWidget);
      expect(find.text('JSON'), findsNothing);
      for (final label in [
        'HTML (dark)',
        'HTML (light)',
        'Plain text',
        'CSV',
        'Remove from list',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await h.shoot(tester, 'convert-menu');

      await tester.tap(find.text('HTML (dark)'));
      await h.waitFor(
        tester,
        () => find.byType(JobTile).evaluate().length == 2,
      );
      await h.settle(tester, frames: 6);
      final converted = h.exports.jobs.last;
      expect(converted.status, JobStatus.done);
      expect(converted.options.format, ExportFormat.htmlDark);
      expect(converted.messages, 2);
      final page = File(converted.partPath(converted.parts.single));
      expect(page.existsSync(), isTrue);
      final html = page.readAsStringSync();
      expect(html, contains('<div class="container accent"'));
      expect(html, contains('_files/'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Saved '), findsOneWidget);
      await h.shoot(tester, 'converted');

      await tester.tap(find.byTooltip('More').first);
      await h.settle(tester, frames: 8);
      await tester.tap(find.text('Remove from list'));
      await h.waitFor(tester, () => h.exports.jobs.length == 1);
      expect(page.existsSync(), isTrue);
      await h.dispose(tester);
    },
  );

  testWidgets('component messages show their layout', variant: desktop, (
    tester,
  ) async {
    desktopView(tester);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    h.library.selectChannel(
      h.library.selectedGuild!.channels.firstWhere(
        (c) => c.id == SampleWorld.playtestingId,
      ),
    );
    await h.settle(tester);
    final title = find.text('Playtest 12 is open');
    expect(title, findsOneWidget);
    expect(find.textContaining('Ask @Tom if you get stuck'), findsOneWidget);
    for (final label in [
      'playtest-checklist.pdf',
      'Download the build',
      'Sign up',
      'Waitlist',
      'Pick a platform',
      'Save',
      'Leave',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    final card = find.ancestor(
      of: title,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 600,
      ),
    );
    expect(tester.getSize(card).width, 600);
    final pictures = tester
        .widgetList<Image>(
          find.descendant(of: card, matching: find.byType(Image)),
        )
        .where((image) => image.fit == BoxFit.cover);
    expect(pictures.map((image) => image.width), [85, 186, 186, 186]);
    await h.shoot(tester, 'components');
    await h.dispose(tester);
  });

  testWidgets('component messages fit a phone', (tester) async {
    phoneView(tester);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    await h.settle(tester);
    await tester.tap(find.text('playtesting'));
    await h.settle(tester);
    expect(find.text('Playtest 12 is open'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
    await h.shoot(tester, 'phone-components');
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> expectHandCursor(
    WidgetTester tester,
    List<Finder> targets,
  ) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final target in targets) {
      await mouse.moveTo(tester.getCenter(target));
      await tester.pump();
      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
        reason: '$target',
      );
    }
  }

  testWidgets('login buttons show the hand cursor', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: false, signedIn: false),
    ))!;
    await tester.pumpWidget(h.app);
    await h.settle(tester);
    await expectHandCursor(tester, [
      find.text('Log in with Discord'),
      find.byTooltip('Show'),
      find.text('How do I get a token?'),
      find.text('Continue'),
      find.text('Privacy policy'),
    ]);
    await h.dispose(tester);
  });

  testWidgets('shell controls show the hand cursor', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    h.library.selectChannel(
      h.library.selectedGuild!.channels.firstWhere(
        (c) => c.id == SampleWorld.generalId,
      ),
    );
    await h.settle(tester);
    await expectHandCursor(tester, [
      find.text('Plant Pot Games'),
      find.text('Community'),
      find.byTooltip('Search messages'),
      find.textContaining('Export #'),
      find.byTooltip('Settings'),
    ]);
    await h.dispose(tester);
  });

  testWidgets(
    'the rail marker sits at the edge of the rail',
    variant: desktop,
    (tester) async {
      desktopView(tester, scale: 1);
      final h = (await tester.runAsync(() => AppHarness.create(bot: false)))!;
      await tester.pumpWidget(h.app);
      await h.waitFor(tester, () => h.library.state == LoadState.ready);
      await h.settle(tester);
      final boxes = find.descendant(
        of: find.byType(RailItem).first,
        matching: find.byType(AnimatedContainer),
      );
      final marker = tester.getRect(boxes.at(0));
      final icon = tester.getRect(boxes.at(1));
      expect(marker.left, 0);
      expect(marker.right, lessThan(icon.left));
      expect(marker.height, 40);
      expect(marker.center.dy, icon.center.dy);
      await h.dispose(tester);
    },
  );

  testWidgets('rail tooltips open to the side', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final h = (await tester.runAsync(() => AppHarness.create(bot: false)))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    await h.settle(tester);
    final icon = find
        .descendant(
          of: find.byType(RailItem).first,
          matching: find.byType(AnimatedContainer),
        )
        .at(1);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(icon));
    await h.settle(tester, frames: 8);
    final tip = tester.getRect(
      find.descendant(
        of: find.byType(RailItem).first,
        matching: find.text('Direct Messages'),
      ),
    );
    expect(tip.left, greaterThan(tester.getRect(icon).right));
    expect(tip.center.dy, closeTo(tester.getCenter(icon).dy, 1));
    await h.shoot(tester, 'rail-tooltip');
    await h.dispose(tester);
  });

  Future<void> pressMouse(WidgetTester tester, int button) async {
    final mouse = await tester.startGesture(
      const Offset(700, 400),
      kind: PointerDeviceKind.mouse,
      buttons: button,
    );
    await mouse.up();
    await mouse.removePointer();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('back and forward step through conversations', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final h = (await tester.runAsync(() => AppHarness.create(bot: false)))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    await h.settle(tester);
    String? open() => h.library.selectedChannel?.displayName;
    await tester.tap(find.text('Nick').first);
    await h.settle(tester);
    await tester.tap(find.text('Alex').first);
    await h.settle(tester);
    expect(open(), 'Alex');

    await pressMouse(tester, kBackMouseButton);
    expect(open(), 'Nick');
    await pressMouse(tester, kBackMouseButton);
    expect(open(), isNull);
    await pressMouse(tester, kBackMouseButton);
    expect(open(), isNull);
    await pressMouse(tester, kForwardMouseButton);
    expect(open(), 'Nick');
    await tester.sendKeyEvent(
      LogicalKeyboardKey.browserForward,
      platform: 'windows',
    );
    expect(open(), 'Alex');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    await tester.pump();
    expect(open(), 'Nick');
    await h.settle(tester);

    await tester.tap(find.byTooltip('Add an account'));
    await h.settle(tester);
    expect(find.text('Log in with Discord'), findsOneWidget);
    await pressMouse(tester, kForwardMouseButton);
    expect(open(), 'Nick');
    await pressMouse(tester, kBackMouseButton);
    await h.settle(tester);
    expect(find.text('Log in with Discord'), findsNothing);
    expect(open(), 'Nick');
    await h.dispose(tester);
  });

  testWidgets(
    'a conversation shows a skeleton while it loads',
    variant: desktop,
    (tester) async {
      desktopView(tester, scale: 1);
      final world = SampleWorld()..build();
      world.pageDelay[SampleWorld.nickDmId] = const Duration(seconds: 1);
      final h = (await tester.runAsync(
        () => AppHarness.create(bot: false, world: world),
      ))!;
      await tester.pumpWidget(h.app);
      await h.waitFor(tester, () => h.library.state == LoadState.ready);
      await h.settle(tester);
      await tester.tap(find.text('Nick').first);
      await h.settle(tester, frames: 2);
      expect(find.byType(MessageSkeleton), findsOneWidget);
      expect(find.byType(MessageList), findsNothing);
      await h.waitFor(
        tester,
        () => find.byType(MessageList).evaluate().isNotEmpty,
      );
      await h.settle(tester);
      expect(find.byType(MessageSkeleton), findsNothing);
      await h.dispose(tester);
    },
  );

  Future<List<String>> copiedText(WidgetTester tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return copied;
  }

  Finder chatTile(Object? id) => find.descendant(
    of: find.byType(MessageList),
    matching: find.byWidgetPredicate(
      (w) => w is MessageTile && w.message.id == id,
    ),
  );

  testWidgets('hovering a message offers to export from it', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()
      ..build()
      ..fillHistory();
    final copied = await copiedText(tester);
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: false, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    await h.settle(tester);
    await tester.tap(find.text('expo booth').first);
    await h.settle(tester);
    expect(find.byTooltip('Export from here'), findsNothing);

    final all = world.messages(SampleWorld.crewDmId);
    final row = chatTile(all[all.length - 3]['id']);
    final message = tester.widget<MessageTile>(row).message;
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.addPointer(location: Offset.zero));
    addTearDown(() => tester.sendEventToBinding(mouse.removePointer()));
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(row)));
    await h.settle(tester, frames: 3);
    expect(find.byTooltip('Export from here'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    expect(
      tester.getTopRight(find.byTooltip('More')).dy,
      lessThan(tester.getTopLeft(row).dy + 16),
    );

    await tester.tap(find.byTooltip('Copy message link'));
    await h.settle(tester, frames: 2);
    expect(
      copied.last,
      'https://discord.com/channels/@me/${SampleWorld.crewDmId}/${message.id}',
    );
    await tester.tap(find.byTooltip('More'));
    await h.settle(tester, frames: 3);
    await tester.tap(find.text('Copy message ID'));
    await h.settle(tester, frames: 3);
    expect(copied.last, message.id);

    await tester.tap(row, buttons: kSecondaryButton);
    await h.settle(tester, frames: 3);
    await tester.tap(find.text('Copy text'));
    await h.settle(tester, frames: 3);
    expect(copied.last, message.content);

    final chat = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(MessageList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final before = chat.position.pixels;
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.byTooltip('More'))),
    );
    await h.settle(tester, frames: 2);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
    await h.settle(tester, frames: 3);
    expect(chat.position.pixels, isNot(before));
    chat.position.jumpTo(before);
    await tester.pump();
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(row)));
    await h.settle(tester, frames: 3);

    await tester.tap(find.byTooltip('Export from here'));
    await h.settle(tester);
    final sent = snowflakeTime(message.id);
    expect(
      tester.widget<ExportSheet>(find.byType(ExportSheet)).after?.toUtc(),
      sent.subtract(const Duration(milliseconds: 1)),
    );
    await tester.tap(find.text('Export').last);
    await h.waitForExports(tester);
    expect(h.exports.jobs.last.status, JobStatus.done);
    expect(h.exports.jobs.last.messages, 3);
    await h.dispose(tester);
  });

  testWidgets(
    'the message menu opens to the right of the pointer',
    variant: desktop,
    (tester) async {
      tester.view.physicalSize = const Size(1000, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final world = SampleWorld()..build();
      final h = (await tester.runAsync(
        () => AppHarness.create(bot: false, world: world),
      ))!;
      await tester.pumpWidget(h.app);
      await h.waitFor(tester, () => h.library.state == LoadState.ready);
      await h.settle(tester);
      await tester.tap(find.text('Nick').first);
      await h.settle(tester);
      final row = chatTile(world.messages(SampleWorld.nickDmId)[1]['id']);
      final y = tester.getCenter(row).dy;

      Future<double> menuLeft(double x) async {
        await tester.tapAt(Offset(x, y), buttons: kSecondaryButton);
        await h.settle(tester, frames: 3);
        final label = tester.getTopLeft(find.text('Export from here')).dx;
        await tester.tapAt(const Offset(20, 740));
        await h.settle(tester, frames: 3);
        expect(find.text('Export from here'), findsNothing);
        return label - 44;
      }

      expect(await menuLeft(700), closeTo(700, 1));
      expect(await menuLeft(900), closeTo(900 - 224, 1));
      await h.dispose(tester);
    },
  );

  testWidgets('holding a message opens its actions', (tester) async {
    phoneView(tester);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: false, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    await h.settle(tester);
    await tester.tap(find.text('Nick').first);
    await h.settle(tester);
    final all = world.messages(SampleWorld.nickDmId);
    final row = chatTile(all[1]['id']);
    final message = tester.widget<MessageTile>(row).message;
    expect(find.byTooltip('More'), findsNothing);

    await tester.longPress(row);
    await h.settle(tester);
    expect(find.text('Export from here'), findsOneWidget);
    expect(find.text('Copy message ID'), findsOneWidget);
    await tester.tap(find.text('Export up to here'));
    await h.settle(tester);
    expect(
      tester.widget<ExportSheet>(find.byType(ExportSheet)).before?.toUtc(),
      snowflakeTime(message.id).add(const Duration(milliseconds: 1)),
    );
    await tester.tap(find.text('Export').last);
    await h.waitForExports(tester);
    expect(h.exports.jobs.last.status, JobStatus.done);
    expect(h.exports.jobs.last.messages, 2);
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('refreshing reloads the conversation list', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: false, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    await h.settle(tester);
    await tester.tap(find.text('Nick').first);
    await h.settle(tester);
    List<String> names() => [for (final c in h.library.dms) c.displayName];
    expect(names().first, 'Nick');

    world.dmChannels.last['last_message_id'] = snowflakeAt(
      DateTime.utc(2026, 3, 15),
    );
    await tester.tap(find.byTooltip('Refresh'));
    await h.waitFor(
      tester,
      () => names().first == 'Marta' && !h.library.refreshing,
    );
    await h.settle(tester, frames: 2);
    expect(h.library.refreshing, isFalse);
    expect(h.library.selectedChannel?.displayName, 'Nick');
    expect(find.byType(MessageList), findsOneWidget);

    world.dmChannels.removeLast();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await h.waitFor(tester, () => names().length == 4);
    expect(names(), isNot(contains('Marta')));
    await h.dispose(tester);
  });

  testWidgets('a bot reloads its servers where it is', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    final other = h.library.guilds[1].guild.id;
    unawaited(h.library.selectGuild(other));
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    await h.settle(tester);

    world.guilds[1]['name'] = 'Reading Group';
    await tester.tap(find.text('Book Club'));
    await h.settle(tester, frames: 3);
    await tester.tap(find.text('Reload'));
    await h.waitFor(
      tester,
      () =>
          h.library.selectedGuild?.guild.name == 'Reading Group' &&
          !h.library.refreshing,
    );
    await h.settle(tester, frames: 2);
    expect(h.library.selectedGuildId, other);
    expect(h.library.refreshing, isFalse);
    expect(find.text('Reading Group'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('back returns to the server you came from', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    h.library.selectChannel(
      h.library.selectedGuild!.channels.firstWhere(
        (c) => c.id == SampleWorld.devLogId,
      ),
    );
    await h.settle(tester);
    final other = h.library.guilds[1].guild.id;
    unawaited(h.library.selectGuild(other));
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    h.library.goHome();
    await h.settle(tester, frames: 4);
    expect(h.library.home, isTrue);

    await pressMouse(tester, kBackMouseButton);
    expect(h.library.home, isFalse);
    expect(h.library.selectedGuildId, other);
    await pressMouse(tester, kBackMouseButton);
    expect(h.library.selectedGuildId, SampleWorld.studioId);
    expect(h.library.selectedChannel?.id, SampleWorld.devLogId);
    await h.settle(tester);
    expect(find.byType(MessageList), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('adding an account fits the default window', variant: desktop, (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1264, 761);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = (await tester.runAsync(() => AppHarness.create(bot: false)))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    await h.settle(tester);
    await tester.tap(find.byTooltip('Add an account'));
    await h.settle(tester);
    final scroll = tester.state<ScrollableState>(
      find
          .ancestor(
            of: find.text('Add an account'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scroll.position.maxScrollExtent, 0);
    await tester.tap(find.text('Continue'));
    await h.settle(tester, frames: 3);
    expect(find.text('Paste a token first.'), findsOneWidget);
    expect(scroll.position.maxScrollExtent, 0);
    await tester.tap(find.byType(BackButton));
    await h.settle(tester);
    expect(find.text('Add an account'), findsNothing);
    await h.dispose(tester);
  });

  Future<void> expectSteadyExtent(WidgetTester tester, Finder row) async {
    final position = tester
        .state<ScrollableState>(
          find.ancestor(of: row, matching: find.byType(Scrollable)).first,
        )
        .position;
    final extent = position.maxScrollExtent;
    expect(extent, greaterThan(0));
    for (final part in [0.2, 0.55, 0.9, 0.4, 1.0]) {
      position.jumpTo(extent * part);
      await tester.pump();
      expect(position.maxScrollExtent, extent);
    }
  }

  testWidgets('the dm list keeps a steady length', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()..build();
    for (var i = 0; i < 90; i++) {
      world.dmChannels.add({
        'id': '${150000000000001000 + i}',
        'type': i % 4 == 0 ? 3 : 1,
        'name': i % 4 == 0 ? 'Group $i' : null,
        'recipients': i % 4 == 0 ? [world.nick, world.dana] : [world.alex],
        'last_message_id': '${150000000000001000 + i}',
      });
    }
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: false, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    await h.settle(tester);
    await expectSteadyExtent(tester, find.byType(HoverTile).first);
    await h.dispose(tester);
  });

  testWidgets('the channel list keeps a steady length', variant: desktop, (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1264, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    await h.settle(tester);
    await expectSteadyExtent(tester, find.byType(ChannelRow).first);
    await h.dispose(tester);
  });

  testWidgets('the chat keeps a steady length once seen', variant: desktop, (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1264, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    h.library.selectChannel(
      h.library.selectedGuild!.channels.firstWhere(
        (c) => c.id == SampleWorld.devLogId,
      ),
    );
    await h.settle(tester);
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(MessageList),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    for (var i = 0; i < 100; i++) {
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(min(position.pixels + 150, position.maxScrollExtent));
      await tester.pump();
    }
    final extent = position.maxScrollExtent;
    expect(extent, greaterThan(1000));
    for (final part in [0.0, 0.3, 0.6, 0.85, 1.0]) {
      position.jumpTo(extent * part);
      await tester.pump();
      expect(position.maxScrollExtent, closeTo(extent, 0.5));
    }
    await h.dispose(tester);
  });

  testWidgets('search replaces the exports panel', variant: desktop, (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1264, 761);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    h.library.selectChannel(
      h.library.selectedGuild!.channels.firstWhere(
        (c) => c.id == SampleWorld.devLogId,
      ),
    );
    await h.settle(tester);
    expect(find.byType(QueueView), findsOneWidget);
    await tester.tap(find.byTooltip('Search messages'));
    await h.settle(tester);
    expect(find.byType(MessageSearch), findsOneWidget);
    expect(find.byType(QueueView), findsNothing);
    expect(tester.getSize(find.byType(MessageList)).width, greaterThan(500));
    await tester.tap(find.byTooltip('Close search'));
    await h.settle(tester);
    expect(find.byType(QueueView), findsOneWidget);

    tester.view.physicalSize = const Size(1000, 761);
    await h.settle(tester, frames: 2);
    await tester.tap(find.byTooltip('Search messages'));
    await h.settle(tester);
    expect(find.byType(MessageSearchPage), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('pinned messages open beside the chat', variant: desktop, (
    tester,
  ) async {
    desktopView(tester, scale: 1);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    Channel channel(String id) =>
        h.library.selectedGuild!.channels.firstWhere((c) => c.id == id);
    h.library.selectChannel(channel(SampleWorld.generalId));
    await h.settle(tester);
    await tester.tap(find.byTooltip('Pinned messages'));
    await h.settle(tester);
    expect(find.text('Nothing is pinned here.'), findsOneWidget);

    h.library.selectChannel(channel(SampleWorld.devLogId));
    await h.settle(tester);
    expect(find.byType(PinnedMessages), findsNothing);
    await tester.tap(find.byTooltip('Pinned messages'));
    await h.settle(tester);
    final pinned = find.descendant(
      of: find.byType(PinnedMessages),
      matching: find.text('Build 0.9.2 is ready'),
    );
    expect(pinned, findsOneWidget);
    await tester.tap(
      find.ancestor(of: pinned, matching: find.byType(InkWell)).first,
    );
    await h.settle(tester);
    expect(find.byType(PinnedMessages), findsOneWidget);
    expect(
      tester
          .widgetList<MessageTile>(
            find.descendant(
              of: find.byType(MessageList),
              matching: find.byType(MessageTile),
            ),
          )
          .where((t) => t.highlight)
          .single
          .message
          .pinned,
      isTrue,
    );
    await tester.tap(find.byTooltip('Close pinned messages'));
    await h.settle(tester);
    expect(find.byType(PinnedMessages), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('phone pins jump to the message', (tester) async {
    phoneView(tester);
    final world = SampleWorld()..build();
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: true, world: world),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(
      tester,
      () => h.library.selectedGuild?.state == LoadState.ready,
    );
    await h.settle(tester);
    await tester.tap(find.text('dev-log'));
    await h.settle(tester);
    await tester.tap(find.byTooltip('Pinned messages'));
    await h.settle(tester);
    expect(find.byType(PinnedMessagesPage), findsOneWidget);
    await tester.tap(
      find
          .ancestor(
            of: find.text('Build 0.9.2 is ready'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await h.settle(tester);
    expect(find.byType(PinnedMessagesPage), findsNothing);
    expect(
      tester
          .widgetList<MessageTile>(find.byType(MessageTile))
          .where((t) => t.highlight)
          .single
          .message
          .pinned,
      isTrue,
    );
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone settings pages', (tester) async {
    phoneView(tester);
    final h = (await tester.runAsync(
      () => AppHarness.create(
        bot: false,
        configure: (settings) {
          r2Bucket(settings);
          settings.defaults.mediaMode = null;
        },
        providerSecrets: r2Secrets,
      ),
    ))!;
    await tester.pumpWidget(h.app);
    await h.waitFor(tester, () => h.library.state == LoadState.ready);
    for (final page in SettingsPage.values) {
      final navigator = Navigator.of(
        tester.element(find.byType(Scaffold).first),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute(builder: (_) => SettingsPageScreen(page: page)),
        ),
      );
      await h.settle(tester, frames: 6);
      await h.shoot(tester, 'phone-settings-${page.name}');
      navigator.pop();
      await h.settle(tester, frames: 4);
    }
    for (final document in AppDocument.values) {
      final context = tester.element(find.byType(Scaffold).first);
      unawaited(document.open(context));
      await h.settle(tester, frames: 6);
      expect(find.byType(DocumentPage), findsOneWidget);
      await h.shoot(tester, 'phone-document-${document.name}');
      Navigator.of(tester.element(find.byType(DocumentPage))).pop();
      await h.settle(tester, frames: 4);
    }
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone login', (tester) async {
    phoneView(tester);
    final h = (await tester.runAsync(
      () => AppHarness.create(bot: false, signedIn: false),
    ))!;
    await tester.pumpWidget(h.app);
    await h.settle(tester);
    expect(find.text('Log in with Discord'), findsOneWidget);
    await h.shoot(tester, 'phone-login');
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'export animation frames',
    skip: screenshotDir == null,
    variant: desktop,
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final world = SampleWorld()
        ..build()
        ..fillHistory();
      world.pageDelay[SampleWorld.artShowcaseId] = const Duration(
        milliseconds: 110,
      );
      final h = (await tester.runAsync(
        () => AppHarness.create(
          bot: true,
          world: world,
          configure: r2Bucket,
          providerSecrets: r2Secrets,
          uploadBytesPerSecond: 150000,
        ),
      ))!;
      await tester.pumpWidget(h.app);
      await h.waitFor(
        tester,
        () => h.library.selectedGuild?.state == LoadState.ready,
      );
      final guild = h.library.selectedGuild!;
      final art = guild.channels.firstWhere(
        (c) => c.id == SampleWorld.artShowcaseId,
      );
      h.library.selectChannel(art);
      await h.settle(tester);

      final clock = Stopwatch()..start();
      final shots = <(String, Duration)>[];
      final holds = <String, double>{};
      Future<void> frame({double? hold}) async {
        final name = 'frame_${shots.length.toString().padLeft(4, '0')}';
        await h.shoot(tester, 'frames/$name');
        shots.add((name, clock.elapsed));
        if (hold != null) holds[name] = hold;
      }

      Future<void> animate(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await frame();
        }
      }

      await frame(hold: 1.2);
      await tester.tap(find.text('Export').last);
      await animate(4);
      await h.settle(tester, frames: 3);
      await frame(hold: 2.2);
      Navigator.of(tester.element(find.byType(ExportSheet))).pop();
      await tester.runAsync(
        () => h.exports.start(
          channels: [art],
          options: h.exports.defaultOptions(),
          guild: guild.guild,
          categoryOf: guild.categoryOf,
        ),
      );
      await animate(4);
      final job = h.exports.jobs.last;
      while (shots.length < 240 &&
          !(job.status == JobStatus.done && h.exports.uploadStats.idle)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
        await frame();
      }
      await h.settle(tester, frames: 3);
      await frame(hold: 3);
      expect(job.status, JobStatus.done);

      final list = <String>[];
      for (var i = 0; i < shots.length; i++) {
        final (name, at) = shots[i];
        final next = i + 1 < shots.length ? shots[i + 1].$2 : at;
        final seconds = holds[name] ?? (next - at).inMilliseconds / 1000;
        list
          ..add("file '$name.png'")
          ..add('duration ${seconds.toStringAsFixed(3)}');
      }
      list.add("file '${shots.last.$1}.png'");
      await tester.runAsync(
        () =>
            File(p.join(screenshotDir!, 'frames', 'frames.txt'))
                .writeAsString(list.join('\n')),
      );
      await h.dispose(tester);
    },
  );
}
