import 'package:flutter/material.dart';

class CropOverlayPainter extends CustomPainter {
  CropOverlayPainter({required this.widthFactor, required this.heightFactor});
  
  final double widthFactor;
  final double heightFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final rectW = size.width * widthFactor;
    final rectH = size.height * heightFactor;
    final left = (size.width - rectW) / 2;
    final top = (size.height - rectH) / 2;

    final hole = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, rectW, rectH),
      const Radius.circular(12),
    );

    canvas.saveLayer(Offset.zero & size, Paint());

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withOpacity(0.55),
    );

    canvas.drawRRect(hole, Paint()..blendMode = BlendMode.clear);

    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
