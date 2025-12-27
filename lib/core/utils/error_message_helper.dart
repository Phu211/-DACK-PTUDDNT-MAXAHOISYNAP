import 'package:flutter/material.dart';

/// Helper class để format error messages một cách nhất quán
class ErrorMessageHelper {
  /// Chuyển đổi error thành thông báo tiếng Việt dễ hiểu
  static String getErrorMessage(dynamic error, {String? defaultMessage}) {
    final errorString = error.toString().toLowerCase();
    final defaultMsg = defaultMessage ?? 'Đã xảy ra lỗi';

    // Xử lý các lỗi phổ biến
    if (errorString.contains('permission') || errorString.contains('quyền')) {
      return 'Bạn không có quyền thực hiện hành động này';
    }
    
    if (errorString.contains('blocked') || errorString.contains('chặn')) {
      return 'Bạn đã bị chặn hoặc đã chặn người này';
    }
    
    if (errorString.contains('network') || 
        errorString.contains('mạng') ||
        errorString.contains('connection') ||
        errorString.contains('kết nối') ||
        errorString.contains('timeout')) {
      return 'Lỗi kết nối mạng. Vui lòng kiểm tra kết nối internet và thử lại';
    }
    
    if (errorString.contains('empty') || 
        errorString.contains('trống') ||
        errorString.contains('null') ||
        errorString.contains('required')) {
      return 'Thông tin không đầy đủ. Vui lòng kiểm tra lại';
    }
    
    if (errorString.contains('not found') || 
        errorString.contains('không tìm thấy') ||
        errorString.contains('không tồn tại')) {
      return 'Không tìm thấy dữ liệu. Vui lòng thử lại';
    }
    
    if (errorString.contains('invalid') || 
        errorString.contains('không hợp lệ') ||
        errorString.contains('sai định dạng')) {
      return 'Dữ liệu không hợp lệ. Vui lòng kiểm tra lại';
    }
    
    if (errorString.contains('unauthorized') || 
        errorString.contains('chưa đăng nhập') ||
        errorString.contains('authentication')) {
      return 'Bạn cần đăng nhập để thực hiện hành động này';
    }
    
    if (errorString.contains('too many') || 
        errorString.contains('quá nhiều') ||
        errorString.contains('rate limit')) {
      return 'Quá nhiều yêu cầu. Vui lòng thử lại sau';
    }
    
    if (errorString.contains('file') || 
        errorString.contains('tệp') ||
        errorString.contains('upload')) {
      if (errorString.contains('too large') || errorString.contains('quá lớn')) {
        return 'File quá lớn. Vui lòng chọn file nhỏ hơn';
      }
      if (errorString.contains('format') || errorString.contains('định dạng')) {
        return 'Định dạng file không được hỗ trợ';
      }
      return 'Lỗi khi xử lý file. Vui lòng thử lại';
    }
    
    if (errorString.contains('storage') || 
        errorString.contains('lưu trữ') ||
        errorString.contains('firebase storage')) {
      return 'Lỗi lưu trữ dữ liệu. Vui lòng thử lại';
    }
    
    if (errorString.contains('firestore') || 
        errorString.contains('database') ||
        errorString.contains('cơ sở dữ liệu')) {
      return 'Lỗi kết nối cơ sở dữ liệu. Vui lòng thử lại';
    }

    // Nếu không match với bất kỳ pattern nào, trả về error message gốc
    // nhưng loại bỏ các thông tin kỹ thuật không cần thiết
    String cleanError = error.toString();
    
    // Loại bỏ các prefix không cần thiết
    if (cleanError.startsWith('Exception: ')) {
      cleanError = cleanError.substring('Exception: '.length);
    }
    if (cleanError.startsWith('Error: ')) {
      cleanError = cleanError.substring('Error: '.length);
    }
    
    return '$defaultMsg: $cleanError';
  }

  /// Tạo SnackBar với error message đã được format
  static SnackBar createErrorSnackBar(dynamic error, {String? defaultMessage}) {
    final errorMessage = getErrorMessage(error, defaultMessage: defaultMessage);
    return SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  /// Tạo SnackBar thành công
  static SnackBar createSuccessSnackBar(String message) {
    return SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

