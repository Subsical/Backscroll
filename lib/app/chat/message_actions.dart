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

Future<MessageAction?> showMessageMenu(
  BuildContext context, {
  required List<MessageAction> actions,
  required RelativeRect position,
}) => showMenu<MessageAction>(
  context: context,
  position: position,
  popUpAnimationStyle: AnimationStyle.noAnimation,
  items: [
    for (final action in actions)
      PopupMenuItem(
        value: action,
        height: 36,
        child: Row(
          children: [
            Expanded(child: Text(action.label)),
            const SizedBox(width: 24),
            Icon(action.icon, size: 18, color: Palette.subtle),
          ],
        ),
      ),
  ],
);

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
                  Icon(action.icon, size: 24, color: Palette.subtle),
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
