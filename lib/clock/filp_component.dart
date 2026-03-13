import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:math' as math;

// --- FLIP COMPONENT ---
class MedicalFlipCard extends StatelessWidget {
  final bool isFlipped;
  final Widget front;
  final Widget back;

  const MedicalFlipCard({
    super.key,
    required this.isFlipped,
    required this.front,
    required this.back,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      tween: Tween<double>(begin: 0, end: isFlipped ? 180 : 0),
      builder: (context, double value, child) {
        bool showFront = value < 90;
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(value * math.pi / 180),
          alignment: Alignment.center,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.13),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.8),
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: showFront
                ? front
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: back,
                  ),
          ),
        );
      },
    );
  }
}
