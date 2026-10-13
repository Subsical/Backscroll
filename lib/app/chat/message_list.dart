import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/discord/models.dart';
import '../../core/export/dates.dart';
import '../../core/export/writers/system_text.dart';
import '../../core/markdown/emoji.dart';
import '../../core/markdown/renderers.dart';
import '../../core/util/html.dart';
import '../scope.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/row_extents.dart';
import '../widgets/scrollbars.dart';
import 'markdown_text.dart';
import 'message_actions.dart';

class PreviewResolver implements MarkdownResolver {
  PreviewResolver({required this.dates, this.guild});

  final DateFormatter dates;
  final GuildState? guild;
  final users = <String, DiscordUser>{};
  Map<String, Channel> channels = const {};

  void learn(List<Message> messages) {
    for (final m in messages) {
      users[m.author.id] = m.author;
      for (final u in m.mentions) {
        users[u.id] = u;
      }
      if (m.referenced != null) {
        users[m.referenced!.author.id] = m.referenced!.author;
      }
    }
    if (guild != null) channels = {for (final c in guild!.channels) c.id: c};
  }

  String displayName(DiscordUser user) {
    final nick = guild?.members[user.id]?.nick;
    return nick == null || nick.isEmpty ? user.displayName : nick;
  }

  Color? nameColor(String userId) {
    final color = guild?.nameColor(userId);
    return color == null ? null : Color(0xFF000000 | color);
  }

  @override
  String? userName(String id) {
    final user = users[id];
    final nick = guild?.members[id]?.nick;
    if (nick != null && nick.isNotEmpty) return nick;
    return user?.displayName;
  }

  @override
  RoleInfo? role(String id) {
    final role = guild?.roles[id];
    return role == null ? null : RoleInfo(role.name, role.color);
  }

  @override
  String? channelName(String id) => channels[id]?.displayName;

  @override
  String media(String url) => url;

  @override
  String timestamp(DateTime time, String? style) => dates.styled(time, style);

  @override
  String fullTimestamp(DateTime time) => dates.full(time);
}

bool _continues(
  Message previous,
  Message next,
  DateFormatter dates,
  int groupSize,
) =>
    groupSize < 50 &&
    previous.isRegular &&
    next.isRegular &&
    !next.isReply &&
    next.interaction == null &&
    previous.author.id == next.author.id &&
    next.timestamp.difference(previous.timestamp).inMinutes < 7 &&
    dates.dayKey(previous.timestamp) == dates.dayKey(next.timestamp);

sealed class _Row {}

class _DayRow extends _Row {
  _DayRow(this.day);
  final DateTime day;
}

class _MessageRow extends _Row {
  _MessageRow(this.message, this.first);
  final Message message;
  final bool first;
}

