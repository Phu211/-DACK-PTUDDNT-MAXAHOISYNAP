/// Utility class để kiểm tra độ mạnh của mật khẩu.
class PasswordValidator {
  /// Kiểm tra độ mạnh mật khẩu và trả về điểm số (0-100).
  /// 0-30: Yếu
  /// 31-60: Trung bình
  /// 61-80: Mạnh
  /// 81-100: Rất mạnh
  static int calculateStrength(String password) {
    if (password.isEmpty) return 0;

    int score = 0;

    // Độ dài (tối đa 30 điểm)
    if (password.length >= 8) score += 10;
    if (password.length >= 12) score += 10;
    if (password.length >= 16) score += 10;

    // Chữ thường (10 điểm)
    if (password.contains(RegExp(r'[a-z]'))) score += 10;

    // Chữ hoa (10 điểm)
    if (password.contains(RegExp(r'[A-Z]'))) score += 10;

    // Số (10 điểm)
    if (password.contains(RegExp(r'[0-9]'))) score += 10;

    // Ký tự đặc biệt (10 điểm)
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score += 10;

    // Độ phức tạp (20 điểm)
    // Có cả chữ hoa, chữ thường, số và ký tự đặc biệt
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    int complexityCount = 0;
    if (hasLower) complexityCount++;
    if (hasUpper) complexityCount++;
    if (hasDigit) complexityCount++;
    if (hasSpecial) complexityCount++;

    if (complexityCount == 4)
      score += 20;
    else if (complexityCount == 3)
      score += 10;

    return score.clamp(0, 100);
  }

  /// Lấy mô tả độ mạnh mật khẩu.
  static String getStrengthLabel(int strength) {
    if (strength <= 30) return 'Yếu';
    if (strength <= 60) return 'Trung bình';
    if (strength <= 80) return 'Mạnh';
    return 'Rất mạnh';
  }

  /// Lấy màu sắc cho độ mạnh mật khẩu.
  static int getStrengthColor(int strength) {
    if (strength <= 30) return 0xFFFF5252; // Red
    if (strength <= 60) return 0xFFFF9800; // Orange
    if (strength <= 80) return 0xFFFFC107; // Amber
    return 0xFF4CAF50; // Green
  }

  /// Kiểm tra mật khẩu có đủ mạnh không (>= 60 điểm).
  static bool isStrongEnough(String password) {
    return calculateStrength(password) >= 60;
  }

  /// Lấy danh sách gợi ý để cải thiện mật khẩu.
  static List<String> getSuggestions(String password) {
    final suggestions = <String>[];
    final strength = calculateStrength(password);

    if (strength >= 60) {
      return suggestions; // Mật khẩu đã đủ mạnh
    }

    if (password.length < 8) {
      suggestions.add('Mật khẩu nên có ít nhất 8 ký tự');
    }

    if (!password.contains(RegExp(r'[a-z]'))) {
      suggestions.add('Thêm chữ thường');
    }

    if (!password.contains(RegExp(r'[A-Z]'))) {
      suggestions.add('Thêm chữ hoa');
    }

    if (!password.contains(RegExp(r'[0-9]'))) {
      suggestions.add('Thêm số');
    }

    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      suggestions.add('Thêm ký tự đặc biệt (!@#\$%...)');
    }

    return suggestions;
  }
}
