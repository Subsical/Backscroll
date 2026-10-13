import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/export/dates.dart';
import '../chat/markdown_text.dart';
import '../chat/message_list.dart';
import '../theme.dart';

enum AppDocument {
  privacy('Privacy policy', 'PRIVACY.md'),
  license('License', 'LICENSE');

  const AppDocument(this.title, this.asset);

  final String title;
  final String asset;

  Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => DocumentPage(document: this)));
}

class DocumentPage extends StatefulWidget {
  const DocumentPage({super.key, required this.document});

  final AppDocument document;

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  late final _text = rootBundle.loadString(widget.document.asset);
  final _resolver = PreviewResolver(dates: DateFormatter());

  Widget _body(String text) {
    if (widget.document.asset.endsWith('.md')) {
      return MarkdownText(
        text.replaceFirst(RegExp(r'^# .*\n+'), ''),
        resolver: _resolver,
      );
    }
    final paragraphs = text.trim().split(RegExp(r'\n\s*\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              p.replaceAll(RegExp(r'\s*\n\s*'), ' '),
              style: Styles.body,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.chat,
    appBar: AppBar(
      backgroundColor: Palette.chat,
      surfaceTintColor: Colors.transparent,
      title: Text(
        widget.document.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    body: FutureBuilder<String>(
      future: _text,
      builder: (context, snapshot) {
        final text = snapshot.data;
        if (text == null) return const SizedBox.shrink();
        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _body(text),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
