import 'package:flutter/material.dart';

import '../../core/discord/models.dart';
import '../export/export_sheet.dart';
import '../scope.dart';
import '../settings/settings_screen.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'server_rail.dart';

Future<void> refreshLibrary(BuildContext context) async {
  final problem = await AppScope.of(context).library.refresh();
  if (problem != null && context.mounted) showToast(context, problem);
}

class RefreshButton extends StatelessWidget {
  const RefreshButton({super.key});

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => IconButton(
        onPressed: library.refreshing ? null : () => refreshLibrary(context),
        tooltip: 'Refresh',
        visualDensity: VisualDensity.compact,
        icon: library.refreshing
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Palette.muted,
                ),
              )
            : const Icon(Icons.refresh_rounded, size: 18, color: Palette.muted),
      ),
    );
  }
}

class _PullToRefresh extends StatelessWidget {
  const _PullToRefresh({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () => refreshLibrary(context),
    color: Palette.header,
    backgroundColor: Palette.floating,
    child: child,
  );
}

class SidebarHeader extends StatelessWidget {
  const SidebarHeader({
    super.key,
    required this.title,
    this.menu = false,
    this.trailing,
  });

  final String title;
  final bool menu;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: EdgeInsets.only(left: 16, right: trailing == null ? 16 : 8),
    decoration: const BoxDecoration(
      color: Palette.sidebar,
      border: Styles.underline,
    ),
    child: Row(
      children: [
        Flexible(
          fit: trailing == null ? FlexFit.loose : FlexFit.tight,
          child: Text(
            title,
            style: const TextStyle(
              color: Palette.header,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (menu)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: Palette.text,
            ),
          ),
        ?trailing,
      ],
    ),
  );
}

class SidebarFrame extends StatelessWidget {
  const SidebarFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: const BoxDecoration(
      color: Palette.sidebar,
      borderRadius: BorderRadius.only(topLeft: Radius.circular(12)),
      border: Border(
        left: BorderSide(color: Palette.divider),
        top: BorderSide(color: Palette.divider),
      ),
    ),
    child: child,
  );
}

class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.channels,
    this.guild,
    required this.all,
  });

  final List<Channel> channels;
  final GuildState? guild;
  final Iterable<Channel> all;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: Styles.card,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${channels.length} selected',
              style: const TextStyle(
                color: Palette.header,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => library.selectAll(all),
            child: const Text('All', style: TextStyle(color: Palette.muted)),
          ),
          DiscordButton(
            label: 'Export',
            dense: true,
            onPressed: channels.isEmpty
                ? null
                : () async {
                    final started = await showExportSheet(
                      context,
                      channels: channels,
                      guild: guild,
                    );
                    if (started) library.toggleSelecting();
                  },
          ),
        ],
      ),
    );
  }
}

class ChannelRow extends StatelessWidget {
  const ChannelRow({
    super.key,
    required this.channel,
    required this.onTap,
    this.selected = false,
    this.checkbox = false,
    this.checked = false,
  });

  final Channel channel;
  final VoidCallback onTap;
  final bool selected;
  final bool checkbox;
  final bool checked;

  @override
  Widget build(BuildContext context) => HoverTile(
    selected: selected,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      children: [
        ChannelGlyph(
          channel,
          color: selected ? Palette.header : Palette.channel,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            channel.displayName,
            style: TextStyle(
              color: selected || checked ? Palette.header : Palette.channel,
              fontSize: 16,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (checkbox)
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(value: checked, onChanged: (_) => onTap()),
          ),
      ],
    ),
  );
}

class GuildSidebar extends StatefulWidget {
  const GuildSidebar({
    super.key,
    required this.onOpen,
    this.room = UserPanel.room,
  });

  final ValueChanged<Channel> onOpen;
  final double room;

  @override
  State<GuildSidebar> createState() => _GuildSidebarState();
}