class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.messages,
    required this.resolver,
    this.top,
    this.bottom,
    this.controller,
    this.anchorId,
    this.flashId,
    this.actions,
  });

  final List<Message> messages;
  final PreviewResolver resolver;
  final Widget? top;
  final Widget? bottom;
  final ScrollController? controller;

  final String? anchorId;
  final String? flashId;
  final MessageActions? actions;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  static const _center = ValueKey('center');

  final _extents = RowExtents();
  final _shown = <String, _HoverState>{};
  final _moved = _Moved();
  final _bar = ValueNotifier<String?>(null);
  final _focus = ValueNotifier<String?>(null);
  var _byId = <String, Message>{};
  String? _hovered;
  String? _held;
  bool _overBar = false;

  @override
  void dispose() {
    _moved.dispose();
    _bar.dispose();
    _focus.dispose();
    super.dispose();
  }

  RenderBox? _rowOf(String id) {
    final row = _shown[id];
    return row == null ? null : row.context.findRenderObject() as RenderBox?;
  }

  bool _scrolled(Notification notification) {
    _moved.tell();
    return false;
  }

  void _settle() {
    if (!mounted) return;
    if (_held == null && !_overBar) _bar.value = _hovered;
    _focus.value = _held ?? (_overBar ? _bar.value : null);
  }

  // a pointer leaves one row before it enters the next, or the toolbar
  void _hover(String id, bool over) {
    if (over) {
      _hovered = id;
    } else if (_hovered == id) {
      _hovered = null;
    }
    scheduleMicrotask(_settle);
  }

  void _hoverBar(bool over) {
    _overBar = over;
    scheduleMicrotask(_settle);
  }

  Future<void> _choose(
    Message message,
    Future<MessageAction?> Function(List<MessageAction> actions) ask,
  ) async {
    final actions = widget.actions;
    if (actions == null) return;
    _held = message.id;
    _bar.value = message.id;
    _settle();
    final picked = await ask(actions.of(message));
    _held = null;
    _settle();
    if (picked != null && mounted) await actions.run(context, picked, message);
  }

  Future<void> _hold(Message message) => _choose(
    message,
    (actions) => showMessageSheet(context, actions: actions),
  );

  Future<void> _menu(Message message, Rect anchor) => _choose(
    message,
    (actions) => showMessageMenu(
      context,
      actions: actions,
      position: RelativeRect.fromRect(
        anchor,
        Offset.zero & MediaQuery.sizeOf(context),
      ),
    ),
  );

  Widget _toolbar(BuildContext context, String? id, Widget? child) {
    final message = _byId[id];
    final actions = widget.actions;
    if (message == null || actions == null) {
      // a region taken out of the tree never reports the pointer leaving
      _overBar = false;
      return const SizedBox.shrink();
    }
    return _BesideRow(
      row: () => _rowOf(message.id),
      moved: _moved,
      child: MouseRegion(
        onEnter: (_) => _hoverBar(true),
        onExit: (_) => _hoverBar(false),
        child: _Toolbar(
          actions: actions.of(message),
          onAction: (action) => actions.run(context, action, message),
          onMore: (button) => _menu(message, button),
        ),
      ),
    );
  }

  List<_Row> _rows() {
    final resolver = widget.resolver;
    final rows = <_Row>[];
    Message? previous;
    var groupSize = 0;
    String? day;
    for (final m in widget.messages) {
      final key = resolver.dates.dayKey(m.timestamp);
      if (key != day) {
        rows.add(_DayRow(m.timestamp));
        day = key;
        previous = null;
      }
      final first =
          previous == null ||
          !_continues(previous, m, resolver.dates, groupSize);
      groupSize = first ? 1 : groupSize + 1;
      rows.add(_MessageRow(m, first));
      previous = m;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final resolver = widget.resolver;
    final anchorId = widget.anchorId;
    final top = widget.top;
    final bottom = widget.bottom;
    final rows = _rows();
    var split = rows.length;
    if (anchorId != null) {
      final index = rows.indexWhere(
        (r) => r is _MessageRow && r.message.id == anchorId,
      );
      if (index >= 0) split = index + 1;
    }
    final older = rows.sublist(0, split).reversed.toList();
    final newer = rows.sublist(split);
    final anchored = split < rows.length || bottom != null;

    Widget build(_Row row) => switch (row) {
      _DayRow(:final day) => _DayDivider(resolver.dates.day(day)),
      _MessageRow(:final message, :final first) => MessageTile(
        message: message,
        first: first,
        resolver: resolver,
        highlight: message.id == widget.flashId,
      ),
    };

    Object id(_Row row) => switch (row) {
      _DayRow(:final day) => resolver.dates.dayKey(day),
      _MessageRow(:final message) => message.id,
    };

    SliverList list(List<_Row> rows, Widget? end, String endId) => SliverList(
      delegate: MeasuredRows(
        extents: _extents,
        idOf: (index) => index == rows.length ? endId : id(rows[index]),
        extraOf: (index) => switch (rows.elementAtOrNull(index)) {
          _MessageRow(:final message) => _mediaHeight(message),
          _ => 0,
        },
        builder: (context, index) =>
            index == rows.length ? end! : build(rows[index]),
        childCount: rows.length + (end == null ? 0 : 1),
      ),
    );

    _byId = {for (final m in widget.messages) m.id: m};
    // The list is reversed: the centre sliver holds the anchor and everything
    // above it, the one before it everything newer. Messages loaded later
    // grow away from the anchor in both directions, so the view doesn't move.
    final scroll = ScrollConfiguration(
      behavior: const AppScrollBehavior(thickness: 8),
      child: CustomScrollView(
        controller: widget.controller,
        reverse: true,
        center: _center,
        anchor: anchored ? 0.4 : 0,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(bottom: anchored ? 16 : 0),
            sliver: list(newer, bottom, 'bottom'),
          ),
          SliverPadding(
            key: _center,
            padding: EdgeInsets.only(bottom: anchored ? 0 : 16),
            sliver: list(older, top, 'top'),
          ),
        ],
      ),
    );
    if (widget.actions == null) return scroll;
    return _ListScope(
      list: this,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<ScrollMetricsNotification>(
              onNotification: _scrolled,
              child: NotificationListener<ScrollNotification>(
                onNotification: _scrolled,
                child: scroll,
              ),
            ),
            if (!isMobileOS)
              Positioned(
                left: 0,
                top: 0,
                child: ValueListenableBuilder(
                  valueListenable: _bar,
                  builder: _toolbar,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListScope extends InheritedWidget {
  const _ListScope({required this.list, required super.child});

  final _MessageListState list;

  @override
  bool updateShouldNotify(_ListScope oldWidget) => false;
}

class _Moved extends ChangeNotifier {
  void tell() => notifyListeners();
}

class _BesideRow extends SingleChildRenderObjectWidget {
  const _BesideRow({required this.row, required this.moved, super.child});

  final RenderBox? Function() row;
  final Listenable moved;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBesideRow(row, moved);

  @override
  void updateRenderObject(BuildContext context, _RenderBesideRow renderObject) {
    renderObject
      ..row = row
      ..markNeedsPaint();
  }
}

// sits over the top right corner of a row, wherever the row has scrolled to
class _RenderBesideRow extends RenderProxyBox {
  _RenderBesideRow(this.row, this._moved);

  RenderBox? Function() row;
  final Listenable _moved;
  Offset? _at;

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _moved.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _moved.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final row = this.row();
    final child = this.child;
    _at = null;
    if (child == null || row == null || !row.attached) return;
    final corner = globalToLocal(row.localToGlobal(Offset(row.size.width, 0)));
    final at = corner - Offset(child.size.width + 30, 16);
    _at = at;
    context.paintChild(child, offset + at);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final at = _at;
    if (at != null) transform.translateByDouble(at.dx, at.dy, 0, 1);
  }

  // the wheel and the pointer still reach the rows under the toolbar
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final at = _at;
    final child = this.child;
    if (at != null && child != null) {
      result.addWithPaintOffset(
        offset: at,
        position: position,
        hitTest: (result, position) =>
            child.hitTest(result, position: position),
      );
    }
    return false;
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.actions,
    required this.onAction,
    required this.onMore,
  });

  final List<MessageAction> actions;
  final ValueChanged<MessageAction> onAction;
  final ValueChanged<Rect> onMore;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: Styles.card.copyWith(
      boxShadow: const [
        BoxShadow(
          color: Color(0x29000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actions)
          if (action != MessageAction.copyId)
            _BarButton(
              icon: action.icon,
              tooltip: action.label,
              onTap: (_) => onAction(action),
            ),
        _BarButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'More',
          onTap: (button) => onMore(
            Rect.fromLTWH(button.left, button.bottom + 4, button.width, 0),
          ),
        ),
      ],
    ),
  );
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final ValueChanged<Rect> onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    preferBelow: false,
    child: IconButton(
      onPressed: () {
        final box = context.findRenderObject()! as RenderBox;
        onTap(box.localToGlobal(Offset.zero) & box.size);
      },
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: Palette.subtle,
        hoverColor: Palette.hover,
        iconSize: 20,
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(28),
        maximumSize: const Size.square(28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
  );
}

