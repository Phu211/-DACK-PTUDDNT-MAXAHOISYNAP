import 'package:shared_preferences/shared_preferences.dart';

class MenuPreferencesService {
  static const String _hiddenMenuItemsKey = 'hidden_menu_items';

  // Lưu danh sách các mục menu bị ẩn
  Future<void> saveHiddenMenuItems(List<String> hiddenItems) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_hiddenMenuItemsKey, hiddenItems);
    } catch (e) {
      throw Exception('Failed to save hidden menu items: $e');
    }
  }

  // Lấy danh sách các mục menu bị ẩn
  Future<List<String>> getHiddenMenuItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_hiddenMenuItemsKey) ?? [];
    } catch (e) {
      return [];
    }
  }

  // Kiểm tra xem một mục menu có bị ẩn không
  Future<bool> isMenuItemHidden(String itemId) async {
    final hiddenItems = await getHiddenMenuItems();
    return hiddenItems.contains(itemId);
  }

  // Xóa tất cả các mục menu bị ẩn (hiển thị lại tất cả)
  Future<void> clearHiddenMenuItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_hiddenMenuItemsKey);
    } catch (e) {
      throw Exception('Failed to clear hidden menu items: $e');
    }
  }
}


