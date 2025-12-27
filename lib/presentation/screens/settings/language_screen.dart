import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/language_provider.dart';
import '../../../data/services/language_service.dart';
import '../../../data/services/libretranslate_service.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  final LanguageService _languageService = LanguageService();
  final LibreTranslateService _translateService = LibreTranslateService();
  bool _isTranslating = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languages = LanguageService.getSupportedLanguages();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)?.languageTitle ?? 'Ngôn ngữ',
          style: TextStyle(color: theme.textTheme.titleLarge?.color),
        ),
        elevation: 0,
      ),
      body: Consumer<LanguageProvider>(
        builder: (context, languageProvider, _) {
          final currentLanguageCode = languageProvider.currentLanguageCode;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: theme.cardColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.languageSelectPrompt ??
                            'Chọn ngôn ngữ cho ứng dụng',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)?.languageSelectDesc ??
                            'Thay đổi ngôn ngữ sẽ áp dụng cho toàn bộ giao diện ứng dụng',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Language options
                ...languages.map((lang) {
                  final isSelected = lang['code'] == currentLanguageCode;
                  return _buildLanguageTile(
                    context: context,
                    theme: theme,
                    language: lang,
                    isSelected: isSelected,
                    onTap: () async {
                      final locale = Locale(lang['code']!);
                      final languageCode = lang['code']!;
                      
                      // Kiểm tra xem ngôn ngữ có trong supportedLocales không
                      const supportedLocales = ['vi', 'en', 'zh'];
                      final needsTranslation = !supportedLocales.contains(languageCode) && 
                                             languageProvider.useLibreTranslate;
                      
                      if (needsTranslation && mounted) {
                        setState(() {
                          _isTranslating = true;
                        });
                        
                        // Kiểm tra API health
                        final isHealthy = await _translateService.checkApiHealth();
                        
                        if (!isHealthy && mounted) {
                          setState(() {
                            _isTranslating = false;
                          });
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Không thể kết nối đến dịch vụ dịch thuật. Vui lòng thử lại sau.',
                              ),
                              backgroundColor: Colors.orange,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          return;
                        }
                      }
                      
                      await languageProvider.setLanguage(locale);
                      await _languageService.setLanguage(languageCode);

                      if (mounted) {
                        setState(() {
                          _isTranslating = false;
                        });
                        
                        final message = needsTranslation
                            ? 'Đã chuyển sang ${lang['name']} (đang sử dụng dịch vụ dịch thuật)'
                            : 'Đã chuyển sang ${lang['name']}';
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  );
                }),

                const SizedBox(height: 16),

                // Auto-translate section
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.translate,
                            color: theme.textTheme.bodyLarge?.color,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)?.languageAutoTranslate ??
                                'Tự động dịch nội dung',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)?.languageAutoTranslateDesc ??
                            'Tự động dịch posts và comments sang ngôn ngữ bạn đã chọn',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Switch(
                        value: languageProvider.autoTranslate,
                        onChanged: (value) async {
                          await languageProvider.setAutoTranslate(value);
                          await _languageService.setAutoTranslate(value);

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  value
                                      ? 'Đã bật tự động dịch'
                                      : 'Đã tắt tự động dịch',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // LibreTranslate section
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.translate,
                            color: theme.textTheme.bodyLarge?.color,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sử dụng LibreTranslate',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: theme.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tự động dịch giao diện sang các ngôn ngữ chưa được hỗ trợ sẵn',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Bật dịch tự động cho ngôn ngữ mới',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                          if (_isTranslating)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Switch(
                              value: languageProvider.useLibreTranslate,
                              onChanged: (value) async {
                                await languageProvider.setUseLibreTranslate(value);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        value
                                            ? 'Đã bật dịch tự động'
                                            : 'Đã tắt dịch tự động',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Info section
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.primaryColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)?.languageInfo ??
                              'Một số tính năng có thể chưa được dịch sang tất cả ngôn ngữ',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLanguageTile({
    required BuildContext context,
    required ThemeData theme,
    required Map<String, String> language,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : theme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Flag emoji
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.scaffoldBackgroundColor,
              ),
              alignment: Alignment.center,
              child: Text(
                language['flag'] ?? '🌐',
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(width: 16),
            // Language info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    language['name'] ?? '',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    language['native'] ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            // Check icon
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).primaryColor,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
