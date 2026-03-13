import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'dart:math' as math;
import 'dart:ui' as ui;

class ProfessionalClockPainter extends CustomPainter {
  final DateTime time;

  ProfessionalClockPainter(this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2.2;

    final paint = Paint()..strokeCap = StrokeCap.round;

    // Background circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Outer border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF263238)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    // Minute & Hour markings
    for (var i = 0; i < 60; i++) {
      double angle = i * 6 * math.pi / 180;

      if (i % 5 == 0) {
        // Hour line
        canvas.drawLine(
          _pos(center, angle, radius),
          _pos(center, angle, radius - 14),
          paint
            ..strokeWidth = 3
            ..color = const Color(0xFF263238),
        );

        // Hour numbers
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${i == 0 ? 12 : i ~/ 5}',
            style: const TextStyle(
              color: Color(0xFF263238),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();

        Offset textPos = _pos(center, angle, radius - 32);

        textPainter.paint(
          canvas,
          Offset(
            textPos.dx - textPainter.width / 2,
            textPos.dy - textPainter.height / 2,
          ),
        );
      } else {
        // Minute line
        canvas.drawLine(
          _pos(center, angle, radius),
          _pos(center, angle, radius - 6),
          paint
            ..strokeWidth = 1.5
            ..color = Colors.black12,
        );
      }
    }

    // Clock Hands
    double h = (time.hour % 12 + time.minute / 60) * 30 * math.pi / 180;
    double m = (time.minute + time.second / 60) * 6 * math.pi / 180;
    double s = (time.second + time.millisecond / 1000) * 6 * math.pi / 180;

    // Hour hand
    canvas.drawLine(
      center,
      _pos(center, h, radius * 0.5),
      paint
        ..strokeWidth = 7
        ..color = const Color(0xFF263238),
    );

    // Minute hand
    canvas.drawLine(
      center,
      _pos(center, m, radius * 0.75),
      paint
        ..strokeWidth = 4
        ..color = const Color(0xFF455A64),
    );

    // Second hand
    canvas.drawLine(
      center,
      _pos(center, s, radius * 0.85),
      paint
        ..strokeWidth = 2
        ..color = Colors.redAccent,
    );

    // Center circle
    canvas.drawCircle(center, 6, Paint()..color = const Color(0xFF263238));

    // ---------------------------
    // DAY TEXT (MON)
    // ---------------------------
    final dayText = DateFormat('EEE').format(time).toUpperCase();

    final dayPainter = TextPainter(
      text: TextSpan(
        text: dayText,
        style: const TextStyle(
          color: Color(0xFF455A64),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    dayPainter.paint(
      canvas,
      Offset(center.dx - dayPainter.width / 2, center.dy + 18),
    );

    // ---------------------------
    // DATE TEXT (21 FEB 2026)
    // ---------------------------
    final dateText = DateFormat('dd MMM yyyy').format(time).toUpperCase();

    final datePainter = TextPainter(
      text: TextSpan(
        text: dateText,
        style: const TextStyle(
          color: Color(0xFF263238),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    datePainter.paint(
      canvas,
      Offset(center.dx - datePainter.width / 2, center.dy + 36),
    );
  }

  Offset _pos(Offset center, double angle, double len) {
    return Offset(
      center.dx + len * math.sin(angle),
      center.dy - len * math.cos(angle),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
