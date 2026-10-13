import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

class BackscrollGlyph extends StatelessWidget {
  const BackscrollGlyph({
    super.key,
    this.size = 28,
    this.color = Colors.white,
    this.accent = Palette.blurple,
  });

  final double size;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _GlyphPainter(color, accent),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.color, this.accent);

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // same coordinates as assets/icon/icon.svg
    final scale = size.width / 660;
    canvas
      ..save()
      ..scale(scale)
      ..translate(-182, -200);
    final bubble = Path()
      ..moveTo(300, 262)
      ..lineTo(724, 262)
      ..arcToPoint(const Offset(834, 372), radius: const Radius.circular(110))
      ..lineTo(834, 608)
      ..arcToPoint(const Offset(724, 718), radius: const Radius.circular(110))
      ..lineTo(446, 718)
      ..lineTo(310, 822)
      ..cubicTo(296, 833, 276, 823, 276, 805)
      ..lineTo(276, 718)
      ..arcToPoint(const Offset(190, 611), radius: const Radius.circular(110))
      ..lineTo(190, 372)
      ..arcToPoint(const Offset(300, 262), radius: const Radius.circular(110))
      ..close();
    canvas.drawPath(bubble, Paint()..color = color);

    const center = Offset(512, 486);
    const r = 118.0;
    const start = 212 * pi / 180;
    const end = 150 * pi / 180;
    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 52
      ..strokeCap = StrokeCap.round;
    final from = center + Offset(cos(start), sin(start)) * r;
    canvas.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..arcToPoint(
          center + Offset(cos(end), sin(end)) * r,
          radius: const Radius.circular(r),
          largeArc: true,
        ),
      stroke,
    );
    final direction = Offset(sin(start), -cos(start));
    final normal = Offset(cos(start), sin(start));
    final tip = from + direction * 62;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo((from + normal * 62).dx, (from + normal * 62).dy)
        ..lineTo((from - normal * 62).dx, (from - normal * 62).dy)
        ..close(),
      Paint()
        ..color = accent
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 14
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(512, 420)
        ..lineTo(512, 490)
        ..lineTo(556, 524),
      stroke..strokeWidth = 46,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.color != color || old.accent != accent;
}
