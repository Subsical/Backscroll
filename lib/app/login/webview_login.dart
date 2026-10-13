import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../services/paths.dart';
import '../theme.dart';
import 'token_reader.dart';

class WebviewUnavailable implements Exception {
  WebviewUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<String?> loginWithWebview(BuildContext context, AppPaths paths) async {
  if (Platform.isAndroid) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const MobileLoginPage(),
      ),
    );
  }
  return _desktopLogin(paths);
}

Future<String?> _desktopLogin(AppPaths paths) async {
  if (!await WebviewWindow.isWebviewAvailable()) {
    throw WebviewUnavailable(
      'The Microsoft Edge WebView2 runtime is missing. Install it or paste a token instead.',
    );
  }
  final webview = await WebviewWindow.create(
    configuration: CreateConfiguration(
      title: 'Log in to Discord',
      windowWidth: 1000,
      windowHeight: 760,
      userDataFolderWindows: paths.webviewData,
    ),
  );
  final result = Completer<String?>();
  var checking = false;
  final poll = Timer.periodic(const Duration(seconds: 1), (_) async {
    if (checking || result.isCompleted) return;
    checking = true;
    try {
      final token = parseTokenResult(
        await webview.evaluateJavaScript(tokenScript),
      );
      if (token != null && !result.isCompleted) result.complete(token);
    } on Exception {
      // page not loaded yet, the next tick retries
    } finally {
      checking = false;
    }
  });
  unawaited(
    webview.onClose.then((_) {
      if (!result.isCompleted) result.complete(null);
    }),
  );
  webview.launch(discordLoginUrl);
  final token = await result.future;
  poll.cancel();
  if (token != null) webview.close();
  // Wiping the session leaves the token valid. Only Discord's logout call
  // would revoke it, and that is never made.
  await WebviewWindow.clearAll(userDataFolderWindows: paths.webviewData);
  return token;
}

class MobileLoginPage extends StatefulWidget {
  const MobileLoginPage({super.key});

  @override
  State<MobileLoginPage> createState() => _MobileLoginPageState();
}

class _MobileLoginPageState extends State<MobileLoginPage> {
  late final WebViewController _controller;
  Timer? _poll;
  bool _loading = true;
  bool _checking = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Palette.chat)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Discord tries to hand the login off to its app through custom
          // schemes; keeping those out keeps the login on the web page.
          onNavigationRequest: (request) =>
              allowedInLoginView(Uri.tryParse(request.url))
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(discordLoginUrl));
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  Future<void> _check() async {
    if (_checking || _done) return;
    _checking = true;
    try {
      final token = parseTokenResult(
        await _controller.runJavaScriptReturningResult(tokenScript),
      );
      if (token != null && mounted && !_done) {
        _done = true;
        Navigator.of(context).pop(token);
      }
    } on Exception {
      // not ready yet
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_wipe());
    super.dispose();
  }

  Future<void> _wipe() async {
    await WebViewCookieManager().clearCookies();
    await _controller.clearLocalStorage();
    await _controller.clearCache();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.chat,
    appBar: AppBar(
      backgroundColor: Palette.sidebar,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Cancel',
      ),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Log in to Discord',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              Icon(Icons.lock_rounded, size: 12, color: Palette.green),
              SizedBox(width: 4),
              Text(
                'discord.com',
                style: TextStyle(fontSize: 12, color: Palette.muted),
              ),
            ],
          ),
        ],
      ),
      bottom: _loading
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
    ),
    body: _webView(),
  );

  // The default texture mode drops focus when the keyboard changes height,
  // which closes it as soon as its language picker opens. Hybrid composition
  // embeds the real WebView, so typing works the way it does in a browser.
  Widget _webView() {
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: platform,
          displayWithHybridComposition: true,
        ),
      );
    }
    return WebViewWidget(controller: _controller);
  }
}
