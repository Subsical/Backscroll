import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/discord/api.dart';
import '../../core/discord/models.dart';
import '../../core/export/dates.dart';
import '../scope.dart';
import '../state/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/row_extents.dart';
import 'message_list.dart';

class MessageSearchPage extends StatelessWidget {
  const MessageSearchPage({super.key, required this.channel, this.guild});

  final Channel channel;
  final GuildState? guild;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.sidebar,
    body: SafeArea(
      child: MessageSearch(
        channel: channel,
        guild: guild,
        onOpen: (message) => Navigator.of(context).pop(message),
        onClose: () => Navigator.of(context).pop(),
      ),
    ),
  );
}

class MessageSearch extends StatefulWidget {
  const MessageSearch({
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
  State<MessageSearch> createState() => _MessageSearchState();
}

class _MessageSearchState extends State<MessageSearch> {
  static const _maxIndexWaits = 10;

  final _query = TextEditingController();
  final _results = <Message>[];
  final _extents = RowExtents();
  late final _resolver = PreviewResolver(
    dates: DateFormatter(locale: AppScope.of(context).locale),
    guild: widget.guild,
  );
  String _searched = '';
  int _total = 0;
  bool _loading = false;
  bool _exhausted = false;
  bool _indexing = false;
  String? _error;
  int _generation = 0;
  int _indexWaits = 0;
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    _retry?.cancel();
    _generation++;
    setState(() {
      _searched = query;
      _results.clear();
      _total = 0;
      _exhausted = false;
      _indexing = false;
      _error = null;
      _indexWaits = 0;
    });
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    final generation = _generation;
    final services = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await services.library.search(
        widget.channel,
        _searched,
        offset: _results.length,
      );
      if (!mounted || generation != _generation) return;
      final wait = results.retryAfter;
      if (wait != null) {
        if (++_indexWaits > _maxIndexWaits) {
          setState(() {
            _loading = false;
            _indexing = false;
            _error =
                'Discord hasn\'t finished indexing this conversation. '
                'Try again in a few minutes.';
          });
          return;
        }
        setState(() => _indexing = true);
        _retry = Timer(wait, () {
          if (mounted && generation == _generation) unawaited(_fetch());
        });
        return;
      }
      setState(() {
        _loading = false;
        _indexing = false;
        _resolver.learn(results.messages);
        _results.addAll(results.messages);
        _total = results.total;
        _exhausted =
            results.messages.isEmpty || _results.length >= results.total;
      });
    } on DiscordException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _indexing = false;
        _error = services.session.isBot && e is ForbiddenException
            ? '${e.message}. Bots can only search message text with the '
                  'Message Content intent turned on.'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final channel = widget.channel;
    return Column(
      children: [
        Container(
          height: compact ? 56 : 48,
          padding: EdgeInsets.only(left: compact ? 4 : 12, right: 4),
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
              Expanded(
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: channel.isPrivate
                        ? 'Search ${channel.displayName}'
                        : 'Search #${channel.displayName}',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    suffixIcon: IconButton(
                      onPressed: _submit,
                      tooltip: 'Search',
                      icon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Palette.muted,
                      ),
                    ),
                  ),
                ),
              ),
              if (!compact && widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: 'Close search',
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
    if (_searched.isEmpty) {
      return const PanelHint(
        icon: Icons.manage_search_rounded,
        text: 'Find messages by the words in them, then tap one to jump to it.',
      );
    }
    if (_results.isEmpty) {
      if (_error != null) {
        return PanelHint(
          icon: Icons.error_outline_rounded,
          text: _error!,
          action: 'Try again',
          onAction: _submit,
        );
      }
      if (_indexing) {
        return const PanelHint(
          icon: Icons.hourglass_top_rounded,
          text:
              'Discord is still indexing this conversation for search. '
              'Trying again in a moment.',
          busy: true,
        );
      }
      if (_loading) return const Center(child: CircularProgressIndicator());
      return const PanelHint(
        icon: Icons.search_off_rounded,
        text: 'No messages match that.',
      );
    }
    final count = NumberFormat.decimalPattern(AppScope.of(context).locale)
        .format(_total);
    return ListView.custom(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
      childrenDelegate: MeasuredRows(
        extents: _extents,
        idOf: (index) => index == 0
            ? 'count'
            : index > _results.length
            ? 'footer'
            : _results[index - 1].id,
        childCount: _results.length + 2,
        builder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                '$count result${_total == 1 ? '' : 's'}',
                style: Styles.sectionLabel,
              ),
            );
          }
          if (index == _results.length + 1) return _footer();
          final message = _results[index - 1];
          return MessageCard(
            message: message,
            resolver: _resolver,
            onTap: () => widget.onOpen(message),
          );
        },
      ),
    );
  }

  Widget _footer() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.red),
            ),
            const SizedBox(height: 8),
            DiscordButton(
              label: 'Try again',
              tone: ButtonTone.secondary,
              onPressed: () => unawaited(_fetch()),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_exhausted) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Center(
        child: DiscordButton(
          label: 'More results',
          tone: ButtonTone.secondary,
          onPressed: () => unawaited(_fetch()),
        ),
      ),
    );
  }
}
