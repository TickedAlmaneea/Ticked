import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// A pulsing placeholder block — the ticket-stub Profile screen's loading
/// state calls for "shimmer the stub card's text lines and stat values,
/// keep the card frame and perforation drawn," so only the words and
/// numbers placeholder here, never the card shape around them.
class ShimmerBar extends StatefulWidget {
  const ShimmerBar({super.key, required this.width, required this.height, this.radius = 4});

  final double width;
  final double height;
  final double radius;

  @override
  State<ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<ShimmerBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(opacity: 0.35 + _controller.value * 0.35, child: child),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: AppColors.skeleton, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}
