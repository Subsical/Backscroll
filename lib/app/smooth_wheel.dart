import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class _Glide {
  _Glide(this.event) : left = event.scrollDelta;

  PointerScrollEvent event;
  Offset left;
}

class WheelSmoother {
  WheelSmoother(this._dispatch);

  static const _settleSeconds = 0.06;

  final void Function(PointerEvent event) _dispatch;
  final _glides = <_Glide>[];
  late final _ticker = Ticker(_tick);
  Duration? _previous;

  bool get busy => _glides.isNotEmpty;

  bool take(PointerEvent event) {
    if (event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        event.scrollDelta == Offset.zero) {
      return false;
    }
    final last = _glides.lastOrNull;
    if (last != null &&
        last.event.position == event.position &&
        last.event.viewId == event.viewId) {
      last
        ..event = event
        ..left += event.scrollDelta;
    } else {
      _glides.add(_Glide(event));
    }
    if (!_ticker.isActive) {
      _previous = null;
      _ticker.start();
    }
    return true;
  }

  void _tick(Duration elapsed) {
    final previous = _previous;
    final seconds = previous == null
        ? 1 / 60
        : (elapsed - previous).inMicroseconds / 1e6;
    _previous = elapsed;
    final share = 1 - exp(-seconds / _settleSeconds);
    for (final glide in _glides.toList()) {
      var step = glide.left * share;
      if ((glide.left - step).distance < 0.5) step = glide.left;
      glide.left -= step;
      if (glide.left == Offset.zero) _glides.remove(glide);
      final event = glide.event;
      _dispatch(
        PointerScrollEvent(
          viewId: event.viewId,
          timeStamp: event.timeStamp,
          kind: event.kind,
          device: event.device,
          position: event.position,
          scrollDelta: step,
          embedderId: event.embedderId,
        ),
      );
    }
    if (_glides.isEmpty) _ticker.stop();
  }

  void dispose() => _ticker.dispose();
}

class AppBinding extends WidgetsFlutterBinding {
  static WidgetsBinding? _instance;

  static WidgetsBinding ensureInitialized() => _instance ??= AppBinding();

  late final _wheel = WheelSmoother(_pass);

  void _pass(PointerEvent event) {
    if (!locked) super.handlePointerEvent(event);
  }

  @override
  void handlePointerEvent(PointerEvent event) {
    if (!_wheel.take(event)) super.handlePointerEvent(event);
  }
}
