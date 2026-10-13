import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/discord/api.dart';
import '../../core/discord/models.dart';
import '../../core/export/dates.dart';
import '../export/export_sheet.dart';
import '../scope.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'message_actions.dart';
import 'message_list.dart';
import 'message_search.dart';
import 'message_skeleton.dart';
import 'pinned_messages.dart';

enum _Panel { search, pins }

class ChannelView extends StatefulWidget {
  const ChannelView({
    super.key,
    required this.channel,
    this.guild,
    this.onBack,
    this.actions = const [],
    this.aside,
  });

  final Channel channel;
  final GuildState? guild;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? aside;

  @override
  State<ChannelView> createState() => _ChannelViewState();
}

class _ChannelViewState extends State<ChannelView> {
  static const _panelWidth = 400.0;

  final _messages = <Message>[];
  final _scroll = ScrollController();
  late PreviewResolver _resolver;
  bool _loading = false;
  bool _loadingNewer = false;
  bool _reachedStart = false;
  bool _reachedEnd = true;
  _Panel? _panel;
  String? _anchorId;
  String? _flashId;
  Timer? _flash;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolver = _newResolver();
    _scroll.addListener(_onScroll);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ChannelView old) {
    super.didUpdateWidget(old);
    if (old.channel.id != widget.channel.id) {
      _generation++;
      _messages.clear();
      _reachedStart = false;
      _reachedEnd = true;
      _loadingNewer = false;
      _anchorId = null;
      _endFlash();
      _panel = null;
      _error = null;
      _resolver = _newResolver();
      unawaited(_load());
    }
  }

  PreviewResolver _newResolver() => PreviewResolver(
    dates: DateFormatter(locale: AppScope.of(context).locale),
    guild: widget.guild,
  );

  void _endFlash() {
    _flash?.cancel();
    _flashId = null;
  }

  @override
  void dispose() {
    _flash?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - 400) unawaited(_load());
    if (position.pixels < position.minScrollExtent + 400) {
      unawaited(_loadNewer());
    }
  }

  Future<void> _load() async {
    if (_loading || _reachedStart || !widget.channel.hasMessages) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final page = await AppScope.of(context).library.fetchMessages(
        widget.channel,
        before: _messages.isEmpty ? null : _messages.first.id,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages.insertAll(0, page);
        _resolver.learn(page);
        _reachedStart = page.length < 50;
        _loading = false;
      });
    } on DiscordException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = e is ForbiddenException
            ? 'You can\'t read this channel.'
            : e.message;
      });
    }
  }

  // After a jump the newest messages aren't loaded yet; they come in as the
  // list is scrolled down.
  Future<void> _loadNewer() async {
    if (_loadingNewer || _reachedEnd || _messages.isEmpty) return;
    final generation = _generation;
    _loadingNewer = true;
    try {
      final page = await AppScope.of(context).library
          .fetchMessages(widget.channel, after: _messages.last.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages.addAll(page);
        _resolver.learn(page);
        _reachedEnd = page.length < 50;
      });
    } on DiscordException {
      // retried on the next scroll
    } finally {
      if (generation == _generation) _loadingNewer = false;
    }
  }

  Future<void> _jumpTo(Message target) async {
    final generation = ++_generation;
    setState(() {
      _messages.clear();
      _anchorId = target.id;
      _endFlash();
      _reachedStart = false;
      _reachedEnd = false;
      _loading = true;
      _loadingNewer = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      final page = await AppScope.of(context).library
          .fetchMessages(widget.channel, around: target.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages.addAll(page);
        _resolver.learn(page);
        _loading = false;
        _flashId = target.id;
        _reachedEnd =
            page.isEmpty || page.last.id == widget.channel.lastMessageId;
      });
      _flash = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _flashId = null);
      });
      // no scroll event comes when the target already sits at either end
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && _scroll.hasClients) {
          _onScroll();
        }
      });
    } on DiscordException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _jumpToPresent() {
    _generation++;
    setState(() {
      _messages.clear();
      _anchorId = null;
      _endFlash();
      _reachedStart = false;
      _reachedEnd = true;
      _loading = false;
      _loadingNewer = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_load());
  }

  bool _fitsBeside(double width) => width >= _panelWidth + 360;

  String? get _subtitle {
    final channel = widget.channel;
    if (channel.isGroupDm) return '${channel.recipients.length + 1} Members';
    if (channel.isDm) return channel.recipients.firstOrNull?.tag;
    return widget.guild?.guild.name;
  }

  Future<void> _open(_Panel panel) async {
    if (!isCompact(context) && _fitsBeside(context.size!.width)) {
      setState(() => _panel = _panel == panel ? null : panel);
      return;
    }
    final picked = await Navigator.of(context).push<Message>(
      MaterialPageRoute(
        builder: (_) => switch (panel) {
          _Panel.search => MessageSearchPage(
            channel: widget.channel,
            guild: widget.guild,
          ),
          _Panel.pins => PinnedMessagesPage(
            channel: widget.channel,
            guild: widget.guild,
          ),
        },
      ),
    );
    if (picked != null && mounted) await _jumpTo(picked);
  }

  Future<void> _export() =>
      showExportSheet(context, channels: [widget.channel], guild: widget.guild);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _build(constraints.maxWidth),
  );

  Widget _build(double width) {
    final channel = widget.channel;
    final compact = isCompact(context);
    final panel = compact || !_fitsBeside(width) ? null : _panel;
    final chat = Column(
      children: [
        _Header(
          channel: channel,
          subtitle: compact ? _subtitle : null,
          onBack: widget.onBack,
          actions: [
            if (channel.hasMessages) ...[
              IconButton(
                onPressed: () => _open(_Panel.pins),
                tooltip: 'Pinned messages',
                icon: Icon(
                  Icons.push_pin_rounded,
                  color: panel == _Panel.pins ? Palette.header : Palette.muted,
                ),
              ),
              IconButton(
                onPressed: () => _open(_Panel.search),
                tooltip: 'Search messages',
                icon: Icon(
                  Icons.search_rounded,
                  color: panel == _Panel.search
                      ? Palette.header
                      : Palette.muted,
                ),
              ),
            ],
            IconButton(
              onPressed: _export,
              tooltip: 'Export this channel',
              icon: const Icon(Icons.download_rounded, color: Palette.muted),
            ),
            ...widget.actions,
          ],
        ),
        Expanded(child: _body()),
        if (_anchorId != null && !_reachedEnd)
          _PresentBar(onTap: _jumpToPresent, compact: compact),
        _ExportBar(channel: channel, onTap: _export, compact: compact),
      ],
    );
    void close() => setState(() => _panel = null);
    final beside = panel == null
        ? widget.aside
        : Container(
            width: _panelWidth,
            decoration: const BoxDecoration(
              color: Palette.sidebar,
              border: Border(left: BorderSide(color: Palette.divider)),
            ),
            child: switch (panel) {
              _Panel.search => MessageSearch(
                channel: channel,
                guild: widget.guild,
                onOpen: _jumpTo,
                onClose: close,
              ),
              _Panel.pins => PinnedMessages(
                channel: channel,
                guild: widget.guild,
                onOpen: _jumpTo,
                onClose: close,
              ),
            },
          );
    return Container(
      color: Palette.chat,
      child: beside == null
          ? chat
          : Row(
              children: [
                Expanded(child: chat),
                beside,
              ],
            ),
    );
  }

  Widget _body() {
    final channel = widget.channel;
    if (!channel.hasMessages) {
      return _Notice(
        icon: Icons.forum_outlined,
        title: channel.isThreadOnly
            ? 'Posts live in threads'
            : 'Nothing to show',
        text: channel.isThreadOnly
            ? 'Exporting this channel exports every post in it as its own thread.'
            : 'This channel has no messages to preview.',
      );
    }
    if (_error != null && _messages.isEmpty) {
      return _Notice(
        icon: Icons.lock_outline_rounded,
        title: 'Can\'t load messages',
        text: _error!,
      );
    }
    if (_messages.isEmpty && _loading) return const MessageSkeleton();
    return MessageList(
      messages: _messages,
      resolver: _resolver,
      controller: _scroll,
      anchorId: _anchorId,
      flashId: _flashId,
      actions: MessageActions(channel: channel, guild: widget.guild),
      bottom: _reachedEnd ? null : const MessageSkeleton(groups: 3),
      top: _reachedStart
          ? _ChannelStart(channel: channel)
          : const MessageSkeleton(groups: 3),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.channel,
    required this.actions,
    this.subtitle,
    this.onBack,
  });

  final Channel channel;
  final List<Widget> actions;
  final String? subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final topic = channel.topic;
    final compact = isCompact(context);
    return Container(
      height: compact ? 56 : 48,
      padding: EdgeInsets.only(left: onBack == null ? 16 : 4, right: 8),
      decoration: const BoxDecoration(
        color: Palette.chat,
        border: Styles.underline,
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: Palette.text),
            ),
          if (channel.isPrivate)
            GroupIcon(channel: channel, size: compact ? 32 : 24)
          else
            ChannelGlyph(channel, size: 24),
          SizedBox(width: compact ? 10 : 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showTopic =
                    topic != null && topic.trim().isNotEmpty && !compact;
                final name = Text(
                  channel.displayName,
                  style: TextStyle(
                    color: Palette.header,
                    fontSize: compact ? 17 : 16,
                    fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
                    height: compact ? 1.2 : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                );
                if (subtitle != null) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      name,
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Palette.muted,
                          fontSize: 13,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: max(
                          0.0,
                          constraints.maxWidth - (showTopic ? 25 : 0),
                        ),
                      ),
                      child: name,
                    ),
                    if (showTopic) ...[
                      Container(
                        width: 1,
                        height: 24,
                        color: Palette.divider,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      Expanded(
                        child: Text(
                          topic.replaceAll('\n', ' '),
                          style: Styles.small,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _PresentBar extends StatelessWidget {
  const _PresentBar({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(compact ? 16 : 8, 0, compact ? 16 : 8, 8),
    child: Material(
      color: Palette.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Palette.divider),
      ),
      child: InkWell(
        onTap: onTap,
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'You\'re viewing older messages',
                  style: TextStyle(color: Palette.text, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Jump to present',
                style: TextStyle(
                  color: Palette.link,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.south_rounded, size: 16, color: Palette.link),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ExportBar extends StatelessWidget {
  const _ExportBar({
    required this.channel,
    required this.onTap,
    required this.compact,
  });

  final Channel channel;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(compact ? 24 : 8);
    // phone buttons already carry their own tap padding
    final inset = isMobileOS ? 4.0 : 12.0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(16, 0, 16, 12)
            : const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Material(
          color: Palette.field,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: const BorderSide(color: Palette.divider),
          ),
          child: InkWell(
            onTap: onTap,
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, inset, 12, inset),
              child: Row(
                children: [
                  const Icon(
                    Icons.download_for_offline_rounded,
                    color: Palette.muted,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Export ${channel.isPrivate ? channel.displayName : '#${channel.displayName}'}',
                      style: TextStyle(
                        color: compact ? Palette.faint : Palette.prompt,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DiscordButton(
                    label: 'Export',
                    dense: true,
                    radius: compact ? 16 : 8,
                    onPressed: onTap,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelStart extends StatelessWidget {
  const _ChannelStart({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (channel.isPrivate)
          GroupIcon(channel: channel, size: 80)
        else
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: Palette.selected,
              shape: BoxShape.circle,
            ),
            child: ChannelGlyph(channel, size: 42, color: Palette.header),
          ),
        const SizedBox(height: 8),
        Text(
          channel.isPrivate
              ? channel.displayName
              : 'Welcome to #${channel.displayName}!',
          style: const TextStyle(
            color: Palette.header,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          channel.isPrivate
              ? 'This is the beginning of your direct message history.'
              : 'This is the start of the #${channel.displayName} channel.',
          style: const TextStyle(color: Palette.muted, fontSize: 16),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Palette.faint),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Palette.header,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: Styles.small),
        ],
      ),
    ),
  );
}
