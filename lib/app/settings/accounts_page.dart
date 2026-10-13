import 'package:flutter/material.dart';

import '../../core/discord/api.dart';
import '../login/login_screen.dart';
import '../login/tos_note.dart';
import '../scope.dart';
import '../state/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  Future<void> _forget(BuildContext context, AccountInfo account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log out of ${account.displayName}?', style: Styles.title),
        content: const Text(
          'This removes the token from this device. It does not sign the '
          'account out anywhere else.',
          style: Styles.body,
        ),
        actions: [
          DiscordButton(
            label: 'Cancel',
            tone: ButtonTone.link,
            onPressed: () => Navigator.pop(context, false),
          ),
          DiscordButton(
            label: 'Log out',
            tone: ButtonTone.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await AppScope.of(context).session.forget(account);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final accounts = session.settings.accounts;
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            for (final account in accounts)
              _AccountCard(
                account: account,
                active: account.id == session.account?.id,
                onSwitch: () => session.switchTo(account),
                onForget: () => _forget(context, account),
              ),
            if (accounts.any((a) => a.kind == TokenKind.user)) ...[
              const SizedBox(height: 8),
              const TosNote(),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: DiscordButton(
                label: 'Add an account',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(adding: true),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'User tokens show your DMs and group DMs. Bot tokens show the servers '
              'the bot is in. Tokens are kept in this device\'s keychain and are only '
              'ever sent to discord.com.',
              style: Styles.small,
            ),
            if (!AppScope.of(context).secrets.available) ...[
              const SizedBox(height: 12),
              const Text(
                'No system keychain was found, so tokens are only kept until the app closes.',
                style: TextStyle(color: Palette.yellow, fontSize: 14),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.active,
    required this.onSwitch,
    required this.onForget,
  });

  final AccountInfo account;
  final bool active;
  final VoidCallback onSwitch;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(16),
    decoration: Styles.card,
    child: Row(
      children: [
        UserAvatar(user: account.user, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      account.displayName,
                      style: const TextStyle(
                        color: Palette.header,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Pill(
                    account.kind == TokenKind.bot ? 'BOT' : 'USER',
                    color: account.kind == TokenKind.bot
                        ? Palette.blurple
                        : const Color(0xFF4E5058),
                  ),
                ],
              ),
              Text(account.user.tag, style: Styles.small),
              if (active)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    'Active',
                    style: TextStyle(
                      color: Palette.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!active) ...[
          DiscordButton(
            label: 'Switch',
            tone: ButtonTone.secondary,
            dense: true,
            onPressed: onSwitch,
          ),
          const SizedBox(width: 8),
        ],
        DiscordButton(
          label: 'Log out',
          tone: ButtonTone.danger,
          dense: true,
          onPressed: onForget,
        ),
      ],
    ),
  );
}