class _GuildSidebarState extends State<GuildSidebar> {
  final _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    return Container(
      color: Palette.sidebar,
      child: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final guild = library.selectedGuild;
          return Column(
            children: [
              if (guild == null)
                const SidebarHeader(title: 'Servers', trailing: RefreshButton())
              else
                PopupMenuButton<String>(
                  tooltip: '',
                  position: PopupMenuPosition.under,
                  offset: const Offset(8, 4),
                  popUpAnimationStyle: AnimationStyle.noAnimation,
                  onSelected: (value) {
                    switch (value) {
                      case 'select':
                        library.toggleSelecting();
                      case 'all':
                        showExportSheet(
                          context,
                          channels: guild.exportable.toList(),
                          guild: guild,
                        );
                      case 'reload':
                        refreshLibrary(context);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'select',
                      child: Text(
                        library.selecting
                            ? 'Stop selecting'
                            : 'Select channels',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'all',
                      child: Text('Export every channel'),
                    ),
                    const PopupMenuItem(value: 'reload', child: Text('Reload')),
                  ],
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SidebarHeader(title: guild.guild.name, menu: true),
                  ),
                ),
              Expanded(child: _content(library, guild)),
              if (library.selecting && guild != null)
                SelectionBar(
                  channels: library.selectedChannels,
                  guild: guild,
                  all: guild.exportable,
                ),
              SizedBox(height: widget.room),
            ],
          );
        },
      ),
    );
  }

  Widget _content(Library library, GuildState? guild) {
    if (library.state == LoadState.failed) {
      return _Problem(
        text: library.error ?? 'Could not load servers',
        onRetry: library.load,
      );
    }
    if (guild == null) {
      return library.state == LoadState.loading
          ? const Center(child: CircularProgressIndicator())
          : const _Problem(
              text: 'This bot is not in any servers yet. Invite it to a server and reload.',
            );
    }
    if (guild.state == LoadState.loading || guild.state == LoadState.idle) {
      return const Center(child: CircularProgressIndicator());
    }
    if (guild.state == LoadState.failed) {
      return _Problem(
        text: guild.error ?? 'Could not load channels',
        onRetry: () => library.selectGuild(guild.guild.id),
      );
    }
    if (guild.channels.isEmpty) {
      return const _Problem(
        text: 'The bot cannot read any channels here. Give it View Channel and Read Message History.',
      );
    }
    final rows = <Widget>[];
    String? category;
    for (final channel in guild.channels) {
      if (channel.isCategory) {
        category = channel.id;
        final collapsed = _collapsed.contains(channel.id);
        rows.add(
          Clickable(
            onTap: () => setState(
              () => collapsed
                  ? _collapsed.remove(channel.id)
                  : _collapsed.add(channel.id),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      channel.displayName,
                      style: Styles.sectionLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    collapsed
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more_rounded,
                    size: 14,
                    color: Palette.channel,
                  ),
                ],
              ),
            ),
          ),
        );
        continue;
      }
      if (category != null &&
          _collapsed.contains(category) &&
          library.selectedChannel?.id != channel.id) {
        continue;
      }
      rows.add(
        ChannelRow(
          channel: channel,
          selected: library.selectedChannel?.id == channel.id,
          checkbox: library.selecting,
          checked: library.selection.contains(channel.id),
          onTap: () => library.selecting
              ? library.toggleSelected(channel)
              : widget.onOpen(channel),
        ),
      );
    }
    // one height for every row keeps the scrollbar from jumping
    return _PullToRefresh(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 12),
        prototypeItem: ChannelRow(
          channel: guild.channels.firstWhere((c) => !c.isCategory),
          onTap: () {},
        ),
        children: rows,
      ),
    );
  }
}

class DmSidebar extends StatefulWidget {
  const DmSidebar({
    super.key,
    required this.onOpen,
    this.room = UserPanel.room,
  });

  final ValueChanged<Channel> onOpen;
  final double room;

  @override
  State<DmSidebar> createState() => _DmSidebarState();
}

