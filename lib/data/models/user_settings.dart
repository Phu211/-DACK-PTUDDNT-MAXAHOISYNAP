import 'privacy_model.dart';

/// User-level settings for privacy, story, messaging, and discovery.
class UserSettings {
  final PrivacyType defaultPostVisibility;
  final PrivacyType defaultStoryVisibility;
  final bool allowStoryShare;
  final bool allowStoryReply;
  final bool storyArchiveEnabled;
  final List<String> storyHiddenUsers;
  final List<String> storyCloseFriends;
  final List<String> storyViewersWhitelist; // cho phép xem khi dùng chế độ tùy chỉnh

  // Feed / post controls
  final String defaultCommentPermission; // everyone/friends/friends_of_friends/custom

  // Discovery & search
  final bool searchByEmail;
  final bool searchByPhone;
  final bool searchEngineIndexable;

  // Messaging
  final String messageWhoCanMessage; // e.g. everyone/friends/friends_of_friends/custom
  final bool messageRequestsEnabled; // cho tin nhắn người lạ vào thư mục phụ

  // Notifications (per category)
  final Map<String, bool> notificationPrefs; // key: category, value: enabled
  final Map<String, bool> notificationEmailPrefs; // email theo category
  final Map<String, bool> notificationSmsPrefs; // sms theo category

  // Location
  final bool locationEnabled;
  final bool locationHistoryEnabled;

  // Data & account lifecycle
  final bool dataDownloadRequested;
  final bool deleteRequested;

  // Blocking lists (lightweight; full block collection may exist elsewhere)
  final List<String> blockedUsers;

  const UserSettings({
    this.defaultPostVisibility = PrivacyType.friends,
    this.defaultStoryVisibility = PrivacyType.friends,
    this.allowStoryShare = true,
    this.allowStoryReply = true,
    this.storyArchiveEnabled = true,
    this.storyHiddenUsers = const [],
    this.storyCloseFriends = const [],
    this.storyViewersWhitelist = const [],
    this.defaultCommentPermission = 'friends',
    this.searchByEmail = true,
    this.searchByPhone = true,
    this.searchEngineIndexable = true,
    this.messageWhoCanMessage = 'friends',
    this.messageRequestsEnabled = true,
    this.notificationPrefs = const {},
    this.notificationEmailPrefs = const {},
    this.notificationSmsPrefs = const {},
    this.locationEnabled = false,
    this.locationHistoryEnabled = false,
    this.dataDownloadRequested = false,
    this.deleteRequested = false,
    this.blockedUsers = const [],
  });

