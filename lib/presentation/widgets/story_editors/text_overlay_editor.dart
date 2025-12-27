import 'package:flutter/material.dart';
import '../../../data/models/story_element_model.dart';

class TextOverlayEditor extends StatefulWidget {
  final Function(StoryTextOverlay) onTextAdded;

  const TextOverlayEditor({super.key, required this.onTextAdded});

  @override
  State<TextOverlayEditor> createState() => _TextOverlayEditorState();
}

class _TextOverlayEditorState extends State<TextOverlayEditor> {
  final TextEditingController _textController = TextEditingController();
  Color _selectedColor = Colors.white;
  double _fontSize = 24.0;
  bool _isBold = false;
  bool _isItalic = false;

  final List<Color> _colors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.cyan,
  ];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _textController,
              style: TextStyle(
                color: _selectedColor,
                fontSize: _fontSize,
                fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
                fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
              ),
              decoration: InputDecoration(
                hintText: 'Nhập text...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderSide: BorderSide(color: _selectedColor)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _selectedColor)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _selectedColor, width: 2)),
              ),
            ),
          ),
          // Color picker
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Màu:', style: TextStyle(color: Colors.black87)),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: _colors.map((color) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedColor = color;
                          });
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: _selectedColor == color ? Colors.blue : Colors.grey, width: 2),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Font size slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kích thước: ${_fontSize.toInt()}', style: const TextStyle(color: Colors.black87)),
                Slider(
                  value: _fontSize,
                  min: 12,
                  max: 72,
                  onChanged: (value) {
                    setState(() {
                      _fontSize = value;
                    });
                  },
                ),
              ],
            ),
          ),
          // Style buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.format_bold, color: _isBold ? Colors.blue : Colors.grey),
                  onPressed: () {
                    setState(() {
                      _isBold = !_isBold;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(Icons.format_italic, color: _isItalic ? Colors.blue : Colors.grey),
                  onPressed: () {
                    setState(() {
                      _isItalic = !_isItalic;
                    });
                  },
                ),
              ],
            ),
          ),
          const Spacer(),
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy', style: TextStyle(color: Colors.black87)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_textController.text.trim().isNotEmpty) {
                      final textOverlay = StoryTextOverlay(
                        text: _textController.text.trim(),
                        x: 0.5,
                        y: 0.5,
                        color: '#${_selectedColor.value.toRadixString(16).substring(2)}',
                        fontSize: _fontSize,
                        isBold: _isBold,
                        isItalic: _isItalic,
                        scale: 1.0,
                      );
                      widget.onTextAdded(textOverlay);
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  child: const Text('Thêm'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
