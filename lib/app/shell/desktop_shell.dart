import 'package:flutter/material.dart';

import '../chat/channel_view.dart';
import '../export/queue_view.dart';
import '../login/login_screen.dart';
import '../scope.dart';
import '../theme.dart';
import 'server_rail.dart';
import 'sidebar.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final _exportsKey = GlobalKey();
  bool _panel = true;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final library = services.library;
    return ListenableBuilder(
      listenable: Listenable.merge([services.session, library]),
      builder: (context, _) {
        final bot = services.session.isBot;
        final channel = library.selectedChannel;
        final wide = MediaQuery.sizeOf(context).width >= 1150;
        final showHome = channel == null || (bot && library.home);
        final Widget sidebar = !bot
            ? DmSidebar(onOpen: library.selectChannel)
            : library.home
            ? ServerList(onGuild: library.selectGuild)
            : GuildSidebar(onOpen: library.selectChannel);
        return Scaffold(
          body: Row(
            children: [
              ColoredBox(
                color: Palette.rail,
                child: Stack(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ServerRail(
                          homeSelected: bot ? library.home : true,
                          onHome: library.goHome,
                          onGuild: library.selectGuild,
                          onAddAccount: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(adding: true),
                            ),
                          ),
                          room: UserPanel.room,
                        ),
                        SizedBox(
                          width: 240,
                          child: SidebarFrame(child: sidebar),
                        ),
                      ],
                    ),
                    const Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: UserPanel(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    const ColoredBox(
                      color: Palette.rail,
                      child: Divider(height: 1, color: Palette.divider),
                    ),
                    Expanded(
                      child: showHome
                          ? const HomePane()
                          : ChannelView(
                              key: ValueKey(channel.id),
                              channel: channel,
                              guild: library.guildOf(channel),
                              actions: [
                                if (wide)
                                  IconButton(
                                    onPressed: () =>
                                        setState(() => _panel = !_panel),
                                    tooltip: _panel
                                        ? 'Hide exports'
                                        : 'Show exports',
                                    icon: Icon(
                                      Icons.view_sidebar_outlined,
                                      color: _panel
                                          ? Palette.header
                                          : Palette.muted,
                                    ),
                                  ),
                              ],
                              aside: wide && _panel
                                  ? Container(
                                      key: _exportsKey,
                                      width: 300,
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: Palette.divider,
                                          ),
                                        ),
                                      ),
                                      child: const QueueView(),
                                    )
                                  : null,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class HomePane extends StatelessWidget {
  const HomePane({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: Palette.chat,
    child: Column(
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Palette.chat,
            border: Styles.underline,
          ),
          child: const Row(
            children: [
              Icon(Icons.downloading_rounded, color: Palette.faint),
              SizedBox(width: 8),
              Text(
                'Exports',
                style: TextStyle(
                  color: Palette.header,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: const Padding(
                padding: EdgeInsets.only(top: 12),
                child: QueueView(),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
