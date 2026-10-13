import 'package:flutter/material.dart';

import '../../core/discord/api.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/document_page.dart';
import '../widgets/logo.dart';
import 'token_help.dart';
import 'tos_note.dart';
import 'webview_login.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.adding = false, this.notice});

  final bool adding;
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _token = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _opening = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _useToken(String raw) async {
    if (raw.trim().isEmpty) {
      setState(() => _error = 'Paste a token first.');
      return;
    }
    final services = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await services.session.signIn(raw);
      if (!mounted) return;
      if (account.kind == TokenKind.user) await _confirmTerms();
      if (mounted && widget.adding) Navigator.of(context).pop();
    } on InvalidTokenException {
      setState(
        () => _error = 'Discord did not accept that token. Check that you copied all of it.',
      );
    } on DiscordException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmTerms() async {
    final settings = AppScope.of(context).settings;
    if (settings.notices.contains('tos')) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('One thing first', style: Styles.title),
        content: const TosNote(),
        actions: [
          DiscordButton(
            label: 'I understand',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    settings.notices.add('tos');
    await settings.save();
  }

  Future<void> _webLogin() async {
    final services = AppScope.of(context);
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final token = await loginWithWebview(context, services.paths);
      if (token != null && mounted) await _useToken(token);
    } on WebviewUnavailable catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'The login window could not be opened here. Paste a token instead.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final services = AppScope.of(context);
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Palette.blurple,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: const BackscrollGlyph(size: 40),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.adding ? 'Add an account' : 'Welcome to Backscroll',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Palette.header,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (widget.notice == null)
          const Text(
            'Export your Discord chats to HTML, JSON, plain text or CSV.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted, fontSize: 16),
          )
        else
          Text(
            widget.notice!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.yellow),
          ),
        const SizedBox(height: 24),
        if (services.webviewLogin) ...[
          const SectionLabel('Your DMs'),
          DiscordButton(
            label: 'Log in with Discord',
            icon: Icons.login_rounded,
            expand: true,
            busy: _opening,
            onPressed: _busy ? null : _webLogin,
          ),
          const SizedBox(height: 8),
          const Text(
            'Opens discord.com so you can log in as usual, with 2FA or a QR code. '
            'The window closes by itself once you are in.',
            style: Styles.small,
          ),
          const SizedBox(height: 12),
          const TosNote(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(child: Divider(color: Palette.divider)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR', style: Styles.sectionLabel),
                ),
                Expanded(child: Divider(color: Palette.divider)),
              ],
            ),
          ),
        ],
        const SectionLabel('Paste a token'),
        TextField(
          controller: _token,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: _useToken,
          decoration: InputDecoration(
            hintText: 'User or bot token',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Palette.muted,
              ),
              tooltip: _obscure ? 'Show' : 'Hide',
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (_error == null)
          const Text(
            'A user token shows your DMs and group DMs. A bot token shows the servers the bot is in.',
            style: Styles.tiny,
          )
        else
          Text(
            _error!,
            style: const TextStyle(color: Palette.red, fontSize: 12),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: () => showTokenHelp(context),
              child: const Text(
                'How do I get a token?',
                style: TextStyle(color: Palette.link),
              ),
            ),
            const Spacer(),
            DiscordButton(
              label: 'Continue',
              busy: _busy,
              onPressed: () => _useToken(_token.text),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => AppDocument.privacy.open(context),
            child: Text(
              AppDocument.privacy.title,
              style: const TextStyle(color: Palette.muted, fontSize: 13),
            ),
          ),
        ),
      ],
    );

    final scroll = SingleChildScrollView(
      padding: compact
          ? const EdgeInsets.all(20)
          : const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: compact
            ? form
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: Palette.chat,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 30,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 28,
                  ),
                  child: form,
                ),
              ),
      ),
    );

    // an app bar's height would make the card scroll on wide windows
    return Scaffold(
      backgroundColor: compact ? Palette.chat : null,
      appBar: widget.adding && compact
          ? AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
            )
          : null,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: compact
            ? null
            : const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4752C4), Color(0xFF2B2D6E), Palette.rail],
                ),
              ),
        alignment: Alignment.center,
        child: SafeArea(
          child: Stack(
            children: [
              Center(child: scroll),
              if (widget.adding && !compact)
                const Positioned(top: 4, left: 4, child: BackButton()),
            ],
          ),
        ),
      ),
    );
  }
}