class _DayDivider extends StatelessWidget {
  const _DayDivider(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    // phones get a brighter hairline, like the phone app
    final line = Expanded(
      child: isCompact(context)
          ? const Divider(color: Palette.muted, height: 1, thickness: 0)
          : const Divider(color: Palette.divider, height: 1),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              text,
              style: const TextStyle(
                color: Palette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

class _Hover extends StatefulWidget {
  const _Hover({required this.message, required this.builder});

  final Message message;
  final Widget Function(bool hover) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  late final _list = context.getInheritedWidgetOfExactType<_ListScope>()?.list;
  bool _hover = false;

  void _set(bool hover) {
    setState(() => _hover = hover);
    _list?._hover(widget.message.id, hover);
  }

  @override
  void initState() {
    super.initState();
    _list?._shown[widget.message.id] = this;
  }

  @override
  void didUpdateWidget(_Hover old) {
    super.didUpdateWidget(old);
    final list = _list;
    if (list == null || old.message.id == widget.message.id) return;
    if (list._shown[old.message.id] == this) list._shown.remove(old.message.id);
    list._shown[widget.message.id] = this;
    if (_hover) {
      list._hover(old.message.id, false);
      list._hover(widget.message.id, true);
    }
  }

  @override
  void dispose() {
    final list = _list;
    final id = widget.message.id;
    if (list != null && list._shown[id] == this) list._shown.remove(id);
    if (_hover) list?._hover(id, false);
    super.dispose();
  }

  Widget _band(bool on) => Container(
    color: on ? Palette.hover : Colors.transparent,
    child: widget.builder(on),
  );

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final message = widget.message;
    return MouseRegion(
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: list == null
          ? _band(_hover)
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              supportedDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
              },
              onLongPress: () => list._hold(message),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapUp: (details) =>
                    list._menu(message, details.globalPosition & Size.zero),
                child: ValueListenableBuilder(
                  valueListenable: list._focus,
                  builder: (context, focus, _) =>
                      _band(focus == null ? _hover : focus == message.id),
                ),
              ),
            ),
    );
  }
}

