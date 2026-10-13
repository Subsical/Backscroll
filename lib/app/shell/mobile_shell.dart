import 'package:flutter/material.dart';

import '../../core/discord/models.dart';
import '../chat/channel_view.dart';
import '../export/queue_view.dart';
import '../login/login_screen.dart';
import '../scope.dart';
import '../settings/settings_screen.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'server_rail.dart';
import 'sidebar.dart';

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _tab = 0;

  void _open(Channel channel) {
    final library = AppScope.of(context).library;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Palette.chat,
          body: SafeArea(
            child: ChannelView(
              channel: channel,
              guild: library.guildOf(channel),
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.session, services.exports]),
      builder: (context, _) {
        final bot = services.session.isBot;
        final running = services.exports.queue.remaining;
        final home = bot
            ? Row(
                children: [
                  ServerRail(
                    homeSelected: false,
                    onHome: () => setState(() => _tab = 1),
                    onGuild: services.library.selectGuild,
                    onAddAccount: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(adding: true),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SidebarFrame(
                      child: GuildSidebar(onOpen: _open, room: 0),
                    ),
                  ),
                ],
              )
            : DmSidebar(onOpen: _open, room: 0);
        return Scaffold(
          backgroundColor: bot && _tab == 0 ? Palette.rail : Palette.chat,
          body: SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _tab,
              children: [home, const _ExportsTab(), const _YouTab()],
            ),
          ),
          bottomNavigationBar: _NavBar(
            index: _tab,
            bot: bot,
            running: running,
            onTap: (i) => setState(() => _tab = i),
          ),
        );
      },
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.bot,
    required this.running,
    required this.onTap,
  });

  final int index;
  final bool bot;
  final int running;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).session.account;
    Widget item(int i, String label, Widget icon) {
      final selected = index == i;
      return Expanded(
        child: InkWell(
          onTap: () => onTap(i),
          mouseCursor: WidgetStateMouseCursor.clickable,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: selected ? Palette.header : Palette.muted,
                    size: 26,
                  ),
                  child: icon,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Palette.header : Palette.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Palette.rail,
        border: Border(top: BorderSide(color: Palette.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            item(
              0,
              bot ? 'Servers' : 'Messages',
              Icon(bot ? Icons.grid_view_rounded : Icons.chat_bubble_rounded),
            ),
            item(
              1,
              'Exports',
              Badge(
                isLabelVisible: running > 0,
                label: Text('$running'),
                backgroundColor: Palette.danger,
                child: const Icon(Icons.download_rounded),
              ),
            ),
            item(
              2,
              'You',
              account == null
                  ? const Icon(Icons.person_rounded)
                  : Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: index == 2
                              ? Palette.header
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: UserAvatar(user: account.user, size: 24),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportsTab extends StatelessWidget {
  const _ExportsTab();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          'Exports',
          style: TextStyle(
            color: Palette.header,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Expanded(child: QueueView(showHeader: false)),
    ],
  );
}

class _YouTab extends StatelessWidget {
  const _YouTab();

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _build(session),
    );
  }

  Widget _build(Session session) {
    final account = session.account;
    if (account == null) return const SizedBox.shrink();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(height: 110, color: Palette.blurple),
            Positioned(
              left: 16,
              bottom: -44,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Palette.chat,
                  shape: BoxShape.circle,
                ),
                child: UserAvatar(user: account.user, size: 84),
              ),
            ),
          ],
        ),
        const SizedBox(height: 52),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.displayName,
                style: const TextStyle(
                  color: Palette.header,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                session.isBot
                    ? '${account.user.tag} · bot account'
                    : account.user.tag,
                style: Styles.small,
              ),
            ],
          ),
        ),
        const SettingsMenu(embedded: true),
      ],
    );
  }
}
