# 📱 BÁO CÁO CHỨC NĂNG ỨNG DỤNG SYNAP

## 📋 MỤC LỤC
1. [Tổng quan](#tổng-quan)
2. [Xác thực & Bảo mật](#xác-thực--bảo-mật)
3. [Trang chủ & Feed](#trang-chủ--feed)
4. [Bài viết (Posts)](#bài-viết-posts)
5. [Stories](#stories)
6. [Tin nhắn & Chat](#tin-nhắn--chat)
7. [Cuộc gọi (Calls)](#cuộc-gọi-calls)
8. [Bạn bè & Mạng xã hội](#bạn-bè--mạng-xã-hội)
9. [Nhóm (Groups)](#nhóm-groups)
10. [Hồ sơ (Profile)](#hồ-sơ-profile)
11. [Tìm kiếm](#tìm-kiếm)
12. [Thông báo](#thông-báo)
13. [Cài đặt](#cài-đặt)
14. [Tính năng AI](#tính-năng-ai)
15. [Tính năng khác](#tính-năng-khác)

---

## 📊 TỔNG QUAN

**Synap** là một ứng dụng mạng xã hội đầy đủ tính năng được xây dựng bằng Flutter, tích hợp Firebase và các công nghệ hiện đại. Ứng dụng hỗ trợ đa nền tảng (iOS, Android, Web) với các tính năng tương tác xã hội, giao tiếp, và giải trí.

### Công nghệ sử dụng:
- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Firebase Auth, Firestore, Storage)
- **Real-time**: Firestore Streams, Agora RTC
- **AI**: Groq/Gemini/OpenAI API
- **Push Notifications**: Firebase Cloud Messaging
- **Email**: SendGrid

---

## 🔐 XÁC THỰC & BẢO MẬT

### 1. Đăng ký tài khoản
**Cách sử dụng:**
- Người dùng mở ứng dụng lần đầu, chọn "Đăng ký"
- Nhập đầy đủ thông tin: Email, mật khẩu (tối thiểu 6 ký tự), tên đầy đủ
- Nhấn nút "Đăng ký"
- Hệ thống kiểm tra email đã tồn tại chưa, mật khẩu có đủ mạnh không
- Nếu hợp lệ, tài khoản được tạo và hiển thị thông báo thành công
- Người dùng nhận email xác thực và email chào mừng tự động
- Sau khi đăng ký, có thể đăng nhập ngay

**Cách hoạt động:**
- Người dùng nhập email, mật khẩu, tên đầy đủ
- Hệ thống tạo tài khoản Firebase Auth
- Tự động gửi email xác thực
- Gửi email chào mừng tự động qua SendGrid
- Lưu thông tin user vào Firestore
- Tạo profile mặc định với avatar placeholder

**Màn hình**: **Màn hình Đăng ký** (`RegisterScreen`)

### 2. Đăng nhập
**Cách sử dụng:**
- Người dùng mở ứng dụng, nhập email và mật khẩu
- Nhấn nút "Đăng nhập"
- Nếu đã bật đăng nhập bằng sinh trắc học (Face ID/Touch ID/Fingerprint), hệ thống sẽ hiển thị popup xác thực sinh trắc học thay vì yêu cầu nhập mật khẩu
- Nếu đã bật 2FA, sau khi nhập mật khẩu đúng, hệ thống yêu cầu nhập mã OTP từ ứng dụng xác thực (Google Authenticator)
- Sau khi xác thực thành công, người dùng được chuyển vào màn hình Trang chủ
- Hệ thống tự động lưu session, không cần đăng nhập lại lần sau (nếu chưa đăng xuất)

**Cách hoạt động:**
- Xác thực qua Firebase Auth
- Kiểm tra email đã xác thực chưa
- Lưu session vào Secure Storage
- Cập nhật trạng thái online/offline
- Ghi nhận lịch sử đăng nhập

**Màn hình**: **Màn hình Đăng nhập** (`LoginScreen`)

### 3. Xác thực 2 yếu tố (2FA)
**Cách sử dụng:**
- Vào **Cài đặt** → **Bảo mật Tài khoản** → **Xác thực 2 yếu tố**
- Nhấn nút "Bật 2FA"
- Hệ thống hiển thị mã QR code trên màn hình
- Người dùng mở ứng dụng Google Authenticator (hoặc ứng dụng xác thực khác) và quét QR code
- Sau khi quét xong, nhập mã OTP 6 số từ ứng dụng xác thực để xác nhận
- Hệ thống tạo và hiển thị danh sách recovery codes (mã khôi phục dự phòng)
- Người dùng nên lưu lại các mã này ở nơi an toàn
- Từ lần đăng nhập sau, mỗi khi đăng nhập sẽ yêu cầu nhập mã OTP sau khi nhập mật khẩu

**Cách hoạt động:**
- Tạo mã QR code cho ứng dụng xác thực (Google Authenticator)
- Lưu secret key vào Firestore (mã hóa)
- Yêu cầu nhập mã OTP khi đăng nhập
- Tạo recovery codes dự phòng
- Hỗ trợ backup codes

**Màn hình**: **Màn hình Bật 2FA** (`TwoFactorAuthScreen`), **Màn hình Xác thực 2FA** (`TwoFactorVerifyScreen`)

### 4. Xác thực sinh trắc học
**Cách sử dụng:**
- Vào **Cài đặt** → **Bảo mật Tài khoản** → **Xác thực Sinh trắc học**
- Bật tùy chọn "Đăng nhập bằng sinh trắc học"
- Hệ thống yêu cầu xác thực sinh trắc học ngay lập tức để kích hoạt tính năng
- Sau khi bật, mỗi lần mở app hoặc đăng nhập, thay vì nhập mật khẩu, hệ thống sẽ hiển thị popup yêu cầu xác thực bằng Face ID/Touch ID/Fingerprint
- Người dùng chỉ cần quét vân tay hoặc nhận diện khuôn mặt để đăng nhập nhanh chóng
- Có thể tắt tính năng này bất cứ lúc nào trong cài đặt

**Cách hoạt động:**
- Sử dụng `local_auth` package
- Hỗ trợ Face ID, Touch ID, Fingerprint
- Lưu trạng thái bật/tắt trong Settings
- Tự động mở khóa khi app khởi động (nếu bật)

**Màn hình**: **Màn hình Xác thực Sinh trắc học** (`BiometricAuthScreen`)

### 5. Quên mật khẩu
**Cách sử dụng:**
- Ở màn hình đăng nhập, nhấn vào "Quên mật khẩu?"
- Nhập email đã đăng ký tài khoản
- Nhấn nút "Gửi link đặt lại mật khẩu"
- Hệ thống gửi email chứa link reset mật khẩu
- Người dùng mở email và click vào link (link có hiệu lực trong 1 giờ)
- Mở link trong trình duyệt hoặc app, nhập mật khẩu mới (2 lần để xác nhận)
- Nhấn "Đặt lại mật khẩu"
- Sau khi đặt lại thành công, có thể đăng nhập bằng mật khẩu mới

**Cách hoạt động:**
- Nhập email → Gửi link reset qua Firebase
- Link reset có thời hạn (1 giờ)
- Cho phép đặt mật khẩu mới

**Màn hình**: **Màn hình Quên mật khẩu** (`ForgotPasswordScreen`)

### 6. Bảo mật tài khoản
**Các tính năng:**
- **Lịch sử đăng nhập**: Xem các thiết bị đã đăng nhập
- **Khóa tài khoản tự động**: Sau nhiều lần đăng nhập sai
- **IP Whitelisting**: Chỉ cho phép đăng nhập từ IP đã đăng ký
- **Câu hỏi bảo mật**: Đặt câu hỏi để khôi phục tài khoản
- **Mã khôi phục**: Tạo mã dự phòng để khôi phục tài khoản
- **Hoạt động đáng ngờ**: Phát hiện và cảnh báo hoạt động bất thường
- **Mã hóa dữ liệu**: Mã hóa thông tin nhạy cảm trước khi lưu

**Màn hình**: **Màn hình Bảo mật Tài khoản** (`AccountSecurityScreen`), **Màn hình Lịch sử Đăng nhập** (`LoginHistoryScreen`), **Màn hình Câu hỏi Bảo mật** (`SecurityQuestionsScreen`), **Màn hình Mã Khôi phục** (`RecoveryCodesScreen`), **Màn hình IP Whitelisting** (`IPWhitelistingScreen`)

---

## 🏠 TRANG CHỦ & FEED

### 1. Trang chủ (Home)
**Cách sử dụng:**
- Sau khi đăng nhập, người dùng được chuyển đến màn hình Trang chủ
- Ở đầu trang, hiển thị Stories của bạn bè (dạng vòng tròn với avatar)
- Kéo xuống để xem feed bài viết từ bạn bè và người đã follow
- Mỗi bài viết hiển thị: avatar, tên người đăng, thời gian, nội dung, ảnh/video
- Nếu bài viết từ nhóm, có badge màu xanh hiển thị tên nhóm ở trên đầu
- Kéo xuống để làm mới (pull-to-refresh) và tải bài viết mới
- Click vào bài viết để xem chi tiết và bình luận
- Scroll tự động đánh dấu bài viết đã xem

**Cách hoạt động:**
- Hiển thị feed bài viết từ bạn bè và người dùng đã follow
- Lọc theo quyền riêng tư (công khai, bạn bè, chỉ mình tôi)
- Hiển thị Stories section ở đầu feed
- Tự động đánh dấu bài viết đã xem
- Hỗ trợ pull-to-refresh
- Responsive design (mobile/desktop)

**Màn hình**: **Màn hình Trang chủ** (`HomeScreen`)

### 2. Bảng Feed (Feed Preferences)
**Cách hoạt động:**
- 3 tab: **Tất cả**, **Đang theo dõi**, **Đề xuất**
- Tab "Tất cả": Hiển thị tất cả bài viết công khai
- Tab "Đang theo dõi": Chỉ hiển thị bài viết từ người đã follow
- Tab "Đề xuất": Bài viết được đề xuất dựa trên thuật toán
- Có thể ẩn bài viết từ người dùng cụ thể
- Có thể bỏ theo dõi người dùng

**Màn hình**: **Màn hình Bảng Feed** (`FeedTabsScreen`), **Màn hình Tùy chọn Feed** (`FeedPreferencesScreen`)

### 3. Stories
**Cách hoạt động:**
- Hiển thị stories của bạn bè ở đầu feed
- Stories tự động xóa sau 24 giờ
- Xem stories dạng fullscreen với swipe navigation
- Tạo stories với ảnh/video
- Tạo Highlights (lưu stories vào bộ sưu tập)
- Chỉnh sửa privacy cho stories

**Màn hình**: **Widget Stories** (`StoriesSection`), **Màn hình Tạo Story** (`CreateStoryScreen`), **Màn hình Xem Story** (`StoryViewerScreen`), **Màn hình Tạo Highlight** (`CreateHighlightScreen`), **Màn hình Chỉnh sửa Highlight** (`EditHighlightScreen`)

---

## 📝 BÀI VIẾT (POSTS)

### 1. Tạo bài viết
**Cách sử dụng:**
- Nhấn nút "+" ở bottom navigation bar hoặc nút "Tạo bài viết" trong menu
- Nhập nội dung bài viết vào ô text
- Khi gõ, sau 1.5 giây, hệ thống tự động hiển thị **AI Content Quality Score** (điểm đánh giá chất lượng 0-100) với icon cảm xúc và gợi ý cải thiện
- Sau khi nhập text hoặc chọn ảnh, widget **AI Content Assistant** tự động hiển thị với các gợi ý:
  - **Caption cải thiện**: Nhấn "Dùng" để thay thế nội dung hiện tại
  - **Hashtags gợi ý**: Nhấn "Dùng" để thêm hashtags vào cuối bài viết
  - Có thể chuyển sang chế độ **Chat** để yêu cầu AI tùy chỉnh theo ý muốn
- Nhấn icon ảnh để thêm ảnh/video từ thư viện hoặc chụp mới (tối đa 10 files)
- Nhấn icon cảm xúc để chọn cảm xúc hiện tại (😊 Vui vẻ, ❤️ Yêu thích, 😮 Ngạc nhiên, 😢 Buồn, 😡 Tức giận)
- Nhấn icon vị trí để thêm vị trí hiện tại hoặc chọn vị trí khác
- Nhấn icon tag để tag bạn bè vào bài viết
- Chọn quyền riêng tư: 🌐 Công khai, 👥 Bạn bè, hoặc 🔒 Chỉ mình tôi
- Nhấn nút "Đăng"
- Hệ thống kiểm tra nội dung bằng **AI Content Moderation**:
  - Nếu phát hiện nội dung toxic/spam (score ≥ 0.7), hiển thị cảnh báo đỏ và không cho phép đăng
  - Nếu có cảnh báo nhẹ (score ≥ 0.5), hiển thị dialog xác nhận, người dùng chọn "Tiếp tục" hoặc "Hủy"
- Sau khi kiểm tra xong, bài viết được upload và hiển thị trên feed

**Cách hoạt động:**
- Nhập nội dung text
- Thêm ảnh/video (tối đa 10 files)
- Chọn quyền riêng tư (Công khai, Bạn bè, Chỉ mình tôi)
- Thêm cảm xúc (feeling)
- Thêm vị trí (location)
- Tag bạn bè
- **AI Content Quality Score**: Đánh giá chất lượng bài viết (0-100 điểm)
- **AI Content Moderation**: Kiểm duyệt nội dung tự động (chặn toxic/spam)
- Upload lên Firebase Storage và Firestore
- Tạo notification cho bạn bè

**Màn hình**: **Màn hình Tạo bài viết** (`CreatePostScreen`)

### 2. Hiển thị bài viết
**Cách hoạt động:**
- Hiển thị avatar, tên, thời gian đăng
- Hiển thị nội dung, ảnh/video
- Hiển thị cảm xúc, vị trí, tagged users
- Hiển thị số lượt like, comment, share
- **Badge nhóm**: Nếu bài viết từ nhóm, hiển thị tên nhóm ở trên đầu
- Hỗ trợ xem fullscreen ảnh/video
- Tự động phát video (nếu bật autoplay)

**Widget**: **Widget Hiển thị Bài viết** (`PostCard`)

### 3. Chi tiết bài viết
**Cách sử dụng:**
- Click vào bất kỳ bài viết nào trên feed để mở màn hình chi tiết
- Xem toàn bộ nội dung, ảnh/video (có thể xem fullscreen)
- Ở góc trên phải, có icon 📄 để xem **AI Comment Summarizer** (tóm tắt tất cả comments)
- Scroll xuống để xem tất cả comments và replies
- Ở phần comment, nếu comment trực tiếp vào bài viết (không phải reply), hiển thị widget **AI Smart Reply** với 3-5 gợi ý trả lời ngắn gọn
- Click vào một gợi ý → Text tự động điền vào ô comment
- Nhấn và giữ nút Like để mở menu cảm xúc (6 loại: 👍 Like, ❤️ Love, 😂 Haha, 😮 Wow, 😢 Sad, 😡 Angry)
- Gõ comment và nhấn "Gửi" (nút bàn phím là nút xuống dòng)
- Hệ thống kiểm tra comment bằng AI Content Moderation trước khi gửi
- Nhấn icon chia sẻ để chia sẻ bài viết lên feed hoặc gửi qua tin nhắn
- Nhấn icon bookmark để lưu bài viết
- Nhấn icon 3 chấm để báo cáo hoặc ẩn bài viết

**Cách hoạt động:**
- Xem toàn bộ nội dung bài viết
- Xem tất cả comments và replies
- **AI Smart Reply**: Gợi ý trả lời thông minh cho comments
- **AI Comment Summarizer**: Tóm tắt tất cả comments thành key points
- Bày tỏ cảm xúc (Like, Love, Haha, Wow, Sad, Angry)
- Comment và reply
- Chia sẻ bài viết
- Lưu bài viết
- Báo cáo/Ẩn bài viết

**Màn hình**: **Màn hình Chi tiết Bài viết** (`PostDetailScreen`)

### 4. Tương tác với bài viết
**Các hành động:**
- **Like/Reaction**: 6 loại cảm xúc (Like, Love, Haha, Wow, Sad, Angry)
- **Comment**: Viết bình luận, reply comment
- **Share**: Chia sẻ bài viết lên feed hoặc gửi qua tin nhắn
- **Save**: Lưu bài viết vào danh sách đã lưu
- **Report**: Báo cáo nội dung không phù hợp
- **Hide**: Ẩn bài viết khỏi feed

**Cách hoạt động:**
- Mỗi hành động được lưu vào Firestore
- Tạo notification cho người đăng bài
- Cập nhật real-time số lượt tương tác

### 5. Bài viết đã lưu
**Cách hoạt động:**
- Lưu tất cả bài viết đã bookmark
- Tổ chức theo thư mục (nếu có)
- Xem lại bài viết đã lưu

**Màn hình**: **Màn hình Bài viết Đã lưu** (`SavedPostsScreen`)

---

## 📸 STORIES

### 1. Tạo Story
**Cách sử dụng:**
- Ở đầu trang chủ, nhấn vào vòng tròn "+" ở Stories section (hoặc vòng tròn avatar của mình)
- Chọn ảnh/video từ thư viện hoặc chụp mới bằng camera
- Có thể thêm text, sticker, vẽ lên story bằng các công cụ chỉnh sửa
- Chọn quyền riêng tư: **Công khai** (mọi người), **Bạn bè** (chỉ bạn bè), hoặc **Tùy chỉnh** (chọn người cụ thể)
- Nhấn nút "Đăng" để đăng story
- Story sẽ hiển thị trong Stories section và tự động xóa sau 24 giờ

**Cách hoạt động:**
- Chọn ảnh/video từ thư viện hoặc chụp mới
- Thêm text, sticker, vẽ lên story
- Chọn quyền riêng tư (Công khai, Bạn bè, Tùy chỉnh)
- Story tự động xóa sau 24 giờ
- Upload lên Firebase Storage

**Màn hình**: **Màn hình Tạo Story** (`CreateStoryScreen`)

### 2. Xem Stories
**Cách sử dụng:**
- Ở đầu trang chủ, nhấn vào vòng tròn story của bạn bè
- Màn hình fullscreen hiển thị story
- **Swipe trái/phải** để chuyển giữa các story của cùng một người
- **Swipe lên/xuống** để chuyển giữa story của người khác
- **Tap màn hình** để tạm dừng/tiếp tục story
- Story tự động chuyển sang story tiếp theo sau 5 giây
- Ở góc dưới có thể gửi phản ứng (emoji) hoặc tin nhắn
- Nhấn icon "Xem ai đã xem" để xem danh sách người đã xem story
- Nhấn nút X để đóng và quay về trang chủ

**Cách hoạt động:**
- Swipe để chuyển giữa các stories
- Tap để tạm dừng/tiếp tục
- Stories tự động chuyển sau 5 giây
- Hiển thị danh sách người đã xem
- Phản ứng với story (emoji)

**Màn hình**: **Màn hình Xem Story** (`StoryViewerScreen`)

### 3. Highlights
**Cách hoạt động:**
- Lưu stories vào bộ sưu tập (Highlights)
- Tạo nhiều highlights với tên và ảnh bìa
- Highlights không tự động xóa
- Hiển thị trên profile

**Màn hình**: **Màn hình Tạo Highlight** (`CreateHighlightScreen`), **Màn hình Chỉnh sửa Highlight** (`EditHighlightScreen`)

---

## 💬 TIN NHẮN & CHAT

### 1. Danh sách tin nhắn
**Cách sử dụng:**
- Nhấn icon tin nhắn ở bottom navigation bar
- Hiển thị danh sách tất cả cuộc trò chuyện (1-1 và nhóm chat)
- Cuộc trò chuyện có tin nhắn mới nhất được sắp xếp lên đầu
- Mỗi cuộc trò chuyện hiển thị: avatar, tên, tin nhắn cuối cùng, thời gian, badge số tin nhắn chưa đọc (màu đỏ)
- Kéo xuống để làm mới danh sách
- Nhấn vào một cuộc trò chuyện để mở chat
- Nhấn icon "+" hoặc "Tạo tin nhắn mới" để tạo cuộc trò chuyện mới
- Có thanh tìm kiếm ở trên để tìm cuộc trò chuyện theo tên

**Cách hoạt động:**
- Hiển thị danh sách cuộc trò chuyện
- Sắp xếp theo tin nhắn mới nhất
- Hiển thị tin nhắn chưa đọc (badge)
- Tìm kiếm cuộc trò chuyện
- Tạo cuộc trò chuyện mới

**Màn hình**: **Màn hình Danh sách Tin nhắn** (`MessagesListScreen`)

### 2. Chat 1-1
**Cách sử dụng:**
- Từ danh sách tin nhắn, click vào một cuộc trò chuyện để mở chat
- Ở đầu màn hình hiển thị avatar, tên, trạng thái online/offline của người nhận
- Ở dưới cùng là ô nhập tin nhắn với các icon:
  - Icon ảnh: Chọn ảnh/video từ thư viện hoặc chụp mới
  - Icon microphone: Giữ để ghi âm tin nhắn thoại, thả ra để gửi
  - Icon vị trí: Chia sẻ vị trí hiện tại hoặc live location
  - Icon gửi: Gửi tin nhắn text
- Gõ tin nhắn và nhấn "Gửi" hoặc Enter
- Tin nhắn hiển thị real-time, có indicator "đang gõ..." khi đối phương đang nhập
- Nhấn và giữ một tin nhắn để xem menu: Xóa (cho mình tôi hoặc cho cả hai bên), Sao chép, Chuyển tiếp
- Tin nhắn đã đọc có dấu tick đôi màu xanh
- Scroll lên để xem tin nhắn cũ hơn (tự động load thêm)

**Cách hoạt động:**
- Gửi tin nhắn text
- Gửi ảnh/video
- Gửi tin nhắn thoại (voice message)
- Gửi vị trí (location sharing)
- Đánh dấu đã đọc
- Typing indicator
- Online/Offline status
- Xóa tin nhắn (cho cả hai bên hoặc chỉ mình tôi)
- Mã hóa tin nhắn end-to-end

**Màn hình**: **Màn hình Chat 1-1** (`ChatScreen`)

### 3. Nhóm chat
**Cách hoạt động:**
- Tạo nhóm chat với nhiều thành viên
- Thêm/xóa thành viên
- Đặt tên nhóm, ảnh đại diện
- Quản lý quyền (admin, member)
- Rời nhóm
- Xem thông tin nhóm

**Màn hình**: **Màn hình Nhóm Chat** (`GroupChatScreen`), **Màn hình Tạo Chat mới** (`NewChatScreen`), **Màn hình Thông tin Nhóm Chat** (`GroupChatInfoScreen`), **Màn hình Thêm Thành viên** (`AddMemberScreen`)

### 4. Chia sẻ vị trí
**Cách hoạt động:**
- Chia sẻ vị trí hiện tại
- Chia sẻ vị trí real-time (live location)
- Xem vị trí trên bản đồ
- Tự động dừng chia sẻ sau thời gian nhất định

**Màn hình**: **Màn hình Chia sẻ Vị trí** (`LiveLocationScreen`)

---

## 📞 CUỘC GỌI (CALLS)

### 1. Cuộc gọi 1-1
**Cách sử dụng:**
- **Gọi đi**: Từ màn hình chat hoặc profile người dùng, nhấn icon điện thoại (voice call) hoặc icon video (video call)
- Màn hình gọi hiển thị: avatar, tên người được gọi, trạng thái "Đang gọi..."
- Người nhận thấy màn hình gọi với nút "Trả lời" và "Từ chối"
- Nếu app ở background, người nhận nhận push notification, click vào để trả lời
- Khi kết nối thành công:
  - **Voice call**: Hiển thị avatar lớn, có nút bật/tắt microphone, loa ngoài, kết thúc
  - **Video call**: Hiển thị video của cả hai bên, có nút bật/tắt camera, microphone, chuyển camera trước/sau, kết thúc
- Nhấn nút đỏ để kết thúc cuộc gọi
- Sau khi kết thúc, hiển thị thời gian cuộc gọi và lưu vào lịch sử

**Cách hoạt động:**
- Sử dụng Agora RTC Engine
- Hỗ trợ voice call và video call
- Gọi từ danh sách bạn bè hoặc trong chat
- Hiển thị màn hình gọi với avatar, tên
- Bật/tắt camera, microphone
- Chuyển đổi camera trước/sau
- Kết thúc cuộc gọi
- Nhận cuộc gọi khi app ở background (push notification)

**Màn hình**: **Màn hình Cuộc gọi** (`CallScreen`), **Màn hình Cuộc gọi Agora** (`AgoraCallScreen`)

### 2. Cuộc gọi nhóm
**Cách hoạt động:**
- Tạo cuộc gọi nhóm từ group chat
- Hỗ trợ nhiều người tham gia
- Hiển thị grid view tất cả người tham gia
- Bật/tắt camera, microphone
- Chuyển đổi speaker/earpiece

**Màn hình**: **Màn hình Cuộc gọi Nhóm** (`GroupCallScreen`)

### 3. Quản lý cuộc gọi
**Cách hoạt động:**
- Tạo token Agora từ backend
- Quản lý trạng thái cuộc gọi (ringing, connected, ended)
- Lưu lịch sử cuộc gọi
- Push notification cho cuộc gọi đến

**Service**: `AgoraCallService`, `CallNotificationService`

---

## 👥 BẠN BÈ & MẠNG XÃ HỘI

### 1. Quản lý bạn bè
**Cách sử dụng:**
- Vào **Menu** → **Bạn bè** hoặc **Tìm bạn bè**
- Có 3 tab: **Tất cả** (danh sách bạn bè), **Lời mời** (lời mời đã nhận), **Gợi ý** (gợi ý kết bạn)
- **Gửi lời mời**: Từ profile người dùng hoặc danh sách gợi ý, nhấn nút "Kết bạn"
- **Chấp nhận/Từ chối**: Ở tab "Lời mời", xem danh sách lời mời đã nhận, nhấn "Chấp nhận" hoặc "Từ chối"
- **Xem bạn bè**: Tab "Tất cả" hiển thị danh sách tất cả bạn bè, có thể tìm kiếm
- **Hủy kết bạn**: Từ profile bạn bè, nhấn "Hủy kết bạn" trong menu 3 chấm
- **Chặn người dùng**: Từ profile, nhấn "Chặn" trong menu, người đó sẽ không thể xem profile và gửi tin nhắn

**Cách hoạt động:**
- Gửi lời mời kết bạn
- Chấp nhận/từ chối lời mời
- Xem danh sách bạn bè
- Xem danh sách lời mời đã gửi
- Hủy kết bạn
- Chặn người dùng

**Màn hình**: **Màn hình Bạn bè** (`FriendsScreen`), **Màn hình Tab Bạn bè** (`FriendsTabsScreen`), **Màn hình Lời mời Kết bạn** (`FriendRequestsScreen`), **Màn hình Danh sách Bạn bè** (`FriendsListScreen`)

### 2. Gợi ý bạn bè
**Cách sử dụng:**
- Vào **Menu** → **Bạn bè** → Tab **"Gợi ý"**
- Hệ thống hiển thị danh sách người dùng được đề xuất dựa trên bạn chung
- Mỗi gợi ý hiển thị: avatar, tên, số bạn chung (ví dụ: "5 bạn chung")
- Nhấn nút "Kết bạn" để gửi lời mời kết bạn ngay
- Có thể click vào profile để xem thông tin trước khi kết bạn
- Danh sách tự động cập nhật khi có gợi ý mới

**Cách hoạt động:**
- **Thuật toán đề xuất**: Dựa trên bạn chung (mutual friends)
- Hiển thị số bạn chung
- Gửi lời mời kết bạn trực tiếp từ danh sách gợi ý

**Màn hình**: **Màn hình Gợi ý Bạn bè** (`PeopleYouMayKnowScreen`)

### 3. Tìm bạn bè
**Cách hoạt động:**
- Tìm kiếm theo tên, email
- Xem profile người dùng
- Gửi lời mời kết bạn

**Màn hình**: **Màn hình Tìm kiếm** (`SearchScreen`) - tab Bạn bè

---

## 👥 NHÓM (GROUPS)

### 1. Tạo nhóm
**Cách sử dụng:**
- Vào **Menu** → **Nhóm** → Nhấn nút "Tạo nhóm"
- Nhập tên nhóm (bắt buộc) và mô tả (tùy chọn)
- Nhấn icon ảnh để chọn ảnh đại diện cho nhóm
- Chọn quyền riêng tư: **Công khai** (mọi người có thể tìm thấy và tham gia) hoặc **Riêng tư** (chỉ thành viên mới thấy)
- Nhấn "Thêm thành viên" để mời bạn bè vào nhóm ngay từ đầu
- Chọn bạn bè muốn thêm và nhấn "Xong"
- Nhấn nút "Tạo nhóm" để hoàn tất
- Lưu ý: Nhóm tạo từ Menu là nhóm đăng bài (post), khác với nhóm chat trong tin nhắn

**Cách hoạt động:**
- Đặt tên nhóm, mô tả
- Chọn ảnh đại diện
- Chọn quyền riêng tư (Công khai, Riêng tư)
- Thêm thành viên ban đầu
- Phân biệt nhóm đăng bài (post) và nhóm chat

**Màn hình**: **Màn hình Tạo Nhóm** (`CreateGroupScreen`)

### 2. Quản lý nhóm
**Cách hoạt động:**
- Xem danh sách nhóm đã tham gia
- Tìm kiếm nhóm
- Tham gia/rời nhóm
- Xem thông tin nhóm
- Chỉnh sửa thông tin nhóm (admin)
- Mời bạn bè vào nhóm
- Chia sẻ link nhóm

**Màn hình**: **Màn hình Nhóm** (`GroupsScreen`), **Màn hình Danh sách Nhóm** (`GroupsListScreen`), **Màn hình Chi tiết Nhóm** (`GroupDetailScreen`), **Màn hình Cài đặt Nhóm** (`GroupSettingsScreen`), **Màn hình Mời Bạn bè vào Nhóm** (`InviteFriendsToGroupScreen`)

### 3. Đăng bài trong nhóm
**Cách sử dụng:**
- Vào **Menu** → **Nhóm** → Chọn một nhóm đã tham gia
- Ở màn hình chi tiết nhóm, nhấn icon "+" (Add Post) ở AppBar (chỉ hiển thị với thành viên)
- Màn hình tạo bài viết tương tự như tạo bài viết thường
- Nhập nội dung, thêm ảnh/video, cảm xúc, vị trí, tag bạn bè
- Có **AI Content Assistant** để gợi ý caption và hashtags
- Có **AI Content Quality Score** và **AI Content Moderation** như bài viết thường
- **Lưu ý**: Bài viết trong nhóm luôn ở chế độ **Công khai**, không thể thay đổi
- Nhấn "Đăng" để đăng bài vào nhóm
- Bài viết sẽ hiển thị trong nhóm và trên trang chủ với badge màu xanh hiển thị tên nhóm ở trên đầu

**Cách hoạt động:**
- Chỉ thành viên mới đăng được
- Bài viết luôn ở chế độ công khai
- Hiển thị badge nhóm trên bài viết ở trang chủ
- Hỗ trợ tất cả tính năng như bài viết thường (reaction, comment, share)
- Tích hợp AI Content Quality Score và Moderation

**Màn hình**: **Màn hình Tạo Bài viết trong Nhóm** (`CreateGroupPostScreen`)

---

## 👤 HỒ SƠ (PROFILE)

### 1. Profile cá nhân
**Cách sử dụng:**
- Nhấn vào avatar ở bottom navigation bar (góc dưới bên phải) để xem profile cá nhân
- Ở đầu profile hiển thị: ảnh bìa, avatar, tên, bio, số bạn bè, số người follow
- Có các tab: **Bài viết**, **Ảnh**, **Đã lưu**
- Tab "Bài viết" hiển thị tất cả bài viết đã đăng (có thể lọc theo privacy)
- Tab "Ảnh" hiển thị tất cả ảnh đã đăng
- Tab "Đã lưu" hiển thị bài viết đã bookmark
- Ở đầu có Stories và Highlights (nếu có)
- Nhấn nút "Chỉnh sửa" để chỉnh sửa thông tin profile

**Cách hoạt động:**
- Xem thông tin cá nhân (tên, avatar, bio)
- Xem bài viết đã đăng
- Xem stories và highlights
- Xem bạn bè
- Xem ảnh đã được tag
- Chỉnh sửa profile

**Màn hình**: **Màn hình Hồ sơ Cá nhân** (`ProfileScreen`), **Màn hình Chỉnh sửa Hồ sơ** (`EditProfileScreen`)

### 2. Profile người khác
**Cách hoạt động:**
- Xem thông tin công khai
- Xem bài viết công khai
- Gửi lời mời kết bạn
- Follow/Unfollow
- Xem bạn chung
- Ghi nhận lượt xem profile

**Màn hình**: **Màn hình Hồ sơ Người khác** (`OtherUserProfileScreen`)

### 3. Quản lý profile
**Các tính năng:**
- **Chỉnh sửa thông tin**: Tên, bio, avatar, ảnh bìa
- **Xem lượt xem profile**: Danh sách người đã xem
- **Ảnh đã tag**: Xem và gỡ tag
- **Hoạt động**: Xem activity log
- **Người dùng đã chặn**: Quản lý danh sách chặn

**Màn hình**: **Màn hình Chỉnh sửa Hồ sơ** (`EditProfileScreen`), **Màn hình Lượt xem Profile** (`ProfileViewsListScreen`), **Màn hình Ảnh đã Tag** (`TaggedPostsScreen`), **Màn hình Nhật ký Hoạt động** (`ActivityLogScreen`), **Màn hình Người dùng Đã chặn** (`BlockedUsersScreen`)

---

## 🔍 TÌM KIẾM

### 1. Tìm kiếm tổng quát
**Cách sử dụng:**
- Nhấn icon tìm kiếm ở bottom navigation bar
- Gõ từ khóa vào thanh tìm kiếm
- Kết quả hiển thị real-time khi gõ (không cần nhấn Enter)
- Có các tab: **Tất cả**, **Người dùng**, **Bài viết**, **Nhóm**
- Tab "Tất cả" hiển thị kết quả từ tất cả các loại
- Tab "Người dùng" chỉ hiển thị người dùng khớp với từ khóa
- Tab "Bài viết" hiển thị bài viết có nội dung khớp
- Tab "Nhóm" hiển thị nhóm có tên khớp
- Click vào một kết quả để xem chi tiết
- Lịch sử tìm kiếm hiển thị ở dưới thanh tìm kiếm (có thể xóa)

**Cách hoạt động:**
- Tìm kiếm người dùng, bài viết, nhóm
- Tìm kiếm real-time khi gõ
- Lọc kết quả theo loại
- Xem lịch sử tìm kiếm

**Màn hình**: **Màn hình Tìm kiếm** (`SearchScreen`)

### 2. Tìm kiếm nâng cao
**Cách hoạt động:**
- Tìm theo hashtag
- Tìm theo vị trí
- Tìm bài viết đã lưu
- Tìm trong tin nhắn

---

## 🔔 THÔNG BÁO

### 1. Thông báo trong app
**Cách sử dụng:**
- Nhấn icon chuông ở AppBar (góc trên phải) để xem tất cả thông báo
- Thông báo mới có badge màu đỏ hiển thị số lượng chưa đọc
- Danh sách thông báo hiển thị theo thời gian (mới nhất ở trên)
- Các loại thông báo:
  - **Like/Reaction**: "A đã thích bài viết của bạn"
  - **Comment**: "B đã bình luận bài viết của bạn"
  - **Follow**: "C đã follow bạn"
  - **Friend request**: "D đã gửi lời mời kết bạn"
  - **Tag**: "E đã tag bạn trong một bài viết"
  - **Mention**: "F đã nhắc đến bạn trong comment"
- Click vào thông báo để mở bài viết/profile tương ứng
- Swipe trái một thông báo để xóa
- Nhấn "Đánh dấu tất cả đã đọc" để xóa badge
- Có thể lọc thông báo theo loại

**Cách hoạt động:**
- Hiển thị thông báo real-time
- Các loại thông báo:
  - Like/Reaction bài viết
  - Comment bài viết
  - Follow
  - Friend request
  - Tag trong bài viết
  - Mention trong comment
- Đánh dấu đã đọc
- Xóa thông báo
- Lọc theo loại

**Màn hình**: **Màn hình Thông báo** (`NotificationsScreen`)

### 2. Push Notifications
**Cách hoạt động:**
- Sử dụng Firebase Cloud Messaging
- Nhận thông báo khi app ở background
- Click thông báo → Mở màn hình tương ứng
- Quản lý cài đặt thông báo

**Service**: `PushNotificationService`, `NotificationService`

---

## ⚙️ CÀI ĐẶT

### 1. Cài đặt tài khoản
**Các tùy chọn:**
- Đổi mật khẩu
- Xóa tài khoản
- Quản lý email
- Quản lý số điện thoại

**Màn hình**: **Màn hình Cài đặt** (`SettingsScreen`), **Màn hình Đổi mật khẩu** (`ChangePasswordScreen`)

### 2. Quyền riêng tư
**Các tùy chọn:**
- Ai có thể xem bài viết
- Ai có thể gửi lời mời kết bạn
- Ai có thể xem profile
- Ai có thể tag bạn
- Chặn người dùng
- Ẩn nội dung đã lưu

**Màn hình**: **Màn hình Trung tâm Quyền riêng tư** (`PrivacyCenterScreen`), **Màn hình Nội dung Đã ẩn** (`HiddenContentScreen`)

### 3. Ngôn ngữ & Giao diện
**Các tùy chọn:**
- Chọn ngôn ngữ (Tiếng Việt, English)
- Dark mode / Light mode
- Tự động dịch bài viết

**Màn hình**: **Màn hình Ngôn ngữ** (`LanguageScreen`), **Màn hình Cài đặt Dark Mode** (`DarkModeSettingsScreen`)

### 4. Quản lý thời gian
**Các tính năng:**
- Theo dõi thời gian sử dụng app
- Nhắc nhở nghỉ giải lao
- Giới hạn thời gian sử dụng

**Màn hình**: **Màn hình Quản lý Thời gian** (`TimeManagementScreen`), **Màn hình Sử dụng Hàng ngày** (`DailyUsageScreen`)

### 5. Menu tùy chỉnh
**Cách hoạt động:**
- Ẩn/hiện các mục trong menu
- Sắp xếp lại thứ tự (nếu có)

**Màn hình**: **Màn hình Menu** (`MenuScreen`)

---

## 🤖 TÍNH NĂNG AI

### 1. AI Content Assistant (Gợi ý Caption & Hashtags)
**Cách sử dụng:**
- Khi tạo bài viết, sau khi nhập nội dung text hoặc chọn ảnh/video, widget **"Gợi ý từ AI"** tự động hiển thị bên dưới ô nhập
- Widget có 2 chế độ: **"Gợi ý"** và **"Chat"**
- **Chế độ Gợi ý** (mặc định):
  - Tự động phân tích nội dung và ảnh (nếu có) để tạo:
    - **Caption cải thiện**: Caption ngắn gọn, hấp dẫn hơn
    - **Hashtags gợi ý**: 5-10 hashtags phù hợp với nội dung
    - **Bản dịch**: Dịch sang ngôn ngữ khác (nếu cần)
    - **Phân tích cảm xúc**: Tích cực/Trung tính/Tiêu cực
  - Nhấn nút **"Dùng"** ở mỗi gợi ý để áp dụng vào bài viết
  - Caption sẽ thay thế nội dung hiện tại, hashtags sẽ được thêm vào cuối
- **Chế độ Chat**:
  - Chat trực tiếp với AI để yêu cầu tùy chỉnh
  - Có các quick actions: "Viết lại caption ngắn gọn hơn", "Thêm hashtags phù hợp", "Viết caption vui vẻ hơn", "Dịch sang tiếng Anh"
  - Gõ yêu cầu tùy chỉnh và AI sẽ phản hồi
  - Có thể chat nhiều lần để điều chỉnh theo ý muốn
- Widget tự động thu gọn/mở rộng, có thể đóng bằng nút mũi tên
- Nếu chưa có nội dung, có thể nhấn nút **"Nhận gợi ý từ AI"** để mở widget

**Cách hoạt động:**
- Phân tích nội dung text và ảnh (nếu có) bằng AI
- Tạo caption cải thiện, hashtags, bản dịch, phân tích cảm xúc
- Hỗ trợ chat với AI để tùy chỉnh theo yêu cầu
- Sử dụng Groq/Gemini/OpenAI API
- Upload ảnh local lên Cloudinary để AI phân tích

**Màn hình**: **Màn hình Tạo bài viết** (`CreatePostScreen`), **Màn hình Tạo Bài viết trong Nhóm** (`CreateGroupPostScreen`) - widget **AI Content Assistant** (`AIContentAssistantWidget`)

### 2. AI Smart Reply Suggestions
**Cách sử dụng:**
- Mở một bài viết bất kỳ (bài viết phải có nội dung text)
- Scroll xuống phần comment
- Nếu comment trực tiếp vào bài viết (không phải reply comment), widget **"Gợi ý trả lời"** sẽ tự động hiển thị
- Widget hiển thị 3-5 gợi ý trả lời ngắn gọn dựa trên nội dung bài viết (ví dụ: "Cảm ơn bạn đã chia sẻ!", "Bài viết rất hay!")
- Click vào một gợi ý → Text tự động được điền vào ô comment
- Có thể chỉnh sửa text trước khi gửi
- Widget chỉ hiển thị khi comment vào bài viết, không hiển thị khi reply comment

**Cách hoạt động:**
- Phân tích nội dung bài viết
- Tạo 3-5 gợi ý trả lời ngắn gọn
- Hiển thị widget trong phần comment
- Click vào gợi ý → Điền vào ô comment
- Sử dụng Groq/Gemini/OpenAI API

**Màn hình**: **Màn hình Chi tiết Bài viết** (`PostDetailScreen`) - widget **Gợi ý Trả lời AI** (`AISmartReplyWidget`)

### 3. AI Content Moderation
**Cách sử dụng:**
- **Khi đăng bài viết**: Sau khi nhập nội dung và nhấn "Đăng", hệ thống tự động kiểm tra nội dung
  - Nếu phát hiện nội dung **toxic/spam nghiêm trọng** (score ≥ 0.7): Hiển thị cảnh báo đỏ "Nội dung không phù hợp. Vui lòng chỉnh sửa." và **không cho phép đăng**
  - Nếu có **cảnh báo nhẹ** (score ≥ 0.5): Hiển thị dialog "Nội dung này có thể không phù hợp. Bạn có muốn tiếp tục đăng không?" với 2 nút: "Tiếp tục" và "Hủy"
  - Nếu nội dung **an toàn** (score < 0.5): Cho phép đăng bình thường
- **Khi comment**: Tương tự như đăng bài viết, kiểm tra trước khi gửi comment
- Hệ thống tự động phát hiện: toxic content, spam, hate speech, nội dung bạo lực

**Cách hoạt động:**
- Kiểm tra nội dung trước khi đăng/comment
- Phát hiện toxic content, spam, hate speech
- Trả về score (0-1) và isToxic flag
- Chặn nội dung có score ≥ 0.7
- Cảnh báo nội dung có score ≥ 0.5
- Rule-based fallback nếu API fail

**Màn hình**: **Màn hình Tạo bài viết** (`CreatePostScreen`), **Màn hình Chi tiết Bài viết** (`PostDetailScreen`)

### 4. AI Content Quality Score
**Cách sử dụng:**
- Khi tạo bài viết, bắt đầu gõ nội dung vào ô text
- Sau khi gõ và dừng lại 1.5 giây, hệ thống tự động hiển thị widget **"Đánh giá chất lượng"** bên dưới ô text
- Widget hiển thị:
  - **Điểm số** (0-100) với màu tương ứng:
    - 🟢 80-100: "Xuất sắc" (màu xanh lá)
    - 🔵 60-79: "Tốt" (màu xanh dương)
    - 🟡 40-59: "Trung bình" (màu vàng)
    - 🔴 0-39: "Cần cải thiện" (màu đỏ)
  - **Icon cảm xúc**: 😊 (tốt), 😐 (trung bình), 😔 (cần cải thiện)
  - **Gợi ý cải thiện**: "Thêm hashtags", "Thêm ảnh/video", "Mở rộng nội dung"
- Widget tự động cập nhật khi người dùng tiếp tục gõ
- Có thể đóng widget bằng cách nhấn nút X

**Cách hoạt động:**
- Đánh giá chất lượng bài viết (0-100 điểm)
- Phân loại: Xuất sắc (≥80), Tốt (≥60), Trung bình (≥40), Cần cải thiện (<40)
- Đưa ra gợi ý cải thiện:
  - Thêm hashtags
  - Thêm ảnh/video
  - Mở rộng nội dung
- Hiển thị real-time khi người dùng gõ (debounce 1.5s)

**Màn hình**: **Màn hình Tạo bài viết** (`CreatePostScreen`), **Màn hình Tạo Bài viết trong Nhóm** (`CreateGroupPostScreen`)

### 5. AI Comment Summarizer
**Cách sử dụng:**
- Mở một bài viết có ít nhất 3 comments
- Ở AppBar (góc trên phải), nhấn icon **📄 Summarize** (Tóm tắt)
- Hệ thống phân tích tất cả comments và tạo tóm tắt
- Hiển thị dialog với tóm tắt ngắn gọn (3-5 điểm chính)
- Tóm tắt cũng hiển thị dưới dạng card có thể đóng lại ở đầu phần comments
- Giúp người dùng nắm bắt nội dung comments nhanh chóng mà không cần đọc hết

**Cách hoạt động:**
- Tóm tắt tất cả comments thành 3-5 điểm chính
- Hiển thị trong dialog và card dismissible
- Giúp người dùng nắm bắt nội dung nhanh chóng

**Màn hình**: **Màn hình Chi tiết Bài viết** (`PostDetailScreen`)

### 6. AI Test Screen
**Cách hoạt động:**
- Màn hình debug để test tất cả tính năng AI
- Kiểm tra cấu hình API
- Test từng tính năng riêng lẻ
- Xem kết quả chi tiết

**Màn hình**: **Màn hình Test AI** (`AITestScreen`)


---

## 🎮 TÍNH NĂNG KHÁC

### 1. Reels (Thước phim)
**Cách hoạt động:**
- Xem video dạng vertical (TikTok-style)
- Swipe để chuyển video
- Like, comment, share
- Tự động phát video

**Màn hình**: **Màn hình Reels** (`ReelsScreen`)

### 2. Games
**Cách hoạt động:**
- Chơi game trong WebView
- Tích hợp game từ web
- Lưu điểm số

**Màn hình**: **Màn hình Games** (`GamesScreen`), **Màn hình Game WebView** (`GameWebViewScreen`)

### 3. Marketplace
**Cách hoạt động:**
- Mua bán sản phẩm
- Đăng sản phẩm
- Tìm kiếm sản phẩm

**Màn hình**: **Màn hình Marketplace** (`MarketplaceScreen`)

### 4. Events
**Cách hoạt động:**
- Xem sự kiện
- Tạo sự kiện
- Tham gia sự kiện

**Màn hình**: **Màn hình Sự kiện** (`EventsScreen`)

### 5. Memories (Kỷ niệm)
**Cách hoạt động:**
- Xem lại bài viết/kỷ niệm từ năm trước
- Tự động nhắc nhở kỷ niệm

**Màn hình**: **Màn hình Kỷ niệm** (`MemoriesScreen`)

### 6. Analytics (Thống kê)
**Cách hoạt động:**
- Xem thống kê bài viết (lượt xem, like, comment)
- Xem thống kê profile (lượt xem, follow)
- Biểu đồ tương tác theo thời gian

**Màn hình**: **Màn hình Thống kê** (`AnalyticsScreen`)

### 7. Dịch nội dung
**Cách hoạt động:**
- Tự động dịch bài viết sang ngôn ngữ đã chọn
- Sử dụng LibreTranslate API
- Cache bản dịch để tối ưu

**Service**: `LibreTranslateService`, `TranslationService`

### 8. Chia sẻ nội dung
**Cách hoạt động:**
- Chia sẻ bài viết, nhóm, profile
- Sử dụng `share_plus` package
- Tạo deep link (nếu có)

---

## 🔄 LUỒNG HOẠT ĐỘNG CHÍNH

### 1. Luồng đăng bài viết
```
Người dùng nhập nội dung
    ↓
AI Content Quality Score (real-time)
    ↓
Chọn ảnh/video, privacy, location
    ↓
AI Content Moderation (kiểm tra)
    ↓
Upload lên Firebase Storage
    ↓
Lưu vào Firestore
    ↓
Tạo notification cho bạn bè
    ↓
Hiển thị trên feed
```

### 2. Luồng comment
```
Người dùng mở bài viết
    ↓
AI Smart Reply hiển thị gợi ý
    ↓
Người dùng chọn gợi ý hoặc tự gõ
    ↓
AI Content Moderation (kiểm tra)
    ↓
Lưu comment vào Firestore
    ↓
Tạo notification cho người đăng
    ↓
Cập nhật real-time
```

### 3. Luồng cuộc gọi
```
Người dùng A gọi người dùng B
    ↓
Backend tạo Agora token
    ↓
Push notification cho B
    ↓
B nhận cuộc gọi (app foreground/background)
    ↓
Kết nối Agora RTC
    ↓
Bắt đầu cuộc gọi
    ↓
Kết thúc cuộc gọi → Lưu lịch sử
```

### 4. Luồng thông báo
```
Sự kiện xảy ra (like, comment, follow...)
    ↓
Tạo notification trong Firestore
    ↓
Gửi push notification (FCM)
    ↓
Người dùng nhận thông báo
    ↓
Click thông báo → Mở màn hình tương ứng
    ↓
Đánh dấu đã đọc
```

---

## 📊 KIẾN TRÚC HỆ THỐNG

### 1. Frontend (Flutter)
- **State Management**: Provider
- **Navigation**: Navigator 2.0
- **UI Components**: Material Design
- **Responsive**: Hỗ trợ mobile, tablet, desktop

### 2. Backend Services
- **Firebase Auth**: Xác thực người dùng
- **Firestore**: Database real-time
- **Firebase Storage**: Lưu trữ ảnh/video
- **Firebase Cloud Messaging**: Push notifications
- **Agora RTC**: Voice/Video calls
- **SendGrid**: Email service
- **Groq/Gemini/OpenAI**: AI services

### 3. Data Models
- `UserModel`: Thông tin người dùng
- `PostModel`: Bài viết
- `CommentModel`: Bình luận
- `MessageModel`: Tin nhắn
- `GroupModel`: Nhóm
- `StoryModel`: Story
- `NotificationModel`: Thông báo
- `ReactionModel`: Cảm xúc

### 4. Services Layer
- `AuthService`: Xác thực
- `FirestoreService`: Database operations
- `StorageService`: File upload
- `MessageService`: Tin nhắn
- `GroupService`: Quản lý nhóm
- `FriendService`: Quản lý bạn bè
- `AIContentService`: AI features
- `AgoraCallService`: Cuộc gọi
- `NotificationService`: Thông báo
- Và nhiều services khác...

---

## 🔒 BẢO MẬT & PRIVACY

### 1. Bảo mật dữ liệu
- Mã hóa mật khẩu (Firebase Auth)
- Mã hóa dữ liệu nhạy cảm (EncryptionService)
- Secure Storage cho tokens
- HTTPS cho tất cả API calls

### 2. Quyền riêng tư
- Kiểm soát ai có thể xem bài viết
- Kiểm soát ai có thể gửi lời mời kết bạn
- Chặn người dùng
- Ẩn nội dung
- Xóa tài khoản

### 3. Content Moderation
- AI tự động phát hiện toxic content
- Báo cáo nội dung không phù hợp
- Ẩn/xóa nội dung vi phạm

---

## 📱 RESPONSIVE DESIGN

### 1. Mobile
- Bottom navigation bar
- Fullscreen modals
- Swipe gestures
- Touch-optimized UI

### 2. Tablet
- Sidebar navigation
- Multi-column layout
- Larger touch targets

### 3. Desktop/Web
- Top navigation bar
- Sidebar với menu
- Keyboard shortcuts
- Mouse hover effects

---

## 🚀 PERFORMANCE OPTIMIZATION

### 1. Image Optimization
- Cached network images
- Lazy loading
- Thumbnail generation
- Progressive loading

### 2. Video Optimization
- Autoplay với settings
- Pause khi scroll
- Thumbnail preview
- Progressive loading

### 3. Database Optimization
- Indexed queries
- Pagination
- Real-time streams
- Cache frequently accessed data

### 4. Network Optimization
- Debounce cho search
- Batch operations
- Offline support (Firestore)
- Retry logic

---

## 📝 GHI CHÚ QUAN TRỌNG

1. **AI Features**: Cần cấu hình API key trong `app_constants.dart`
2. **Push Notifications**: Cần cấu hình FCM trong Firebase Console
3. **Agora Calls**: Cần cấu hình Agora App ID và Certificate
4. **Email Service**: Cần cấu hình SendGrid API key trong backend
5. **Deep Linking**: Chưa được implement đầy đủ (có thể mở rộng)

---

## 📅 CẬP NHẬT

**Phiên bản hiện tại**: 1.0.5+6

**Ngày cập nhật**: 2025

---

**Tài liệu này được tạo tự động dựa trên codebase hiện tại. Một số tính năng có thể đang trong quá trình phát triển hoặc cần cấu hình thêm.**