class MessageCard extends StatelessWidget {
  const MessageCard({
    super.key,
    required this.message,
    required this.resolver,
    required this.onTap,
  });

  final Message message;
  final PreviewResolver resolver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Palette.chat,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Palette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        mouseCursor: WidgetStateMouseCursor.clickable,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: IgnorePointer(
            child: MessageTile(
              message: message,
              first: true,
              resolver: resolver,
            ),
          ),
        ),
      ),
    ),
  );
}

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.first,
    required this.resolver,
    this.highlight = false,
  });

  final Message message;
  final bool first;
  final PreviewResolver resolver;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final line = systemLine(message, guildName: resolver.guild?.guild.name);
    if (line != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _Hover(
          message: message,
          builder: (_) =>
              _SystemTile(message: message, line: line, resolver: resolver),
        ),
      );
    }
    final shown =
        message.type == MessageType.threadStarter && message.referenced != null
        ? message.referenced!
        : message;
    final compact = isCompact(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 16 : 0),
      child: _Hover(
        message: message,
        builder: (hover) => TweenAnimationBuilder<double>(
          tween: Tween(end: highlight ? 1 : 0),
          duration: highlight
              ? Duration.zero
              : const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (context, glow, child) => Container(
            decoration: glow == 0
                ? null
                : BoxDecoration(
                    color: Palette.blurple.withValues(alpha: 0.16 * glow),
                    border: Border(
                      left: BorderSide(
                        color: Palette.blurple.withValues(alpha: glow),
                        width: 2,
                      ),
                    ),
                  ),
            padding: EdgeInsets.fromLTRB(
              glow == 0 ? 16 : 14,
              2,
              compact ? 12 : 48,
              2,
            ),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (first && message.isReply)
                _ReplyLine(message: message, resolver: resolver),
              if (first && message.interaction != null)
                _InteractionLine(
                  interaction: message.interaction!,
                  resolver: resolver,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    child: first
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: UserAvatar(user: shown.author),
                          )
                        : hover
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            // am and pm times are wider than the avatar
                            child: OverflowBox(
                              fit: OverflowBoxFit.deferToChild,
                              alignment: Alignment.centerRight,
                              minWidth: 0,
                              maxWidth: 56,
                              child: Text(
                                resolver.dates.time(message.timestamp),
                                style: const TextStyle(
                                  color: Palette.faint,
                                  fontSize: 10.5,
                                ),
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _Body(
                      message: shown,
                      first: first,
                      resolver: resolver,
                      thread: message.thread,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.message,
    required this.first,
    required this.resolver,
    this.thread,
  });

  final Message message;
  final bool first;
  final PreviewResolver resolver;
  final Channel? thread;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (first) children.add(_Header(message: message, resolver: resolver));
    if (message.content.isNotEmpty) {
      children.add(
        MarkdownText(
          message.content,
          resolver: resolver,
          trailing: message.editedTimestamp == null
              ? null
              : WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Tooltip(
                    message: resolver.dates.full(message.editedTimestamp!),
                    child: const Text(
                      ' (edited)',
                      style: TextStyle(fontSize: 10, color: Palette.faint),
                    ),
                  ),
                ),
        ),
      );
    }
    for (final f in message.forwards) {
      children.add(_Forward(forward: f, resolver: resolver));
    }
    for (final a in message.attachments) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _AttachmentView(a),
        ),
      );
    }
    for (final e in mergeGalleryEmbeds(message.embeds)) {
      if (e.type == 'poll_result') continue;
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _EmbedView(embed: e, resolver: resolver),
        ),
      );
    }
    for (final s in message.stickers) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: s.isLottie
              ? _StickerName(s.name)
              : Image(
                  image: AppScope.of(context).images(s.url),
                  width: 160,
                  height: 160,
                  errorBuilder: (_, _, _) => _StickerName(s.name),
                ),
        ),
      );
    }
    if (message.poll != null) children.add(_PollView(poll: message.poll!));
    if (message.components.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _Components(
            components: message.components,
            resolver: resolver,
          ),
        ),
      );
    }
    if (thread != null) children.add(_ThreadCard(thread: thread!));
    if (message.reactions.isNotEmpty) {
      children.add(_Reactions(message.reactions));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.message, required this.resolver});

  final Message message;
  final PreviewResolver resolver;

  @override
  Widget build(BuildContext context) {
    final author = message.author;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(
            resolver.displayName(author),
            style: TextStyle(
              color: resolver.nameColor(author.id) ?? Palette.header,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (author.bot || message.webhookId != null) const Pill('APP'),
          Text(
            resolver.dates.short(message.timestamp),
            style: const TextStyle(color: Palette.faint, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ReplyLine extends StatelessWidget {
  const _ReplyLine({required this.message, required this.resolver});

  final Message message;
  final PreviewResolver resolver;

  @override
  Widget build(BuildContext context) {
    final ref = message.referenced;
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 4),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 10,
            margin: const EdgeInsets.only(top: 8, right: 4),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Palette.spine, width: 2),
                top: BorderSide(color: Palette.spine, width: 2),
              ),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(6)),
            ),
          ),
          if (ref == null)
            const Text(
              'Original message was deleted',
              style: TextStyle(
                color: Palette.muted,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            )
          else ...[
            UserAvatar(user: ref.author, size: 16),
            const SizedBox(width: 4),
            Text(
              resolver.displayName(ref.author),
              style: TextStyle(
                color: resolver.nameColor(ref.author.id) ?? Palette.header,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ref.content.isEmpty
                  ? const Text(
                      'Click to see attachment',
                      style: TextStyle(
                        color: Palette.muted,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : MarkdownText(
                      ref.content,
                      resolver: resolver,
                      singleLine: true,
                      style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 14,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InteractionLine extends StatelessWidget {
  const _InteractionLine({required this.interaction, required this.resolver});

  final InteractionInfo interaction;
  final PreviewResolver resolver;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 20, bottom: 4),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 10,
          margin: const EdgeInsets.only(top: 8, right: 4),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Palette.spine, width: 2),
              top: BorderSide(color: Palette.spine, width: 2),
            ),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(6)),
          ),
        ),
        UserAvatar(user: interaction.user, size: 16),
        const SizedBox(width: 4),
        Text(
          resolver.displayName(interaction.user),
          style: TextStyle(
            color: resolver.nameColor(interaction.user.id) ?? Palette.header,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Text(
          ' used ',
          style: TextStyle(color: Palette.muted, fontSize: 14),
        ),
        Text(
          '/${interaction.name ?? 'command'}',
          style: const TextStyle(color: Palette.link, fontSize: 14),
        ),
      ],
    ),
  );
}

class _SystemTile extends StatelessWidget {
  const _SystemTile({
    required this.message,
    required this.line,
    required this.resolver,
  });

  final Message message;
  final SystemLine line;
  final PreviewResolver resolver;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (line.icon) {
      'join' => (Icons.arrow_forward_rounded, Palette.green),
      'leave' => (Icons.arrow_back_rounded, Palette.red),
      'pin' => (Icons.push_pin_outlined, Palette.muted),
      'phone' => (Icons.call_rounded, Palette.green),
      'pencil' => (Icons.edit_outlined, Palette.muted),
      'boost' => (Icons.diamond_outlined, const Color(0xFFFF73FA)),
      'thread' => (Icons.chat_bubble_outline_rounded, Palette.muted),
      'poll' => (Icons.bar_chart_rounded, Palette.muted),
      _ => (Icons.mic_none_rounded, Palette.muted),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 2, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: Palette.muted,
                  fontSize: 16,
                  height: 1.375,
                ),
                children: [
                  for (final part in line.parts)
                    switch (part) {
                      DiscordUser user => TextSpan(
                        text: resolver.displayName(user),
                        style: TextStyle(
                          color: resolver.nameColor(user.id) ?? Palette.header,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Strong(:final text) => TextSpan(
                        text: text,
                        style: const TextStyle(
                          color: Palette.header,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      MessageLink(:final label) => TextSpan(
                        text: label,
                        style: const TextStyle(
                          color: Palette.header,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      ThreadLink(:final thread) => TextSpan(
                        text: thread.displayName,
                        style: const TextStyle(
                          color: Palette.header,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _ => TextSpan(text: '$part'),
                    },
                  TextSpan(
                    text: '  ${resolver.dates.short(message.timestamp)}',
                    style: const TextStyle(color: Palette.faint, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

(double, double) _fit(
  int? width,
  int? height,
  double maxWidth,
  double maxHeight,
) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return (maxWidth, maxHeight * 0.7);
  }
  final scale = min(1.0, min(maxWidth / width, maxHeight / height));
  return (width * scale, height * scale);
}

double _mediaHeight(Message message) {
  var height = 160.0 * message.stickers.where((s) => !s.isLottie).length;
  for (final a in message.attachments) {
    if (a.isImage) height += _fit(a.width, a.height, 400, 300).$2;
  }
  for (final e in mergeGalleryEmbeds(message.embeds)) {
    if (e.isPlainImage || e.isGifv) {
      final media = e.isGifv ? (e.thumbnail ?? e.video!) : e.thumbnail!;
      height += _fit(media.width, media.height, 400, 300).$2;
    }
  }
  visitComponents(message.components, (component) {
    if (component is GalleryComponent && component.items.length == 1) {
      final media = component.items.single;
      if (!media.isVideo) {
        height += _fit(media.width, media.height, 550, 350).$2;
      }
    }
  });
  return height;
}

String _resized(String url, double width, double height) {
  final separator = url.contains('?') ? '&' : '?';
  return '$url${separator}width=${width.round()}&height=${height.round()}';
}

class _AttachmentView extends StatelessWidget {
  const _AttachmentView(this.attachment);

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    if (a.isImage) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final (w, h) = _fit(
            a.width,
            a.height,
            min(400, constraints.maxWidth),
            300,
          );
          final image = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(
              image: AppScope.of(context)
                  .images(_resized(a.proxyUrl ?? a.url, w, h)),
              width: w,
              height: h,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(width: w, height: h, color: Palette.sidebar),
            ),
          );
          return a.isSpoiler ? _Spoiler(child: image) : image;
        },
      );
    }
    return _FileCard(
      name: a.isVoiceMessage ? 'Voice message' : a.displayName,
      detail: formatBytes(a.size),
      icon: a.isVideo
          ? Icons.movie_outlined
          : a.isAudio
          ? Icons.music_note_rounded
          : Icons.description_outlined,
      url: a.url,
    );
  }
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.child});

  final Widget child;

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (_open) return widget.child;
    return Clickable(
      onTap: () => setState(() => _open = true),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: widget.child,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'SPOILER',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.name,
    required this.detail,
    required this.icon,
    required this.url,
  });

  final String name;
  final String detail;
  final IconData icon;
  final String url;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 432),
    padding: const EdgeInsets.all(10),
    decoration: Styles.card,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 32, color: Palette.blurple),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Clickable(
                onTap: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  name,
                  style: const TextStyle(color: Palette.link, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(detail, style: Styles.tiny),
            ],
          ),
        ),
      ],
    ),
  );
}

