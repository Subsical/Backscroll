import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';

const _userSteps = [
  'Open discord.com in a browser on a computer and log in.',
  'Open the developer tools with Ctrl+Shift+I, or Cmd+Option+I on a Mac.',
  'Go to the Network tab and reload the page.',
  'Type api into the filter box, click any request to discord.com/api and copy the value of its Authorization header.',
  'When you are done, close the tab instead of logging out. Logging out resets the token.',
];

const _botSteps = [
  'Open the Discord Developer Portal and pick your application.',
  'Under Bot, press Reset Token and copy the new token.',
  'On the same page, turn on Message Content Intent, otherwise message text comes back empty.',
  'Invite the bot to your server with View Channels and Read Message History.',
];

Future<void> showTokenHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) =>
      const FractionallySizedBox(heightFactor: 0.8, child: _TokenHelp()),
);

class _TokenHelp extends StatelessWidget {
  const _TokenHelp();

  Widget _steps(List<String> steps) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    children: [
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Palette.blurple,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(steps[i], style: Styles.body)),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Getting a token', style: Styles.title),
        ),
        const TabBar(
          indicatorColor: Palette.blurple,
          labelColor: Palette.header,
          unselectedLabelColor: Palette.muted,
          dividerColor: Palette.divider,
          tabs: [
            Tab(text: 'User token'),
            Tab(text: 'Bot token'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [_steps(_userSteps), _steps(_botSteps)]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              isCompact(context)
                  ? 'On a phone, the Log in with Discord button is much easier.'
                  : 'Your token is like a password. Backscroll only ever sends it to discord.com.',
              style: Styles.small,
            ),
          ),
        ),
      ],
    ),
  );
}