  UserSettings copyWith({
    PrivacyType? defaultPostVisibility,
    PrivacyType? defaultStoryVisibility,
    bool? allowStoryShare,
    bool? allowStoryReply,
    bool? storyArchiveEnabled,
    List<String>? storyHiddenUsers,
    List<String>? storyCloseFriends,
    List<String>? storyViewersWhitelist,
    String? defaultCommentPermission,
    bool? searchByEmail,
    bool? searchByPhone,
    bool? searchEngineIndexable,
    String? messageWhoCanMessage,
    bool? messageRequestsEnabled,
    Map<String, bool>? notificationPrefs,
    Map<String, bool>? notificationEmailPrefs,
    Map<String, bool>? notificationSmsPrefs,
    bool? locationEnabled,
    bool? locationHistoryEnabled,
    bool? dataDownloadRequested,
    bool? deleteRequested,
    List<String>? blockedUsers,
  }) {
    return UserSettings(
      defaultPostVisibility:
          defaultPostVisibility ?? this.defaultPostVisibility,
      defaultStoryVisibility:
          defaultStoryVisibility ?? this.defaultStoryVisibility,
      allowStoryShare: allowStoryShare ?? this.allowStoryShare,
      allowStoryReply: allowStoryReply ?? this.allowStoryReply,
      storyArchiveEnabled: storyArchiveEnabled ?? this.storyArchiveEnabled,
      storyHiddenUsers: storyHiddenUsers ?? this.storyHiddenUsers,
      storyCloseFriends: storyCloseFriends ?? this.storyCloseFriends,
      storyViewersWhitelist:
          storyViewersWhitelist ?? this.storyViewersWhitelist,
      defaultCommentPermission:
          defaultCommentPermission ?? this.defaultCommentPermission,
      searchByEmail: searchByEmail ?? this.searchByEmail,
      searchByPhone: searchByPhone ?? this.searchByPhone,
      searchEngineIndexable:
          searchEngineIndexable ?? this.searchEngineIndexable,
      messageWhoCanMessage:
          messageWhoCanMessage ?? this.messageWhoCanMessage,
      messageRequestsEnabled:
          messageRequestsEnabled ?? this.messageRequestsEnabled,
      notificationPrefs: notificationPrefs ?? this.notificationPrefs,
      notificationEmailPrefs:
          notificationEmailPrefs ?? this.notificationEmailPrefs,
      notificationSmsPrefs: notificationSmsPrefs ?? this.notificationSmsPrefs,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      locationHistoryEnabled:
          locationHistoryEnabled ?? this.locationHistoryEnabled,
      dataDownloadRequested:
          dataDownloadRequested ?? this.dataDownloadRequested,
      deleteRequested: deleteRequested ?? this.deleteRequested,
      blockedUsers: blockedUsers ?? this.blockedUsers,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'defaultPostVisibility': defaultPostVisibility.toValue(),
      'defaultStoryVisibility': defaultStoryVisibility.toValue(),
      'allowStoryShare': allowStoryShare,
      'allowStoryReply': allowStoryReply,
      'storyArchiveEnabled': storyArchiveEnabled,
      'storyHiddenUsers': storyHiddenUsers,
      'storyCloseFriends': storyCloseFriends,
      'storyViewersWhitelist': storyViewersWhitelist,
      'defaultCommentPermission': defaultCommentPermission,
      'searchByEmail': searchByEmail,
      'searchByPhone': searchByPhone,
      'searchEngineIndexable': searchEngineIndexable,
      'messageWhoCanMessage': messageWhoCanMessage,
      'messageRequestsEnabled': messageRequestsEnabled,
      'notificationPrefs': notificationPrefs,
      'notificationEmailPrefs': notificationEmailPrefs,
      'notificationSmsPrefs': notificationSmsPrefs,
      'locationEnabled': locationEnabled,
      'locationHistoryEnabled': locationHistoryEnabled,
      'dataDownloadRequested': dataDownloadRequested,
      'deleteRequested': deleteRequested,
      'blockedUsers': blockedUsers,
    };
  }

  factory UserSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserSettings();

    return UserSettings(
      defaultPostVisibility: PrivacyTypeExtension.fromString(
              map['defaultPostVisibility'] ?? 'friends') ??
          PrivacyType.friends,
      defaultStoryVisibility: PrivacyTypeExtension.fromString(
              map['defaultStoryVisibility'] ?? 'friends') ??
          PrivacyType.friends,
      allowStoryShare: map['allowStoryShare'] ?? true,
      allowStoryReply: map['allowStoryReply'] ?? true,
      storyArchiveEnabled: map['storyArchiveEnabled'] ?? true,
      storyHiddenUsers: (map['storyHiddenUsers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      storyCloseFriends: (map['storyCloseFriends'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      storyViewersWhitelist: (map['storyViewersWhitelist'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      defaultCommentPermission:
          map['defaultCommentPermission'] ?? 'friends',
      searchByEmail: map['searchByEmail'] ?? true,
      searchByPhone: map['searchByPhone'] ?? true,
      searchEngineIndexable: map['searchEngineIndexable'] ?? true,
      messageWhoCanMessage: map['messageWhoCanMessage'] ?? 'friends',
      messageRequestsEnabled: map['messageRequestsEnabled'] ?? true,
      notificationPrefs:
          Map<String, bool>.from(map['notificationPrefs'] ?? {}),
      notificationEmailPrefs:
          Map<String, bool>.from(map['notificationEmailPrefs'] ?? {}),
      notificationSmsPrefs:
          Map<String, bool>.from(map['notificationSmsPrefs'] ?? {}),
      locationEnabled: map['locationEnabled'] ?? false,
      locationHistoryEnabled: map['locationHistoryEnabled'] ?? false,
      dataDownloadRequested: map['dataDownloadRequested'] ?? false,
      deleteRequested: map['deleteRequested'] ?? false,
      blockedUsers:
          (map['blockedUsers'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
    );
  }
}