String _mediaUrl(ComponentMedia media, double width, double height) =>
    media.proxyUrl == null
    ? media.url
    : _resized(media.proxyUrl!, width, height);

class _Components extends StatelessWidget {
  const _Components({
    required this.components,
    required this.resolver,
    this.gap = 8,
  });

  final List<Component> components;
  final PreviewResolver resolver;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (index, component) in components.indexed)
        Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : gap),
          child: _ComponentView(component: component, resolver: resolver),
        ),
    ],
  );
}

class _ComponentView extends StatelessWidget {
  const _ComponentView({required this.component, required this.resolver});

  final Component component;
  final PreviewResolver resolver;

  @override
  Widget build(BuildContext context) {
    final component = this.component;
    switch (component) {
      case TextComponent(:final content):
        return MarkdownText(content, resolver: resolver);
      case ContainerComponent(
        :final components,
        :final accentColor,
        :final spoiler,
      ):
        final card = Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 600),
          clipBehavior: Clip.antiAlias,
          decoration: Styles.card,
          child: Container(
            decoration: accentColor == null
                ? null
                : BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Color(0xFF000000 | accentColor),
                        width: 4,
                      ),
                    ),
                  ),
            padding: EdgeInsets.fromLTRB(
              accentColor == null ? 16 : 12,
              16,
              16,
              16,
            ),
            child: _Components(components: components, resolver: resolver),
          ),
        );
        return spoiler ? _Spoiler(child: card) : card;
      case SectionComponent(:final components, :final accessory):
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Components(
                components: components,
                resolver: resolver,
                gap: 4,
              ),
            ),
            if (accessory != null) ...[
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: _ComponentView(component: accessory, resolver: resolver),
              ),
            ],
          ],
        );
      case ThumbnailComponent(:final media):
        final image = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(
            image: AppScope.of(context).images(_mediaUrl(media, 170, 170)),
            width: 85,
            height: 85,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                Container(width: 85, height: 85, color: Palette.sidebar),
          ),
        );
        return media.spoiler ? _Spoiler(child: image) : image;
      case GalleryComponent(:final items):
        return _GalleryView(items);
      case FileComponent(:final media, :final name, :final size):
        return _FileCard(
          name: name,
          detail: formatBytes(size),
          icon: media.isAudio
              ? Icons.music_note_rounded
              : Icons.description_outlined,
          url: media.bestUrl,
        );
      case SeparatorComponent(:final divider, :final large):
        return Padding(
          padding: EdgeInsets.symmetric(vertical: large ? 8 : 0),
          child: divider
              ? const Divider(color: Palette.divider, height: 1)
              : const SizedBox(height: 1),
        );
      case RowComponent(:final components):
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final child in components)
              _ComponentView(component: child, resolver: resolver),
          ],
        );
      case ButtonComponent():
        return _ButtonView(component);
      case SelectComponent(:final text, :final disabled):
        return Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: Styles.inset,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: Styles.small,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Palette.muted,
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _GalleryView extends StatelessWidget {
  const _GalleryView(this.items);

  final List<ComponentMedia> items;

  Widget _tile(
    BuildContext context,
    ComponentMedia media,
    double w,
    double h, {
    double scale = 1,
  }) {
    if (media.isVideo) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Palette.sidebar,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.movie_outlined, color: Palette.muted),
      );
    }
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image(
        image: AppScope.of(context)
            .images(_mediaUrl(media, w * scale, h * scale)),
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Container(width: w, height: h, color: Palette.sidebar),
      ),
    );
    return media.spoiler ? _Spoiler(child: image) : image;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (items.length == 1) {
        final media = items.single;
        if (media.isVideo) {
          return _FileCard(
            name: media.fileName,
            detail: 'Video',
            icon: Icons.movie_outlined,
            url: media.bestUrl,
          );
        }
        final (w, h) = _fit(
          media.width,
          media.height,
          min(550, constraints.maxWidth),
          350,
        );
        return _tile(context, media, w, h);
      }
      final columns = items.length == 2 || items.length == 4 ? 2 : 3;
      final width = min(600.0, constraints.maxWidth);
      final side = ((width - 4 * (columns - 1)) / columns).floorToDouble();
      return SizedBox(
        width: width,
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final media in items)
              _tile(context, media, side, side, scale: 2),
          ],
        ),
      );
    },
  );
}

