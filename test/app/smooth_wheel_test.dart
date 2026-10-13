import 'package:backscroll/app/smooth_wheel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScrollController list;
  late WheelSmoother wheel;

  Future<Offset> pumpList(WidgetTester tester) async {
    list = ScrollController();
    addTearDown(list.dispose);
    wheel = WheelSmoother(tester.binding.handlePointerEvent);
    addTearDown(wheel.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.builder(
          controller: list,
          itemExtent: 50,
          itemBuilder: (context, index) => Text('$index'),
        ),
      ),
    );
    return tester.getCenter(find.byType(ListView));
  }

  Future<List<double>> glide(WidgetTester tester) async {
    final seen = <double>[];
    for (var frame = 0; frame < 120 && wheel.busy; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(list.offset);
    }
    expect(wheel.busy, isFalse);
    return seen;
  }

  testWidgets('a wheel notch is spread over many frames', (tester) async {
    final at = await pumpList(tester);
    final taken = wheel.take(
      PointerScrollEvent(position: at, scrollDelta: const Offset(0, 100)),
    );
    expect(taken, isTrue);
    expect(list.offset, 0);
    final seen = await glide(tester);
    expect(seen.length, greaterThan(8));
    expect(seen.first, inExclusiveRange(0, 40));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    expect(seen[seen.length ~/ 2], lessThan(100));
    expect(seen.last, closeTo(100, 0.001));
  });

  testWidgets('notches add up and turn around', (tester) async {
    final at = await pumpList(tester);
    PointerScrollEvent notch(double dy) =>
        PointerScrollEvent(position: at, scrollDelta: Offset(0, dy));
    wheel
      ..take(notch(100))
      ..take(notch(100));
    await tester.pump(const Duration(milliseconds: 16));
    wheel.take(notch(100));
    expect((await glide(tester)).last, closeTo(300, 0.001));

    wheel.take(notch(100));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final turning = list.offset;
    expect(turning, inExclusiveRange(300, 400));
    wheel.take(notch(-200));
    final back = await glide(tester);
    expect(back.last, closeTo(200, 0.001));
    expect(back.first, lessThan(turning));
  });

  testWidgets('only mouse wheels are smoothed', (tester) async {
    final at = await pumpList(tester);
    expect(
      wheel.take(
        PointerScrollEvent(
          kind: PointerDeviceKind.trackpad,
          position: at,
          scrollDelta: const Offset(0, 40),
        ),
      ),
      isFalse,
    );
    expect(wheel.take(PointerHoverEvent(position: at)), isFalse);
    expect(wheel.busy, isFalse);
  });
}
