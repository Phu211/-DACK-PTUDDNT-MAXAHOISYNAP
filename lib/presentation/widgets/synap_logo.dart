import 'package:flutter/material.dart';

class SynapLogo extends StatelessWidget {
  final double size;
  final bool showText;

  const SynapLogo({
    super.key,
    this.size = 40,
    this.showText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipOval(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF00D4FF), // Cyan
                  Color(0xFF7B2CBF), // Magenta/Purple
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D4FF).withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: CustomPaint(
              painter: _BrainIconPainter(),
            ),
          ),
        ),
        if (showText) ...[
          const SizedBox(height: 8),
          const Text(
            'Synap',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D1B3D),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _BrainIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final fillPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    // Draw brain shape (simplified)
    final brainPath = Path();
    
    // Left hemisphere
    brainPath.moveTo(size.width * 0.3, size.height * 0.2);
    brainPath.quadraticBezierTo(size.width * 0.15, size.height * 0.3, size.width * 0.2, size.height * 0.5);
    brainPath.quadraticBezierTo(size.width * 0.15, size.height * 0.7, size.width * 0.3, size.height * 0.8);
    brainPath.quadraticBezierTo(size.width * 0.35, size.height * 0.85, size.width * 0.4, size.height * 0.75);
    brainPath.quadraticBezierTo(size.width * 0.35, size.height * 0.6, size.width * 0.4, size.height * 0.5);
    brainPath.quadraticBezierTo(size.width * 0.35, size.height * 0.4, size.width * 0.3, size.height * 0.2);
    
    // Right hemisphere
    brainPath.moveTo(size.width * 0.7, size.height * 0.2);
    brainPath.quadraticBezierTo(size.width * 0.85, size.height * 0.3, size.width * 0.8, size.height * 0.5);
    brainPath.quadraticBezierTo(size.width * 0.85, size.height * 0.7, size.width * 0.7, size.height * 0.8);
    brainPath.quadraticBezierTo(size.width * 0.65, size.height * 0.85, size.width * 0.6, size.height * 0.75);
    brainPath.quadraticBezierTo(size.width * 0.65, size.height * 0.6, size.width * 0.6, size.height * 0.5);
    brainPath.quadraticBezierTo(size.width * 0.65, size.height * 0.4, size.width * 0.7, size.height * 0.2);
    
    // Center connection
    brainPath.moveTo(size.width * 0.4, size.height * 0.5);
    brainPath.lineTo(size.width * 0.6, size.height * 0.5);
    
    canvas.drawPath(brainPath, fillPaint);
    canvas.drawPath(brainPath, paint);
    
    // Draw neural connections (simplified)
    final connectionPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    // Draw some connection lines
    canvas.drawLine(
      Offset(size.width * 0.3, size.height * 0.4),
      Offset(size.width * 0.5, size.height * 0.3),
      connectionPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.7, size.height * 0.4),
      Offset(size.width * 0.5, size.height * 0.3),
      connectionPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.3, size.height * 0.6),
      Offset(size.width * 0.5, size.height * 0.7),
      connectionPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.7, size.height * 0.6),
      Offset(size.width * 0.5, size.height * 0.7),
      connectionPaint,
    );
    
    // Draw connection nodes
    final nodePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.3), 2, nodePaint);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.7), 2, nodePaint);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.4), 1.5, nodePaint);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.4), 1.5, nodePaint);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.6), 1.5, nodePaint);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.6), 1.5, nodePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


