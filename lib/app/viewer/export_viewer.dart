import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme.dart';

class ExportViewer extends StatefulWidget {
  const ExportViewer({super.key, required this.path, required this.title});

  final String path;
  final String title;

  @override
  State<ExportViewer> createState() => _ExportViewerState();
}

class _ExportViewerState extends State<ExportViewer> {
  late final _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Palette.chat)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null || uri.scheme == 'file') {
            return NavigationDecision.navigate;
          }
          launchUrl(uri, mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
      ),
    )
    ..loadFile(widget.path);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.chat,
    appBar: AppBar(
      backgroundColor: Palette.chat,
      surfaceTintColor: Colors.transparent,
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    body: WebViewWidget(controller: _controller),
  );
}
