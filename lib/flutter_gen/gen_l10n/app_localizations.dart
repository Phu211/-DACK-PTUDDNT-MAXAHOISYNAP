import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Minimal manual localization stub to unblock analyzer/build without codegen.
/// When running `flutter gen-l10n`, this file should be replaced by generated output.
class AppLocalizations {
  AppLocalizations(this.locale);
  final Locale locale;

  static const List<Locale> supportedLocales = [Locale('vi'), Locale('en'), Locale('zh')];

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  // Simple lookup table for the small set of strings we use.
  static final Map<String, Map<String, String>> _localizedValues = {
    'vi': {
      'appTitle': 'Synap',
      'homeTitle': 'Trang chủ',
      'storiesYourStory': 'Tin của bạn',
      'profileTitle': 'Trang cá nhân',
      'editProfile': 'Chỉnh sửa trang cá nhân',
      'friends': 'Bạn bè',
      'viewAllFriends': 'Xem tất cả bạn bè',
      'noPosts': 'Chưa có bài viết nào',
      'savedTitle': 'Đã lưu',
      'savedEmptyTitle': 'Chưa có bài viết nào được lưu',
      'savedEmptyDesc': 'Lưu bài viết để xem lại sau',
      'languageTitle': 'Ngôn ngữ',
      'languageSelectPrompt': 'Chọn ngôn ngữ cho ứng dụng',
      'languageSelectDesc': 'Thay đổi ngôn ngữ sẽ áp dụng cho toàn bộ giao diện ứng dụng',
      'languageAutoTranslate': 'Tự động dịch nội dung',
      'languageAutoTranslateDesc': 'Tự động dịch bài viết và bình luận',
      'languageInfo': 'Một số tính năng có thể chưa được dịch',
      'retry': 'Thử lại',
      'loginRequired': 'Vui lòng đăng nhập',
      'logout': 'Đăng xuất',
      'logoutConfirm': 'Bạn có chắc chắn muốn đăng xuất?',
      'cancel': 'Hủy',
      'timeMgmtTitle': 'Quản lý thời gian',
      'timeMgmtBreakReminder': 'Nhắc nhở nghỉ giải lao',
      'timeMgmtBreakReminderDesc': 'Nhắc bạn nghỉ sau một khoảng thời gian sử dụng ứng dụng',
      'timeMgmtIntervalLabel': 'Khoảng thời gian nhắc',
      'timeMgmtEnabled': 'Đã bật nhắc nhở nghỉ giải lao',
      'timeMgmtDisabled': 'Đã tắt nhắc nhở nghỉ giải lao',
      'timeUsageTitle': 'Thời gian sử dụng hàng ngày',
      'timeUsageToday': 'Hôm nay',
      'timeUsageLast7Days': '7 ngày gần đây',
      'timeUsageNoData': 'Chưa có dữ liệu thời gian sử dụng',
      // Menu
      'menuFriendsOnline': '23 người online',
      'menuMemories': 'Kỷ niệm',
      'menuFindFriends': 'Tìm bạn bè',
      'menuFeed': 'Bảng feed',
      'menuGames': 'Game',
      'menuSaved': 'Đã lưu',
      'menuAnalytics': 'Thống kê cá nhân',
      'menuGroups': 'Nhóm',
      'menuReels': 'Thước phim',
      'menuHideLess': 'Ẩn bớt',
      'menuHelpSupport': 'Trợ giúp và hỗ trợ',
      'menuHelpCenter': 'Trung tâm trợ giúp',
      'menuInAppSupport': 'Hỗ trợ trong ứng dụng',
      'menuReportProblem': 'Báo cáo sự cố',
      'menuSettingsPrivacy': 'Cài đặt và quyền riêng tư',
      'menuSettings': 'Cài đặt',
      'menuTimeManagement': 'Quản lý thời gian',
      'menuDarkMode': 'Chế độ tối',
      'menuLanguage': 'Ngôn ngữ',
      // Create post
      'createPostTitle': 'Tạo bài viết',
      'postShare': 'Đăng bài',
      'postPlaceholder': 'Bạn đang nghĩ gì?',
      'postPhotoVideo': 'Ảnh/video',
      'postTagPeople': 'Gắn thẻ người khác',
      'postFeelings': 'Cảm xúc/hoạt động',
      // Story editor / creator
      'storyNew': 'Mới',
      'storyStickers': 'Nhãn dán',
      'storyTextTool': 'Văn bản',
      'storyMusic': 'Nhạc',
      'storyEffects': 'Hiệu ứng',
      'storyMention': 'Nhắc đến',
      'storyShare': 'Chia sẻ',
      'storyPickMedia': 'Chọn ảnh / video',
      'storyChooseMedia': 'Chọn ảnh / video',
      // Notifications
      'notificationsTitle': 'Thông báo',
      'notificationsLoadError': 'Không thể tải thông báo',
      'notificationsEmpty': 'Chưa có thông báo nào',
      // Post actions
      'postComments': '{count} bình luận',
      'postPlayVideo': 'Phát video',
      'postRemoveTag': 'Gỡ thẻ',
      'postRemoveTagConfirm':
          'Bạn có chắc chắn muốn gỡ thẻ khỏi bài viết này? Bài viết sẽ không hiển thị trong mục "Được gắn thẻ" của bạn nữa.',
      'postRemoveTagSuccess': 'Đã gỡ thẻ khỏi bài viết',
      'postSave': 'Lưu bài viết',
      'postUnsave': 'Xóa khỏi danh sách các mục đã lưu.',
      'postSaveDescription': 'Thêm vào danh sách các mục đã lưu.',
      'postSavedSuccess': 'Đã lưu bài viết',
      'postUnsavedSuccess': 'Đã bỏ lưu bài viết',
      'postHiddenSuccess': 'Đã ẩn bài viết',
      'postTemporarilyHideUser': 'Tạm ẩn người dùng',
      'postTemporarilyHideUserConfirm': 'Tạm ẩn {name} trong 30 ngày',
      'postTemporarilyHideUserSuccess': 'Đã tạm ẩn người dùng trong 30 ngày',
      'postHideAllFromUser': 'Ẩn tất cả bài viết',
      'postHideAllFromUserConfirm': 'Ẩn tất cả từ {name}',
      'postHideAllFromUserSuccess': 'Đã ẩn tất cả bài viết từ người dùng này',
      'postBlockUser': 'Chặn người dùng',
      'postBlockUserConfirm': 'Chặn trang cá nhân của {name}',
      'postBlockUserSuccess': 'Đã chặn người dùng',
      'postDeleteSuccess': 'Đã xóa bài viết',
      'postShare': 'Chia sẻ bài viết',
      'postShareToStory': 'Chia sẻ lên tin của bạn',
      'postShareToProfile': 'Chia sẻ lên trang cá nhân',
      'postShareToProfileSuccess': 'Đã chia sẻ bài viết lên trang cá nhân',
      'postShareToStorySuccess': 'Đã chia sẻ bài viết lên tin của bạn',
      'postTaggedUsers': 'Đã gắn thẻ {users}',
      'timeAgoDays': '{days} ngày trước',
      'timeAgoHours': '{hours} giờ trước',
      'timeAgoMinutes': '{minutes} phút trước',
      'timeAgoJustNow': 'Vừa xong',
      'postShareError': 'Không thể chia sẻ bài viết',
      'postReactionError': 'Không thể bày tỏ cảm xúc',
      'postReactionDisplayError': 'Không thể hiển thị bày tỏ cảm xúc',
      'postNoReactions': 'Chưa có người nào',
      'postAllReactions': 'Tất cả cảm xúc',
      // Comments
      'commentEdit': 'Chỉnh sửa bình luận',
      'commentDelete': 'Xóa bình luận',
      'commentDeleteConfirm': 'Bạn có chắc chắn muốn xóa bình luận này?',
      'commentUpdatedSuccess': 'Đã cập nhật bình luận',
      'commentUpdateError': 'Lỗi cập nhật bình luận',
      'commentEdited': '• Đã chỉnh sửa',
      // Create post
      'createPostEditTitle': 'Chỉnh sửa bài viết',
      'createPostContentRequired': 'Vui lòng nhập nội dung hoặc chọn ảnh/video/GIF',
      'createPostAlbumFeature': 'Tính năng album đang phát triển',
      'createPostUploadingImages': 'Đang tải ảnh lên...',
      'createPostUploadingVideo': 'Đang tải video lên...',
      'createPostProcessing': 'Đang xử lý...',
      'createPostUploadProgress': '{percent}% Hoàn tất',
      // AI Assistant
      'aiAssistantGetSuggestions': 'Nhận gợi ý từ AI',
      'aiAssistantLoading': 'Đang tải...',
      'aiAssistantTitle': 'Gợi ý từ AI',
      'aiAssistantCaption': 'Caption cải thiện',
      'aiAssistantHashtags': 'Hashtags gợi ý',
      'aiAssistantTranslation': 'Bản dịch',
      'aiAssistantSentiment': 'Phân tích cảm xúc',
      'aiAssistantCaptionApplied': 'Đã áp dụng caption',
      'aiAssistantHashtagsApplied': 'Đã thêm hashtags',
      'aiAssistantTranslationApplied': 'Đã áp dụng bản dịch',
      'aiAssistantEmptyContent': 'Vui lòng nhập nội dung hoặc chọn ảnh để nhận gợi ý từ AI',
      'aiAssistantError': 'Không thể tạo gợi ý. Vui lòng thử lại.',
      'aiAssistantLoadError': 'Lỗi tải gợi ý AI',
    },
    'en': {
      'appTitle': 'Synap',
      'homeTitle': 'Home',
      'storiesYourStory': 'Your story',
      'profileTitle': 'Profile',
      'editProfile': 'Edit profile',
      'friends': 'Friends',
      'viewAllFriends': 'View all friends',
      'noPosts': 'No posts yet',
      'savedTitle': 'Saved',
      'savedEmptyTitle': 'No saved posts',
      'savedEmptyDesc': 'Save posts to view them later',
      'languageTitle': 'Language',
      'languageSelectPrompt': 'Choose the app language',
      'languageSelectDesc': 'Language change applies to the whole app',
      'languageAutoTranslate': 'Auto translate content',
      'languageAutoTranslateDesc': 'Automatically translate posts and comments',
      'languageInfo': 'Some features might not be translated yet',
      'retry': 'Retry',
      'loginRequired': 'Please log in',
      'logout': 'Log out',
      'logoutConfirm': 'Are you sure you want to log out?',
      'cancel': 'Cancel',
      'timeMgmtTitle': 'Time management',
      'timeMgmtBreakReminder': 'Break reminder',
      'timeMgmtBreakReminderDesc': 'Remind you to take a break after using the app for a while',
      'timeMgmtIntervalLabel': 'Reminder interval',
      'timeMgmtEnabled': 'Break reminder enabled',
      'timeMgmtDisabled': 'Break reminder disabled',
      'timeUsageTitle': 'Daily usage time',
      'timeUsageToday': 'Today',
      'timeUsageLast7Days': 'Last 7 days',
      'timeUsageNoData': 'No usage data yet',
      // Menu
      'menuFriendsOnline': '23 friends online',
      'menuMemories': 'Memories',
      'menuFindFriends': 'Find friends',
      'menuFeed': 'Feed',
      'menuGames': 'Games',
      'menuSaved': 'Saved',
      'menuAnalytics': 'Personal Analytics',
      'menuGroups': 'Groups',
      'menuReels': 'Reels',
      'menuHideLess': 'See less',
      'menuHelpSupport': 'Help & support',
      'menuHelpCenter': 'Help center',
      'menuInAppSupport': 'In-app support',
      'menuReportProblem': 'Report a problem',
      'menuSettingsPrivacy': 'Settings & privacy',
      'menuSettings': 'Settings',
      'menuTimeManagement': 'Time management',
      'menuDarkMode': 'Dark mode',
      'menuLanguage': 'Language',
      // Create post
      'createPostTitle': 'Create post',
      'postShare': 'Post',
      'postPlaceholder': 'What\'s on your mind?',
      'postPhotoVideo': 'Photo/video',
      'postTagPeople': 'Tag people',
      'postFeelings': 'Feeling/activity',
      // Story editor / creator
      'storyNew': 'New',
      'storyStickers': 'Stickers',
      'storyTextTool': 'Text',
      'storyMusic': 'Music',
      'storyEffects': 'Effects',
      'storyMention': 'Mention',
      'storyShare': 'Share',
      'storyPickMedia': 'Choose photo / video',
      'storyChooseMedia': 'Choose photo / video',
      // Notifications
      'notificationsTitle': 'Notifications',
      'notificationsLoadError': 'Could not load notifications',
      'notificationsEmpty': 'No notifications yet',
      // Post actions
      'postComments': '{count} comments',
      'postPlayVideo': 'Play video',
      'postRemoveTag': 'Remove tag',
      'postRemoveTagConfirm':
          'Are you sure you want to remove your tag from this post? The post will no longer appear in your "Tagged" section.',
      'postRemoveTagSuccess': 'Tag removed from post',
      'postSave': 'Save post',
      'postUnsave': 'Remove from saved items',
      'postSaveDescription': 'Add to saved items',
      'postSavedSuccess': 'Post saved',
      'postUnsavedSuccess': 'Post unsaved',
      'postHiddenSuccess': 'Post hidden',
      'postTemporarilyHideUser': 'Temporarily hide user',
      'postTemporarilyHideUserConfirm': 'Temporarily hide {name} for 30 days',
      'postTemporarilyHideUserSuccess': 'User temporarily hidden for 30 days',
      'postHideAllFromUser': 'Hide all posts',
      'postHideAllFromUserConfirm': 'Hide all from {name}',
      'postHideAllFromUserSuccess': 'All posts from this user have been hidden',
      'postBlockUser': 'Block user',
      'postBlockUserConfirm': 'Block {name}\'s profile',
      'postBlockUserSuccess': 'User blocked',
      'postDeleteSuccess': 'Post deleted',
      'postShare': 'Share post',
      'postShareToStory': 'Share to your story',
      'postShareToProfile': 'Share to profile',
      'postShareToProfileSuccess': 'Post shared to profile',
      'postShareToStorySuccess': 'Post shared to your story',
      'postTaggedUsers': 'Tagged {users}',
      'timeAgoDays': '{days} days ago',
      'timeAgoHours': '{hours} hours ago',
      'timeAgoMinutes': '{minutes} minutes ago',
      'timeAgoJustNow': 'Just now',
      'postShareError': 'Cannot share post',
      'postReactionError': 'Cannot react to post',
      'postReactionDisplayError': 'Cannot display reactions',
      'postNoReactions': 'No reactions yet',
      'postAllReactions': 'All reactions',
      // Comments
      'commentEdit': 'Edit comment',
      'commentDelete': 'Delete comment',
      'commentDeleteConfirm': 'Are you sure you want to delete this comment?',
      'commentUpdatedSuccess': 'Comment updated',
      'commentUpdateError': 'Error updating comment',
      'commentEdited': '• Edited',
      // Create post
      'createPostEditTitle': 'Edit post',
      'createPostContentRequired': 'Please enter content or select image/video/GIF',
      'createPostAlbumFeature': 'Album feature is under development',
      'createPostUploadingImages': 'Uploading images...',
      'createPostUploadingVideo': 'Uploading video...',
      'createPostProcessing': 'Processing...',
      'createPostUploadProgress': '{percent}% Complete',
      // AI Assistant
      'aiAssistantGetSuggestions': 'Get AI suggestions',
      'aiAssistantLoading': 'Loading...',
      'aiAssistantTitle': 'AI Suggestions',
      'aiAssistantCaption': 'Improved caption',
      'aiAssistantHashtags': 'Suggested hashtags',
      'aiAssistantTranslation': 'Translation',
      'aiAssistantSentiment': 'Sentiment analysis',
      'aiAssistantCaptionApplied': 'Caption applied',
      'aiAssistantHashtagsApplied': 'Hashtags added',
      'aiAssistantTranslationApplied': 'Translation applied',
      'aiAssistantEmptyContent': 'Please enter content or select an image to get AI suggestions',
      'aiAssistantError': 'Cannot generate suggestions. Please try again.',
      'aiAssistantLoadError': 'Error loading AI suggestions',
    },
    'zh': {
      'appTitle': 'Synap',
      'homeTitle': '主页',
      'storiesYourStory': '你的动态',
      'profileTitle': '个人主页',
      'editProfile': '编辑个人主页',
      'friends': '朋友',
      'viewAllFriends': '查看所有朋友',
      'noPosts': '还没有帖子',
      'savedTitle': '已保存',
      'savedEmptyTitle': '还没有保存的帖子',
      'savedEmptyDesc': '保存帖子以便稍后查看',
      'languageTitle': '语言',
      'languageSelectPrompt': '选择应用语言',
      'languageSelectDesc': '更改语言将作用于整个应用界面',
      'languageAutoTranslate': '自动翻译内容',
      'languageAutoTranslateDesc': '自动翻译帖子和评论',
      'languageInfo': '部分功能可能尚未完全翻译',
      'retry': '重试',
      'loginRequired': '请登录',
      'logout': '退出登录',
      'logoutConfirm': '确定要退出登录吗？',
      'cancel': '取消',
      'timeMgmtTitle': '时间管理',
      'timeMgmtBreakReminder': '休息提醒',
      'timeMgmtBreakReminderDesc': '使用应用一段时间后提醒你休息',
      'timeMgmtIntervalLabel': '提醒间隔',
      'timeMgmtEnabled': '已开启休息提醒',
      'timeMgmtDisabled': '已关闭休息提醒',
      'timeUsageTitle': '每日使用时间',
      'timeUsageToday': '今天',
      'timeUsageLast7Days': '最近 7 天',
      'timeUsageNoData': '暂无使用时间数据',
      // Menu
      'menuFriendsOnline': '23 位好友在线',
      'menuMemories': '回忆',
      'menuFindFriends': '寻找朋友',
      'menuFeed': '动态',
      'menuGames': '游戏',
      'menuSaved': '已保存',
      'menuAnalytics': '个人统计',
      'menuGroups': '群组',
      'menuReels': '短片',
      'menuHideLess': '收起',
      'menuHelpSupport': '帮助与支持',
      'menuHelpCenter': '帮助中心',
      'menuInAppSupport': '应用内支持',
      'menuReportProblem': '报告问题',
      'menuSettingsPrivacy': '设置与隐私',
      'menuSettings': '设置',
      'menuTimeManagement': '时间管理',
      'menuDarkMode': '深色模式',
      'menuLanguage': '语言',
      // Create post
      'createPostTitle': '发布帖子',
      'postShare': '发布',
      'postPlaceholder': '你在想什么？',
      'postPhotoVideo': '照片/视频',
      'postTagPeople': '标记好友',
      'postFeelings': '心情/活动',
      // Story editor / creator
      'storyNew': '新的',
      'storyStickers': '贴纸',
      'storyTextTool': '文字',
      'storyMusic': '音乐',
      'storyEffects': '效果',
      'storyMention': '提及',
      'storyShare': '分享',
      'storyPickMedia': '选择照片 / 视频',
      'storyChooseMedia': '选择照片 / 视频',
      // Notifications
      'notificationsTitle': '通知',
      'notificationsLoadError': '无法加载通知',
      'notificationsEmpty': '还没有通知',
      // Post actions
      'postComments': '{count} 条评论',
      'postPlayVideo': '播放视频',
      'postRemoveTag': '移除标签',
      'postRemoveTagConfirm': '您确定要从此帖子中移除您的标签吗？该帖子将不再出现在您的"已标记"部分。',
      'postRemoveTagSuccess': '已从帖子中移除标签',
      'postSave': '保存帖子',
      'postUnsave': '从已保存项目中移除',
      'postSaveDescription': '添加到已保存项目',
      'postSavedSuccess': '帖子已保存',
      'postUnsavedSuccess': '帖子已取消保存',
      'postHiddenSuccess': '帖子已隐藏',
      'postTemporarilyHideUser': '临时隐藏用户',
      'postTemporarilyHideUserConfirm': '临时隐藏 {name} 30 天',
      'postTemporarilyHideUserSuccess': '用户已临时隐藏 30 天',
      'postHideAllFromUser': '隐藏所有帖子',
      'postHideAllFromUserConfirm': '隐藏来自 {name} 的所有内容',
      'postHideAllFromUserSuccess': '已隐藏来自此用户的所有帖子',
      'postBlockUser': '屏蔽用户',
      'postBlockUserConfirm': '屏蔽 {name} 的个人主页',
      'postBlockUserSuccess': '用户已屏蔽',
      'postDeleteSuccess': '帖子已删除',
      'postShareToStory': '分享到您的动态',
      'postShareToProfile': '分享到个人主页',
      'postShareToProfileSuccess': '帖子已分享到个人主页',
      'postShareToStorySuccess': '帖子已分享到您的动态',
      'postTaggedUsers': '标记了 {users}',
      'timeAgoDays': '{days} 天前',
      'timeAgoHours': '{hours} 小时前',
      'timeAgoMinutes': '{minutes} 分钟前',
      'timeAgoJustNow': '刚刚',
      'postShareError': '无法分享帖子',
      'postReactionError': '无法对帖子做出反应',
      'postReactionDisplayError': '无法显示反应',
      'postNoReactions': '还没有反应',
      'postAllReactions': '所有反应',
      // Comments
      'commentEdit': '编辑评论',
      'commentDelete': '删除评论',
      'commentDeleteConfirm': '您确定要删除此评论吗？',
      'commentUpdatedSuccess': '评论已更新',
      'commentUpdateError': '更新评论时出错',
      'commentEdited': '• 已编辑',
      // Create post
      'createPostEditTitle': '编辑帖子',
      'createPostContentRequired': '请输入内容或选择图片/视频/GIF',
      'createPostAlbumFeature': '相册功能正在开发中',
      'createPostUploadingImages': '正在上传图片...',
      'createPostUploadingVideo': '正在上传视频...',
      'createPostProcessing': '正在处理...',
      'createPostUploadProgress': '{percent}% 完成',
      // AI Assistant
      'aiAssistantGetSuggestions': '获取 AI 建议',
      'aiAssistantLoading': '加载中...',
      'aiAssistantTitle': 'AI 建议',
      'aiAssistantCaption': '改进的标题',
      'aiAssistantHashtags': '建议的标签',
      'aiAssistantTranslation': '翻译',
      'aiAssistantSentiment': '情感分析',
      'aiAssistantCaptionApplied': '标题已应用',
      'aiAssistantHashtagsApplied': '标签已添加',
      'aiAssistantTranslationApplied': '翻译已应用',
      'aiAssistantEmptyContent': '请输入内容或选择图片以获取 AI 建议',
      'aiAssistantError': '无法生成建议。请重试。',
      'aiAssistantLoadError': '加载 AI 建议时出错',
    },
  };

