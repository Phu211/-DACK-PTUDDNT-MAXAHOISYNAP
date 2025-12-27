import 'package:flutter/material.dart';

class EffectPicker extends StatelessWidget {
  final Function(String) onEffectSelected;

  const EffectPicker({super.key, required this.onEffectSelected});

  final List<Map<String, dynamic>> _effects = const [
    {'name': 'Không có', 'icon': Icons.filter_none, 'value': null},
    {'name': 'Đen trắng', 'icon': Icons.filter_b_and_w, 'value': 'black_white'},
    {'name': 'Làm mờ', 'icon': Icons.blur_on, 'value': 'blur'},
    {'name': 'Sáng', 'icon': Icons.wb_sunny, 'value': 'bright'},
    {'name': 'Tối', 'icon': Icons.brightness_2, 'value': 'dark'},
    {'name': 'Bão hòa', 'icon': Icons.palette, 'value': 'saturated'},
    {'name': 'Vintage', 'icon': Icons.camera_alt, 'value': 'vintage'},
    {'name': 'Sepia', 'icon': Icons.photo_filter, 'value': 'sepia'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      color: Colors.white,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Chọn hiệu ứng',
              style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _effects.length,
              itemBuilder: (context, index) {
                final effect = _effects[index];
                return GestureDetector(
                  onTap: () {
                    onEffectSelected(effect['value']);
                    Navigator.pop(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(effect['icon'] as IconData, color: Colors.black87, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          effect['name'] as String,
                          style: const TextStyle(color: Colors.black87, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
