import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'about_page.dart';
import 'accounts_page.dart';
import 'defaults_page.dart';
import 'hosts_page.dart';

enum SettingsPage {
  accounts('My accounts', Icons.person_outline_rounded),
  defaults('Export defaults', Icons.tune_rounded),
  hosts('Attachment hosts', Icons.cloud_upload_outlined),
  about('About', Icons.info_outline_rounded);

  const SettingsPage(this.title, this.icon);

  final String title;
  final IconData icon;

  Widget body() => switch (this) {
    SettingsPage.accounts => const AccountsPage(),
    SettingsPage.defaults => const DefaultsPage(),
    SettingsPage.hosts => const HostsPage(),
    SettingsPage.about => const AboutPage(),
  };
}

Future<void> openSettings(BuildContext context, {SettingsPage? page}) {
  if (isCompact(context)) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => page == null
            ? const SettingsMenu()
            : SettingsPageScreen(page: page),
      ),
    );
  }
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) =>
          SettingsScreen(initial: page ?? SettingsPage.accounts),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(animation),
          child: child,
        ),
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.initial});

  final SettingsPage initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsPage _page = widget.initial;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.chat,
    body: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Container(
                color: Palette.sidebar,
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 218,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(6, 60, 6, 24),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
                        child: Text('Settings', style: Styles.sectionLabel),
                      ),
                      for (final page in SettingsPage.values)
                        HoverTile(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          selected: page == _page,
                          onTap: () => setState(() => _page = page),
                          child: Text(
                            page.title,
                            style: TextStyle(
                              color: page == _page
                                  ? Palette.header
                                  : Palette.muted,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(40, 60, 40, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_page.title, style: Styles.title),
                            const SizedBox(height: 20),
                            Expanded(child: _page.body()),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 60,
                    right: 24,
                    child: Column(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: IconButton.styleFrom(
                            side: const BorderSide(
                              color: Palette.muted,
                              width: 2,
                            ),
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Palette.muted,
                          ),
                          tooltip: 'Close',
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'ESC',
                          style: TextStyle(
                            color: Palette.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SettingsMenu extends StatelessWidget {
  const SettingsMenu({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final menu = Padding(
      padding: const EdgeInsets.all(16),
      child: Material(
        color: Palette.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Palette.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final page in SettingsPage.values)
              ListTile(
                leading: Icon(page.icon, color: Palette.muted),
                title: Text(
                  page.title,
                  style: const TextStyle(
                    color: Palette.header,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Palette.muted,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPageScreen(page: page),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (embedded) return menu;
    return Scaffold(
      backgroundColor: Palette.chat,
      appBar: AppBar(
        backgroundColor: Palette.chat,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(children: [menu]),
    );
  }
}

class SettingsPageScreen extends StatelessWidget {
  const SettingsPageScreen({super.key, required this.page});

  final SettingsPage page;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.chat,
    appBar: AppBar(
      backgroundColor: Palette.chat,
      surfaceTintColor: Colors.transparent,
      title: Text(
        page.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: page.body(),
      ),
    ),
  );
}
