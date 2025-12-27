import 'package:flutter/material.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';

class HideMenuItemsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allMenuItems;
  final List<String> hiddenItems;
  final Function(List<String>) onSave;

  const HideMenuItemsDialog({
    required this.allMenuItems,
    required this.hiddenItems,
    required this.onSave,
  });

  @override
  State<HideMenuItemsDialog> createState() => _HideMenuItemsDialogState();
}

class _HideMenuItemsDialogState extends State<HideMenuItemsDialog> {
  late List<String> _selectedHiddenItems;

  @override
  void initState() {
    super.initState();
    _selectedHiddenItems = List.from(widget.hiddenItems);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(strings?.menuHideLess ?? 'Ẩn bớt'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chọn các mục bạn muốn ẩn khỏi menu',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ...widget.allMenuItems.map((item) {
                final isHidden = _selectedHiddenItems.contains(item['id']);
                return CheckboxListTile(
                  title: Row(
                    children: [
                      Icon(
                        item['icon'] as IconData,
                        size: 20,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['title'] as String,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  value: isHidden,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedHiddenItems.add(item['id']);
                      } else {
                        _selectedHiddenItems.remove(item['id']);
                      }
                    });
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                );
              }).toList(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings?.cancel ?? 'Hủy'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_selectedHiddenItems);
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