class _ButtonView extends StatelessWidget {
  const _ButtonView(this.button);

  final ButtonComponent button;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (button.kind) {
      ButtonKind.primary => (Palette.blurple, Colors.white),
      ButtonKind.success => (const Color(0xFF008545), Colors.white),
      ButtonKind.danger => (Palette.danger, Colors.white),
      _ => (Palette.hover, Palette.text),
    };
    final emoji = button.emoji;
    final url = button.url;
    final pill = Opacity(
      opacity: button.disabled ? 0.5 : 1,
      child: Container(
        constraints: const BoxConstraints(minWidth: 60, minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (emoji != null) ...[
              emoji.isCustom
                  ? Image(
                      image: AppScope.of(context).images(emoji.imageUrl!),
                      width: 18,
                      height: 18,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : _EmojiGlyph(emoji.name, size: 18),
              if (button.label != null) const SizedBox(width: 6),
            ],
            if (button.label != null)
              Flexible(
                child: Text(
                  button.label!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (url != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.open_in_new_rounded, size: 16, color: foreground),
            ],
          ],
        ),
      ),
    );
    if (url == null || !isSafeLink(url)) return pill;
    return Clickable(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: pill,
    );
  }
}

class _EmbedView extends StatelessWidget {
  const _EmbedView({required this.embed, required this.resolver});

