import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/discord/api.dart';
import '../../core/discord/models.dart';
import '../../core/export/dates.dart';
import '../scope.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/row_extents.dart';
import 'message_list.dart';

class PinnedMessagesPage extends StatelessWidget {
  const PinnedMessagesPage({super.key, required this.channel, this.guild});

  final Channel channel;
  final GuildState? guild;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.sidebar,
    body: SafeArea(
      child: PinnedMessages(
        channel: channel,
        guild: guild,
        onOpen: (message) => Navigator.of(context).pop(message),
        onClose: () => Navigator.of(context).pop(),
      ),
    ),
  );
}

class PinnedMessages extends StatefulWidget {
  const PinnedMessages({
    super.key,
    required this.channel,
    required this.onOpen,
    this.guild,
    this.onClose,
  });

  final Channel channel;
  final GuildState? guild;
  final ValueChanged<Message> onOpen;
  final VoidCallback? onClose;

  @override
  State<PinnedMessages> createState() => _PinnedMessagesState();
}

class _PinnedMessagesState extends State<PinnedMessages> {
  final _extents = RowExtents();
  late final _resolver = PreviewResolver(
    dates: DateFormatter(locale: AppScope.of(context).locale),
    guild: widget.guild,
  );
  List<Message>? _pins;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final pins = await AppScope.of(context).library.fetchPins(widget.channel);
      if (!mounted) return;
      setState(() {
        _resolver.learn(pins);
        _pins = pins;
      });
    } on DiscordException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is ForbiddenException
            ? 'You can\'t read this channel.'
            : e.message,
      );
    }
  }

  void _retry() {
    setState(() => _error = null);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return Column(
      children: [
        Container(
          height: compact ? 56 : 48,
          padding: EdgeInsets.only(left: compact ? 4 : 16, right: 4),
          decoration: const BoxDecoration(border: Styles.underline),
          child: Row(
            children: [
              if (compact && widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: 'Back',
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Palette.text,
                  ),
                ),
              const Expanded(
                child: Text(
                  'Pinned messages',
                  style: TextStyle(
                    color: Palette.header,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!compact && widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: 'Close pinned messages',
                  icon: const Icon(Icons.close_rounded, color: Palette.muted),
                ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_error != null) {
      return PanelHint(
        icon: Icons.error_outline_rounded,
        text: _error!,
        action: 'Try again',
        onAction: _retry,
      );
    }
    final pins = _pins;
    if (pins == null) return const Center(child: CircularProgressIndicator());
    if (pins.isEmpty) {
      return const PanelHint(
        icon: Icons.push_pin_outlined,
        text: 'Nothing is pinned here.',
      );
    }
    return ListView.custom(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
      childrenDelegate: MeasuredRows(
        extents: _extents,
        idOf: (index) => pins[index].id,
        childCount: pins.length,
        builder: (context, index) => MessageCard(
          message: pins[index],
          resolver: _resolver,
          onTap: () => widget.onOpen(pins[index]),
        ),
      ),
    );
  }
}
