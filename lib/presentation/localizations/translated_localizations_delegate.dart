import 'package:flutter/material.dart';
import '../../flutter_gen/gen_l10n/app_localizations.dart';

/// Custom LocalizationsDelegate để tự động dịch các chuỗi
/// khi ngôn ngữ không có trong supportedLocales
class TranslatedLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  // Danh sách các ngôn ngữ được hỗ trợ sẵn
  static const List<String> _supportedLocales = ['vi', 'en', 'zh'];

  TranslatedLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    // Hỗ trợ tất cả các ngôn ngữ (sẽ dịch nếu cần)
    return true;
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    // Luôn trả về AppLocalizations gốc
    // Việc dịch sẽ được xử lý ở level cao hơn thông qua TranslationHelper
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(TranslatedLocalizationsDelegate old) => false;
  
  /// Kiểm tra xem ngôn ngữ có cần dịch không
  static bool needsTranslation(String languageCode) {
    return !_supportedLocales.contains(languageCode);
  }
}