  final Embed embed;
  final PreviewResolver resolver;

  @override
  Widget build(BuildContext context) {
    final e = embed;
    final images = AppScope.of(context).images;
    if (e.components.isNotEmpty) {
      return _Components(components: e.components, resolver: resolver);
    }
    if (e.isPlainImage || e.isGifv) {
      final media = e.isGifv ? (e.thumbnail ?? e.video!) : e.thumbnail!;
      final (w, h) = _fit(media.width, media.height, 400, 300);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          image: images(media.bestUrl),
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Container(width: w, height: h, color: Palette.sidebar),
        ),
      );
    }
    final color = e.color == null ? Palette.rail : Color(0xFF000000 | e.color!);
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      clipBehavior: Clip.antiAlias,
      decoration: Styles.card.copyWith(borderRadius: BorderRadius.circular(4)),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.providerName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(e.providerName!, style: Styles.tiny),
              ),
            if (e.author != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (e.author!.iconUrl != null) ...[
                      CircleImage(url: e.author!.iconUrl, size: 24),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        e.author!.name,
                        style: const TextStyle(
                          color: Palette.header,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (e.title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  e.title!,
                  style: TextStyle(
                    color: e.url == null ? Palette.header : Palette.link,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (e.description != null && e.description!.isNotEmpty)
              MarkdownText(
                e.description!,
                resolver: resolver,
                style: const TextStyle(
                  color: Palette.text,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            if (e.fields.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    for (final f in e.fields)
                      SizedBox(
                        width: f.inline ? 120 : 470,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.name,
                              style: const TextStyle(
                                color: Palette.header,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            MarkdownText(
                              f.value,
                              resolver: resolver,
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (e.images.isNotEmpty ||
                (e.type == 'video' && e.thumbnail != null))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image(
                    image: images(
                      (e.images.isNotEmpty ? e.images.first : e.thumbnail!)
                          .bestUrl,
                    ),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (e.footer != null || e.timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  [
                    if (e.footer != null) e.footer!.text,
                    if (e.timestamp != null) resolver.dates.short(e.timestamp!),
                  ].join(' \u{2022} '),
                  style: const TextStyle(
                    color: Palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Forward extends StatelessWidget {
  const _Forward({required this.forward, required this.resolver});

  final ForwardedMessage forward;
  final PreviewResolver resolver;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.only(left: 12),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: Palette.spine, width: 4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shortcut_rounded, size: 16, color: Palette.muted),
            SizedBox(width: 4),
            Text(
              'Forwarded',
              style: TextStyle(
                color: Palette.muted,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        if (forward.content.isNotEmpty)
          MarkdownText(forward.content, resolver: resolver),
        for (final a in forward.attachments)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _AttachmentView(a),
          ),
      ],
    ),
  );
}

class _StickerName extends StatelessWidget {
  const _StickerName(this.name);

  final String name;

  @override
  Widget build(BuildContext context) =>
      Text('Sticker: $name', style: Styles.small);
}

class _PollView extends StatelessWidget {
  const _PollView({required this.poll});

  final Poll poll;

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(16),
      decoration: Styles.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poll.question,
            style: const TextStyle(
              color: Palette.header,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final answer in poll.answers)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Palette.rail,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: total == 0 ? 0 : answer.votes / total,
                      child: Container(color: const Color(0x335865F2)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(answer.text, style: Styles.body)),
                        Text('${answer.votes}', style: Styles.small),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '$total vote${total == 1 ? '' : 's'}',
              style: Styles.small,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.thread});

  final Channel thread;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 4),
    constraints: const BoxConstraints(maxWidth: 480),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: Styles.card,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          thread.displayName,
          style: const TextStyle(
            color: Palette.header,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          thread.messageCount == null
              ? 'Thread'
              : '${thread.messageCount} messages',
          style: const TextStyle(
            color: Palette.link,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _Reactions extends StatelessWidget {
  const _Reactions(this.reactions);

  final List<Reaction> reactions;

  @override
  Widget build(BuildContext context) {
    final images = AppScope.of(context).images;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final r in reactions)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Palette.hover,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: r.burstCount > 0
                      ? const Color(0xFFFF73FA)
                      : Palette.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  r.emoji.isCustom
                      ? Image(
                          image: images(r.emoji.imageUrl!),
                          width: 16,
                          height: 16,
                          errorBuilder: (_, _, _) =>
                              Text(':${r.emoji.name}:', style: Styles.tiny),
                        )
                      : _EmojiGlyph(r.emoji.name, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${r.count}',
                    style: const TextStyle(
                      color: Palette.subtle,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmojiGlyph extends StatelessWidget {
  const _EmojiGlyph(this.emoji, {required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) => Image(
    image: AppScope.of(context).images(twemojiPngUrl(emoji)),
    width: size,
    height: size,
    errorBuilder: (_, _, _) =>
        Text(emoji, style: TextStyle(fontSize: size * 0.9)),
  );
}
