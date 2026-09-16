import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// A horizontal line of evenly spaced dashes — the ticket-stub Profile
/// screen's perforation cut and the dotted "leader" between a stat's label
/// and its value. One painter, two looks: a wider square-ended dash for the
/// perforation, a short round dash for a leader, picked by the caller
/// through [dashWidth] / [dashGap] / [strokeCap].
class DottedLine extends StatelessWidget {
  const DottedLine({
    super.key,
    this.color = AppColors.dash,
    this.strokeWidth = 1.0,
    this.dashWidth = 4,
    this.dashGap = 4,
    this.strokeCap = StrokeCap.butt,
  });

  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashGap;
  final StrokeCap strokeCap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: strokeWidth + 2,
      width: double.infinity,
      child: CustomPaint(
        painter: _DottedLinePainter(
          color: color,
          strokeWidth: strokeWidth,
          dashWidth: dashWidth,
          dashGap: dashGap,
          strokeCap: strokeCap,
        ),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  _DottedLinePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashGap,
    required this.strokeCap,
  });

  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashGap;
  final StrokeCap strokeCap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = strokeCap;
    final y = size.height / 2;
    final step = dashWidth + dashGap;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dashWidth).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += step;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        dashWidth != oldDelegate.dashWidth ||
        dashGap != oldDelegate.dashGap ||
        strokeCap != oldDelegate.strokeCap;
  }
}
