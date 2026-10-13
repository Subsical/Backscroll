import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/discord/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/document_page.dart';
import '../widgets/logo.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 32),
    children: [
      Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Palette.blurple,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: const BackscrollGlyph(size: 40),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Backscroll',
                style: TextStyle(
                  color: Palette.header,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text('Version $appVersion', style: Styles.small),
            ],
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        'Backscroll exports Discord chats to HTML, JSON, plain text and CSV, '
        'on desktop and on your phone.',
        style: Styles.body,
      ),
      const SizedBox(height: 16),
      const Text(
        'How exporting works, from paging through messages to the HTML layout, '
        'follows DiscordChatExporter by Oleksii Holub (MIT). The code here is '
        'written from scratch.',
        style: Styles.small,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DiscordButton(
            label: 'DiscordChatExporter',
            tone: ButtonTone.secondary,
            icon: Icons.open_in_new_rounded,
            onPressed: () => launchUrl(
              Uri.parse('https://github.com/Tyrrrz/DiscordChatExporter'),
            ),
          ),
          DiscordButton(
            label: 'Open source licenses',
            tone: ButtonTone.secondary,
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Backscroll',
              applicationVersion: appVersion,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const SectionLabel('Legal'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final document in AppDocument.values)
            DiscordButton(
              label: document.title,
              tone: ButtonTone.secondary,
              onPressed: () => document.open(context),
            ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Backscroll is released under the MIT License and isn\'t affiliated with Discord.',
        style: Styles.small,
      ),
      const SizedBox(height: 24),
      const Text(
        'Interface font: Figtree by Erik Kennedy, under the SIL Open Font License. '
        'Emoji in exports are Twemoji images (CC-BY 4.0).',
        style: Styles.tiny,
      ),
    ],
  );
}
