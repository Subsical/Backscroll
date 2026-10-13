import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'login/login_screen.dart';
import 'scope.dart';
import 'shell/desktop_shell.dart';
import 'shell/mobile_shell.dart';
import 'shell/sidebar.dart';
import 'theme.dart';
import 'widgets/logo.dart';
import 'widgets/scrollbars.dart';

class BackscrollApp extends StatefulWidget {
  const BackscrollApp({super.key, required this.services});

  final AppServices services;

  @override
  State<BackscrollApp> createState() => _BackscrollAppState();
}

class _BackscrollAppState extends State<BackscrollApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  Future<void> _back() async {
    final closed = await _navigator.currentState?.maybePop() ?? false;
    if (!closed) widget.services.library.back();
  }

  void _forward() {
    if (_navigator.currentState?.canPop() ?? true) return;
    widget.services.library.forward();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final alt = HardwareKeyboard.instance.isAltPressed;
    if (key == LogicalKeyboardKey.browserBack ||
        alt && key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_back());
      return true;
    }
    if (key == LogicalKeyboardKey.browserForward ||
        alt && key == LogicalKeyboardKey.arrowRight) {
      _forward();
      return true;
    }
    if (key == LogicalKeyboardKey.f5 ||
        HardwareKeyboard.instance.isControlPressed &&
            key == LogicalKeyboardKey.keyR) {
      final context = _navigator.currentContext;
      if (context == null || !widget.services.session.signedIn) return false;
      unawaited(refreshLibrary(context));
      return true;
    }
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons == kBackMouseButton) unawaited(_back());
    if (event.buttons == kForwardMouseButton) _forward();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.services,
    child: MaterialApp(
      navigatorKey: _navigator,
      title: 'Backscroll',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      scrollBehavior: const AppScrollBehavior(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Listener(onPointerDown: _onPointerDown, child: child),
      ),
      home: const RootGate(),
    ),
  );
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.session, services.library]),
      builder: (context, _) {
        final session = services.session;
        if (!session.restored) return const _Splash();
        if (!session.signedIn) return const LoginScreen();
        if (services.library.tokenRejected) {
          return LoginScreen(
            notice:
                'Discord no longer accepts the saved token for '
                '${session.account?.displayName}. Log in again to keep going.',
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 720
              ? const MobileShell()
              : const DesktopShell(),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Palette.chat,
    body: Center(child: BackscrollGlyph(size: 72)),
  );
}
