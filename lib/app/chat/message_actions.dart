import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/discord/models.dart';
import '../../core/discord/snowflake.dart';
import '../export/export_sheet.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum MessageAction {
  exportFrom('Export from here', Icons.vertical_align_bottom_rounded),
  exportUntil('Export up to here', Icons.vertical_align_top_rounded),
  copyText('Copy text', Icons.content_copy_rounded),
  copyLink('Copy message link', Icons.link_rounded),
  copyId('Copy message ID', Icons.pin_outlined);

  const MessageAction(this.label, this.icon);

  final String label;
  final IconData icon;

  bool get exports => this == exportFrom || this == exportUntil;

  Widget glyph({required double size, Color color = Palette.subtle}) =>
      this == copyId
      ? _IdBadge(size: size, color: color)
      : Icon(icon, size: size, color: color);
}

// Discord draws this one as a small plate with the letters cut out
class _IdBadge extends StatelessWidget {
  const _IdBadge({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Center(
      child: Container(
        width: size * 0.9,
        height: size * 0.7,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.15),
        ),
        child: Text(
          'ID',
          style: TextStyle(
            color: Palette.floating,
            fontSize: size * 0.5,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    ),
  );
}

class MessageActions {
  const MessageActions({required this.channel, this.guild});

  final Channel channel;
  final GuildState? guild;

  List<MessageAction> of(Message message) => [
    for (final action in MessageAction.values)
      if (action != MessageAction.copyText || message.content.isNotEmpty)
        action,
  ];

  String link(Message message) =>
      'https://discord.com/channels/'
      '${channel.isPrivate ? '@me' : channel.guildId}/${channel.id}/${message.id}';

  Future<void> run(
    BuildContext context,
    MessageAction action,
    Message message,
  ) async {
    // a millisecond of room keeps the message itself inside the range
    const edge = Duration(milliseconds: 1);
    final sent = snowflakeTime(message.id).toLocal();
    switch (action) {
      case MessageAction.exportFrom:
        await showExportSheet(
          context,
          channels: [channel],
          guild: guild,
          after: sent.subtract(edge),
        );
      case MessageAction.exportUntil:
        await showExportSheet(
          context,
          channels: [channel],
          guild: guild,
          before: sent.add(edge),
        );
      case MessageAction.copyText:
        await _copy(context, message.content);
      case MessageAction.copyLink:
        await _copy(context, link(message));
      case MessageAction.copyId:
        await _copy(context, message.id);
    }
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showToast(context, 'Copied');
  }
}

const _menuWidth = 224.0;

// Flutter opens a menu towards the half of the window with more room. Discord
// opens it to the right of the pointer and only turns it around when it would
// not fit, so the side is picked here.
Future<MessageAction?> showMessageMenu(
  BuildContext context, {
  required List<MessageAction> actions,
  required Offset at,
  bool rightAligned = false,
}) {
  final window = MediaQuery.sizeOf(context);
  final toTheLeft = rightAligned || at.dx + _menuWidth + 8 > window.width;
  return showMenu<MessageAction>(
    context: context,
    position: toTheLeft
        ? RelativeRect.fromLTRB(window.width, at.dy, window.width - at.dx, 0)
        : RelativeRect.fromLTRB(at.dx, at.dy, window.width, 0),
    constraints: const BoxConstraints.tightFor(width: _menuWidth),
    popUpAnimationStyle: AnimationStyle.noAnimation,
    menuPadding: const EdgeInsets.symmetric(vertical: 6),
    items: [
      for (final (index, action) in actions.indexed) ...[
        if (index > 0 && action.exports != actions[index - 1].exports)
          const _MenuGap(),
        _MenuRow(action),
      ],
    ],
  );
}

class _MenuRow extends PopupMenuEntry<MessageAction> {
  const _MenuRow(this.action);

  final MessageAction action;

  @override
  double get height => 36;

  @override
  bool represents(MessageAction? value) => value == action;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: InkWell(
      onTap: () => Navigator.pop(context, widget.action),
      borderRadius: BorderRadius.circular(4),
      hoverColor: Palette.hover,
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            widget.action.glyph(size: 20),
            const SizedBox(width: 8),
            Text(
              widget.action.label,
              style: const TextStyle(
                color: Palette.text,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MenuGap extends PopupMenuEntry<Never> {
  const _MenuGap();

  @override
  double get height => 17;

  @override
  bool represents(void value) => false;

  @override
  State<_MenuGap> createState() => _MenuGapState();
}

class _MenuGapState extends State<_MenuGap> {
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Divider(height: 1, color: Palette.divider),
  );
}

Future<MessageAction?> showMessageSheet(
  BuildContext context, {
  required List<MessageAction> actions,
}) => showModalBottomSheet<MessageAction>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetGroup([
            for (final action in actions)
              if (action.exports) action,
          ]),
          const SizedBox(height: 12),
          _SheetGroup([
            for (final action in actions)
              if (!action.exports) action,
          ]),
        ],
      ),
    ),
  ),
);

class _SheetGroup extends StatelessWidget {
  const _SheetGroup(this.actions);

  final List<MessageAction> actions;

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.hover,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (index, action) in actions.indexed) ...[
          if (index > 0)
            const Divider(height: 1, indent: 56, color: Palette.divider),
          InkWell(
            onTap: () => Navigator.of(context).pop(action),
            highlightColor: Palette.hover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  action.glyph(size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      action.label,
                      style: const TextStyle(
                        color: Palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