  String _t(String key) => _localizedValues[locale.languageCode]?[key] ?? _localizedValues['en']![key]!;

  String get appTitle => _t('appTitle');
  String get homeTitle => _t('homeTitle');
  String get storiesYourStory => _t('storiesYourStory');
  String get profileTitle => _t('profileTitle');
  String get editProfile => _t('editProfile');
  String get friends => _t('friends');
  String get viewAllFriends => _t('viewAllFriends');
  String get noPosts => _t('noPosts');
  String get savedTitle => _t('savedTitle');
  String get savedEmptyTitle => _t('savedEmptyTitle');
  String get savedEmptyDesc => _t('savedEmptyDesc');
  String get languageTitle => _t('languageTitle');
  String get languageSelectPrompt => _t('languageSelectPrompt');
  String get languageSelectDesc => _t('languageSelectDesc');
  String get languageAutoTranslate => _t('languageAutoTranslate');
  String get languageAutoTranslateDesc => _t('languageAutoTranslateDesc');
  String get languageInfo => _t('languageInfo');
  String get retry => _t('retry');
  String get loginRequired => _t('loginRequired');
  String get logout => _t('logout');
  String get logoutConfirm => _t('logoutConfirm');
  String get cancel => _t('cancel');
  String get timeMgmtTitle => _t('timeMgmtTitle');
  String get timeMgmtBreakReminder => _t('timeMgmtBreakReminder');
  String get timeMgmtBreakReminderDesc => _t('timeMgmtBreakReminderDesc');
  String get timeMgmtIntervalLabel => _t('timeMgmtIntervalLabel');
  String get timeMgmtEnabled => _t('timeMgmtEnabled');
  String get timeMgmtDisabled => _t('timeMgmtDisabled');
  String get timeUsageTitle => _t('timeUsageTitle');
  String get timeUsageToday => _t('timeUsageToday');
  String get timeUsageLast7Days => _t('timeUsageLast7Days');
  String get timeUsageNoData => _t('timeUsageNoData');
  // Menu
  String get menuFriendsOnline => _t('menuFriendsOnline');
  String get menuMemories => _t('menuMemories');
  String get menuFindFriends => _t('menuFindFriends');
  String get menuFeed => _t('menuFeed');
  String get menuGames => _t('menuGames');
  String get menuSaved => _t('menuSaved');
  String get menuAnalytics => _t('menuAnalytics');
  String get menuGroups => _t('menuGroups');
  String get menuReels => _t('menuReels');
  String get menuHideLess => _t('menuHideLess');
  String get menuHelpSupport => _t('menuHelpSupport');
  String get menuHelpCenter => _t('menuHelpCenter');
  String get menuInAppSupport => _t('menuInAppSupport');
  String get menuReportProblem => _t('menuReportProblem');
  String get menuSettingsPrivacy => _t('menuSettingsPrivacy');
  String get menuSettings => _t('menuSettings');
  String get menuTimeManagement => _t('menuTimeManagement');
  String get menuDarkMode => _t('menuDarkMode');
  String get menuLanguage => _t('menuLanguage');
  // Create post
  String get createPostTitle => _t('createPostTitle');
  String get postShare => _t('postShare');
  String get postPlaceholder => _t('postPlaceholder');
  String get postPhotoVideo => _t('postPhotoVideo');
  String get postTagPeople => _t('postTagPeople');
  String get postFeelings => _t('postFeelings');
  // Story editor / creator
  String get storyNew => _t('storyNew');
  String get storyStickers => _t('storyStickers');
  String get storyTextTool => _t('storyTextTool');
  String get storyMusic => _t('storyMusic');
  String get storyEffects => _t('storyEffects');
  String get storyMention => _t('storyMention');
  String get storyShare => _t('storyShare');
  String get storyPickMedia => _t('storyPickMedia');
  String get storyChooseMedia => _t('storyChooseMedia');
  // Notifications
  String get notificationsTitle => _t('notificationsTitle');
  String get notificationsLoadError => _t('notificationsLoadError');
  String get notificationsEmpty => _t('notificationsEmpty');
  // Post actions
  String postComments(int count) => _t('postComments').replaceAll('{count}', count.toString());
  String get postPlayVideo => _t('postPlayVideo');
  String get postRemoveTag => _t('postRemoveTag');
  String get postRemoveTagConfirm => _t('postRemoveTagConfirm');
  String get postRemoveTagSuccess => _t('postRemoveTagSuccess');
  String get postSave => _t('postSave');
  String get postUnsave => _t('postUnsave');
  String get postSaveDescription => _t('postSaveDescription');
  String get postSavedSuccess => _t('postSavedSuccess');
  String get postUnsavedSuccess => _t('postUnsavedSuccess');
  String get postHiddenSuccess => _t('postHiddenSuccess');
  String get postTemporarilyHideUser => _t('postTemporarilyHideUser');
  String postTemporarilyHideUserConfirm(String name) => _t('postTemporarilyHideUserConfirm').replaceAll('{name}', name);
  String get postTemporarilyHideUserSuccess => _t('postTemporarilyHideUserSuccess');
  String get postHideAllFromUser => _t('postHideAllFromUser');
  String postHideAllFromUserConfirm(String name) => _t('postHideAllFromUserConfirm').replaceAll('{name}', name);
  String get postHideAllFromUserSuccess => _t('postHideAllFromUserSuccess');
  String get postBlockUser => _t('postBlockUser');
  String postBlockUserConfirm(String name) => _t('postBlockUserConfirm').replaceAll('{name}', name);
  String get postBlockUserSuccess => _t('postBlockUserSuccess');
  String get postDeleteSuccess => _t('postDeleteSuccess');
  String get postShareToStory => _t('postShareToStory');
  String get postShareToProfile => _t('postShareToProfile');
  String get postShareToProfileSuccess => _t('postShareToProfileSuccess');
  String get postShareToStorySuccess => _t('postShareToStorySuccess');
  String postTaggedUsers(String users) => _t('postTaggedUsers').replaceAll('{users}', users);
  String timeAgoDays(int days) => _t('timeAgoDays').replaceAll('{days}', days.toString());
  String timeAgoHours(int hours) => _t('timeAgoHours').replaceAll('{hours}', hours.toString());
  String timeAgoMinutes(int minutes) => _t('timeAgoMinutes').replaceAll('{minutes}', minutes.toString());
  String get timeAgoJustNow => _t('timeAgoJustNow');
  String get postShareError => _t('postShareError');
  String get postReactionError => _t('postReactionError');
  String get postReactionDisplayError => _t('postReactionDisplayError');
  String get postNoReactions => _t('postNoReactions');
  String get postAllReactions => _t('postAllReactions');
  // Comments
  String get commentEdit => _t('commentEdit');
  String get commentDelete => _t('commentDelete');
  String get commentDeleteConfirm => _t('commentDeleteConfirm');
  String get commentUpdatedSuccess => _t('commentUpdatedSuccess');
  String get commentUpdateError => _t('commentUpdateError');
  String get commentEdited => _t('commentEdited');
  // Create post
  String get createPostEditTitle => _t('createPostEditTitle');
  String get createPostContentRequired => _t('createPostContentRequired');
  String get createPostAlbumFeature => _t('createPostAlbumFeature');
  String get createPostUploadingImages => _t('createPostUploadingImages');
  String get createPostUploadingVideo => _t('createPostUploadingVideo');
  String get createPostProcessing => _t('createPostProcessing');
  String createPostUploadProgress(int percent) => _t('createPostUploadProgress').replaceAll('{percent}', percent.toString());
  // AI Assistant
  String get aiAssistantGetSuggestions => _t('aiAssistantGetSuggestions');
  String get aiAssistantLoading => _t('aiAssistantLoading');
  String get aiAssistantTitle => _t('aiAssistantTitle');
  String get aiAssistantCaption => _t('aiAssistantCaption');
  String get aiAssistantHashtags => _t('aiAssistantHashtags');
  String get aiAssistantTranslation => _t('aiAssistantTranslation');
  String get aiAssistantSentiment => _t('aiAssistantSentiment');
  String get aiAssistantCaptionApplied => _t('aiAssistantCaptionApplied');
  String get aiAssistantHashtagsApplied => _t('aiAssistantHashtagsApplied');
  String get aiAssistantTranslationApplied => _t('aiAssistantTranslationApplied');
  String get aiAssistantEmptyContent => _t('aiAssistantEmptyContent');
  String get aiAssistantError => _t('aiAssistantError');
  String get aiAssistantLoadError => _t('aiAssistantLoadError');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.map((l) => l.languageCode).contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
