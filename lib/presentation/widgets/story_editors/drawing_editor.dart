import 'package:flutter/material.dart';
import '../../../data/models/story_element_model.dart';

class DrawingEditor extends StatefulWidget {
  final Function(StoryDrawing) onDrawingComplete;

  const DrawingEditor({super.key, required this.onDrawingComplete});

  @override
  State<DrawingEditor> createState() => _DrawingEditorState();
}

class _DrawingEditorState extends State<DrawingEditor> {
  List<DrawingPoint> _points = [];
  Color _selectedColor = Colors.black;
  double _strokeWidth = 3.0;

  final List<Color> _colors = [
    Colors.black,
    Colors.white,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
  ];

  void _onPanStart(DragStartDetails details, Size size) {
    setState(() {
      _points.add(DrawingPoint(x: details.localPosition.dx / size.width, y: details.localPosition.dy / size.height));
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    setState(() {
      _points.add(DrawingPoint(x: details.localPosition.dx / size.width, y: details.localPosition.dy / size.height));
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // Không clear points ở đây, để có thể vẽ tiếp hoặc lưu khi nhấn Xong
  }

  void _saveCurrentDrawing() {
    if (_points.isNotEmpty) {
      final drawing = StoryDrawing(
        points: List.from(_points),
        color: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        strokeWidth: _strokeWidth,
      );
      widget.onDrawingComplete(drawing);
      setState(() {
        _points.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      color: Colors.white,
      child: Column(
        children: [
          // Color picker
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text('Màu:', style: TextStyle(color: Colors.black87)),
                const SizedBox(width: 8),
                ..._colors.map((color) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColor = color;
                      });
                    },
                    child: Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: _selectedColor == color ? Colors.blue : Colors.grey, width: 2),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Stroke width
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Độ dày:', style: TextStyle(color: Colors.black87)),
                Expanded(
                  child: Slider(
                    value: _strokeWidth,
                    min: 1,
                    max: 10,
                    onChanged: (value) {
                      setState(() {
                        _strokeWidth = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          // Drawing area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: (details) => _onPanStart(details, Size(constraints.maxWidth, constraints.maxHeight)),
                  onPanUpdate: (details) => _onPanUpdate(details, Size(constraints.maxWidth, constraints.maxHeight)),
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    painter: DrawingPainter(points: _points, color: _selectedColor, strokeWidth: _strokeWidth),
                    child: Container(),
                  ),
                );
              },
            ),
          ),
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _points.clear();
                    });
                  },
                  child: const Text('Xóa', style: TextStyle(color: Colors.black87)),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Lưu drawing hiện tại trước khi đóng
                    _saveCurrentDrawing();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  child: const Text('Xong'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawingPoint> points;
  final Color color;
  final double strokeWidth;

  DrawingPainter({required this.points, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(
        Offset(points[i].x * size.width, points[i].y * size.height),
        Offset(points[i + 1].x * size.width, points[i + 1].y * size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
