class AppConstants {
  // App Info
  static const String appName = 'Synap';
  static const String appVersion = '1.0.0';

  /// Backend base URL (Render server) for Agora token + push gateway.
  ///
  /// Deploy `agora-backend` lên Render và thay URL này theo service của bạn.
  /// TODO: Thay YOUR_BACKEND_URL bằng URL backend thực tế của bạn
  static const String backendBaseUrl = 'YOUR_BACKEND_URL';

  /// Google Maps API Key (Tùy chọn - không bắt buộc)
  /// Hiện tại app đang dùng OpenStreetMap (miễn phí, không giới hạn)
  /// Nếu muốn dùng Google Maps Static API:
  /// - Lấy tại: https://console.cloud.google.com/google/maps-apis/credentials
  /// - Enable "Maps Static API" trong Google Cloud Console
  /// - Miễn phí: 28,000 requests/tháng, sau đó $2/1000 requests
  /// - Thay YOUR_GOOGLE_MAPS_API_KEY bằng API key thực tế
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  /// Mapbox Access Token (Tùy chọn - không bắt buộc)
  /// Nếu muốn dùng Mapbox Static Images:
  /// - Đăng ký tại: https://www.mapbox.com/
  /// - Miễn phí: 50,000 requests/tháng
  /// - Thay YOUR_MAPBOX_ACCESS_TOKEN bằng access token thực tế
  static const String mapboxAccessToken = 'YOUR_MAPBOX_ACCESS_TOKEN';

  /// AI API Configuration - Chọn một trong các API miễn phí sau:
  /// 
  /// 1. Groq (KHUYẾN NGHỊ - Miễn phí, nhanh):
  ///    - Đăng ký: https://console.groq.com
  ///    - Lấy API key: https://console.groq.com/keys
  ///    - Models: llama-3.1-8b-instant, mixtral-8x7b-32768
  /// 
  /// 2. OpenRouter (Nhiều models miễn phí):
  ///    - Đăng ký: https://openrouter.ai
  ///    - Lấy API key: https://openrouter.ai/keys
  ///    - Có hơn 15 models miễn phí
  /// 
  /// 3. Google Gemini (Free tier tốt):
  ///    - Đăng ký: https://ai.google.dev
  ///    - Lấy API key: https://aistudio.google.com/app/apikey
  ///    - Models: gemini-pro, gemini-1.5-flash
  /// 
  /// 4. OpenAI (Có phí, nhưng chất lượng cao):
  ///    - Đăng ký: https://platform.openai.com/api-keys
  ///    - Models: gpt-3.5-turbo, gpt-4
   
  /// Chọn provider: 'groq', 'openrouter', 'gemini', hoặc 'openai'
  static const String aiProvider = 'groq'; // Mặc định dùng Groq (miễn phí)
  
  /// API Key cho AI Content Assistant
  /// Thay YOUR_API_KEY bằng key từ provider bạn chọn
  /// TODO: Thay YOUR_AI_API_KEY bằng API key thực tế từ provider bạn chọn
  static const String aiApiKey = 'YOUR_AI_API_KEY';

  // Collections
  static const String usersCollection = 'users';
  static const String postsCollection = 'posts';
  static const String commentsCollection = 'comments';
  static const String likesCollection = 'likes';
  static const String followsCollection = 'follows';
  static const String messagesCollection = 'messages';
  static const String conversationsCollection = 'conversations';
  static const String notificationsCollection = 'notifications';
  static const String storiesCollection = 'stories';
  static const String storyViewsCollection = 'storyViews';
  static const String storyReactionsCollection = 'storyReactions';
  static const String groupsCollection = 'groups';
  static const String groupCallsCollection = 'groupCalls';
  static const String savedPostsCollection = 'savedPosts';
  static const String savedStoriesCollection = 'savedStories';
  static const String hiddenPostsCollection = 'hiddenPosts';
  static const String reportsCollection = 'reports';
  static const String blocksCollection = 'blocks';
  static const String friendRequestsCollection = 'friendRequests';
  static const String friendsCollection = 'friends';
  static const String videosCollection = 'videos';
  static const String pagesCollection = 'pages';
  static const String productsCollection = 'products';
  static const String userInteractionsCollection = 'userInteractions';
  static const String feedPreferencesCollection = 'feedPreferences';
  static const String postNotificationsCollection = 'postNotifications';
  static const String userSettingsCollection = 'userSettings';
  static const String messageRequestsCollection = 'messageRequests';
  static const String viewedPostsCollection = 'viewedPosts';
  static const String highlightsCollection = 'highlights';
  static const String activityLogsCollection = 'activityLogs';
  static const String profileViewsCollection = 'profileViews';
  static const String taggedPostsCollection = 'taggedPosts';

  // Storage Paths
  static const String avatarsPath = 'avatars';
  static const String postsPath = 'posts';
  static const String coversPath = 'covers';
}