class _DmSidebarState extends State<DmSidebar> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    final compact = isCompact(context);
    return Container(
      color: Palette.sidebar,
      child: ListenableBuilder(
        listenable: Listenable.merge([library, _search]),
        builder: (context, _) {
          final query = _search.text.trim().toLowerCase();
          final dms = library.dms
              .where(
                (c) =>
                    query.isEmpty ||
                    c.displayName.toLowerCase().contains(query),
              )
              .toList();
          return Column(
            children: [
              Container(
                height: compact ? 56 : 48,
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Palette.sidebar,
                  border: Styles.underline,
                ),
                child: TextField(
                  controller: _search,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: compact ? 16 : 14),
                  decoration: InputDecoration(
                    hintText: 'Find a conversation',
                    hintStyle: const TextStyle(
                      color: Palette.header,
                      fontWeight: FontWeight.w500,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: compact ? 10 : 7,
                    ),
                    fillColor: Palette.hover,
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 2),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Direct Messages',
                        style: Styles.sectionLabel,
                      ),
                    ),
                    const RefreshButton(),
                    IconButton(
                      onPressed: library.toggleSelecting,
                      tooltip: library.selecting
                          ? 'Stop selecting'
                          : 'Select conversations',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        library.selecting
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 18,
                        color: library.selecting
                            ? Palette.header
                            : Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _list(library, dms)),
              if (library.selecting)
                SelectionBar(
                  channels: library.selectedChannels,
                  all: library.dms,
                ),
              SizedBox(height: widget.room),
            ],
          );
        },
      ),
    );
  }

  Widget _list(Library library, List<Channel> dms) {
    if (library.state == LoadState.failed) {
      return _Problem(
        text: library.error ?? 'Could not load conversations',
        onRetry: library.load,
      );
    }
    if (library.state != LoadState.ready) {
      return const Center(child: CircularProgressIndicator());
    }
    if (dms.isEmpty) return const _Problem(text: 'No conversations found.');
    // one height for every row keeps the scrollbar from jumping
    return _PullToRefresh(
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
        prototypeItem: _row(
          library,
          dms.firstWhere((c) => c.isGroupDm, orElse: () => dms.first),
        ),
        itemCount: dms.length,
        itemBuilder: (context, index) => _row(library, dms[index]),
      ),
    );
  }

  Widget _row(Library library, Channel dm) => HoverTile(
    selected: library.selectedChannel?.id == dm.id,
    onTap: () =>
        library.selecting ? library.toggleSelected(dm) : widget.onOpen(dm),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    child: Row(
      children: [
        GroupIcon(channel: dm),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dm.displayName,
                style: TextStyle(
                  color: library.selectedChannel?.id == dm.id
                      ? Palette.header
                      : Palette.muted,
                  fontSize: 16,
                  fontWeight: library.selectedChannel?.id == dm.id
                      ? FontWeight.w600
                      : FontWeight.w500,
                  height: 18 / 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (dm.isGroupDm)
                Text(
                  '${dm.recipients.length + 1} Members',
                  style: Styles.tiny.copyWith(
                    color: library.selectedChannel?.id == dm.id
                        ? Palette.text
                        : null,
                    height: 14 / 12,
                  ),
                ),
            ],
          ),
        ),
        if (library.selecting)
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: library.selection.contains(dm.id),
              onChanged: (_) => library.toggleSelected(dm),
            ),
          ),
      ],
    ),
  );
}

class ServerList extends StatelessWidget {
  const ServerList({super.key, required this.onGuild});

  final ValueChanged<String> onGuild;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    return Container(
      color: Palette.sidebar,
      child: ListenableBuilder(
        listenable: library,
        builder: (context, _) => Column(
          children: [
            const SidebarHeader(title: 'Servers', trailing: RefreshButton()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8),
                children: [
                  for (final g in library.guilds)
                    HoverTile(
                      onTap: () => onGuild(g.guild.id),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Container(
                              width: 32,
                              height: 32,
                              color: Palette.hover,
                              alignment: Alignment.center,
                              child: GuildIcon(guild: g.guild, size: 32),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              g.guild.name,
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: UserPanel.room),
          ],
        ),
      ),
    );
  }
}

class UserPanel extends StatelessWidget {
  const UserPanel({super.key});

  static const room = 64.0;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final account = session.account;
        if (account == null) return const SizedBox.shrink();
        return Container(
          height: 56,
          decoration: Styles.card.copyWith(boxShadow: Styles.lift),
          padding: const EdgeInsets.only(left: 8, right: 4),
          child: Row(
            children: [
              UserAvatar(user: account.user, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      style: const TextStyle(
                        color: Palette.header,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      session.isBot ? 'Bot account' : account.user.tag,
                      style: const TextStyle(
                        color: Palette.subtle,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => openSettings(context),
                tooltip: 'Settings',
                icon: const Icon(
                  Icons.settings_rounded,
                  size: 20,
                  color: Palette.subtle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center, style: Styles.small),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            DiscordButton(
              label: 'Try again',
              tone: ButtonTone.secondary,
              dense: true,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    ),
  );
}
