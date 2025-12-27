import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import '../../../flutter_gen/gen_l10n/app_localizations.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/privacy_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/deezer_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/location_sharing_service.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/ai_content_service.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/notification_model.dart';
import '../../providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/ai_content_assistant_widget.dart';

class CreatePostScreen extends StatefulWidget {
  final PostModel? postToEdit; // Nếu có, sẽ ở chế độ chỉnh sửa

  const CreatePostScreen({super.key, this.postToEdit});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  final DeezerService _spotifyService = DeezerService();
  final UserService _userService = UserService();
  final LocationSharingService _locationService = LocationSharingService();
  final NotificationService _notificationService = NotificationService();
  final ImagePicker _imagePicker = ImagePicker();
  List<XFile> _selectedImages = [];
  XFile? _selectedVideo;
  VideoPlayerController? _videoController;
  bool _isLoading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';
  PrivacyType _selectedPrivacy = PrivacyType.public;
  String? _selectedFeeling;
  String? _selectedLocation;
  DeezerTrack? _selectedMusic;
  List<UserModel> _taggedUsers = []; // Users tagged in the post
  String? _selectedMilestoneCategory; // Selected milestone category
  String? _selectedMilestoneEvent; // Selected milestone event
  String? _selectedGifUrl; // Selected GIF URL from GIPHY
  // TODO: Thay YOUR_GIPHY_API_KEY bằng Giphy API key thực tế của bạn
  // Lấy tại: https://developers.giphy.com/dashboard/
  static const String _giphyApiKey = 'YOUR_GIPHY_API_KEY';
  AIContentQuality? _contentQuality;
  bool _isLoadingQuality = false;
  Timer? _qualityDebounceTimer;

  @override
  void initState() {
    super.initState();
    // Load dữ liệu bài viết nếu đang edit
    if (widget.postToEdit != null) {
      _loadPostData();
    }
  }

  void _loadPostData() {
    final post = widget.postToEdit!;
    _contentController.text = post.content;
    _selectedPrivacy = post.privacy;
    _selectedLocation = post.location;
    _selectedFeeling = post.feeling;
    _selectedMilestoneCategory = post.milestoneCategory;
    _selectedMilestoneEvent = post.milestoneEvent;
    _selectedGifUrl = post.gifUrl;
    
    // Load tagged users
    if (post.taggedUserIds.isNotEmpty) {
      _loadTaggedUsers(post.taggedUserIds);
    }
    
    // Load music if exists
    if (post.musicTrackId != null && post.musicTrackId!.isNotEmpty) {
      _selectedMusic = DeezerTrack(
        id: post.musicTrackId!,
        name: post.musicName ?? '',
        artist: post.musicArtist ?? '',
        previewUrl: post.musicPreviewUrl ?? '',
        imageUrl: post.musicImageUrl ?? '',
        externalUrl: post.musicExternalUrl ?? '',
      );
    }
  }

  Future<void> _loadTaggedUsers(List<String> userIds) async {
    try {
      final users = <UserModel>[];
      for (final userId in userIds) {
        final user = await _userService.getUserById(userId);
        if (user != null) {
          users.add(user);
        }
      }
      if (mounted) {
        setState(() {
          _taggedUsers = users;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error loading tagged users: $e');
      }
    }
  }

  @override
  void dispose() {
    _qualityDebounceTimer?.cancel();
    _contentController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _debounceQualityCheck() {
    _qualityDebounceTimer?.cancel();
    _qualityDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
      _checkContentQuality();
    });
  }

  Future<void> _checkContentQuality() async {
    final text = _contentController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _contentQuality = null;
      });
      return;
    }

    setState(() {
      _isLoadingQuality = true;
    });

    try {
      final aiService = AIContentService();
      final hashtagsCount = text.split('#').length - 1;
      final quality = await aiService.evaluateContentQuality(
        text: text,
        hashtagsCount: hashtagsCount,
        hasImage: _selectedImages.isNotEmpty,
      );

      if (mounted) {
        setState(() {
          _contentQuality = quality;
          _isLoadingQuality = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingQuality = false;
        });
        debugPrint('Error checking content quality: $e');
      }
    }
  }

  Widget _buildContentQualityWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, size: 18, color: Colors.purple[700]),
              const SizedBox(width: 8),
              Text(
                'Đánh giá chất lượng',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple[700],
                ),
              ),
              if (_isLoadingQuality) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          if (!_isLoadingQuality && _contentQuality != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // Score display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getQualityColor(_contentQuality!.score).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_contentQuality!.score}/100',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _getQualityColor(_contentQuality!.score),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _contentQuality!.qualityLevel,
                        style: TextStyle(
                          fontSize: 12,
                          color: _getQualityColor(_contentQuality!.score),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Quality indicator
                _buildQualityIndicator(_contentQuality!.score),
              ],
            ),
            if (_contentQuality!.suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Gợi ý cải thiện:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.purple[700],
                ),
              ),
              const SizedBox(height: 6),
              ..._contentQuality!.suggestions.map((suggestion) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline, size: 14, color: Colors.purple[600]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            suggestion,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ],
      ),
    );
  }

  Color _getQualityColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.blue;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }

  Widget _buildQualityIndicator(int score) {
    Color color = _getQualityColor(score);
    IconData icon;
    if (score >= 80) {
      icon = Icons.sentiment_very_satisfied;
    } else if (score >= 60) {
      icon = Icons.sentiment_satisfied;
    } else if (score >= 40) {
      icon = Icons.sentiment_neutral;
    } else {
      icon = Icons.sentiment_dissatisfied;
    }
    return Icon(icon, color: color, size: 24);
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          // Xóa video và GIF nếu đã chọn ảnh (chỉ cho phép ảnh hoặc video hoặc GIF)
          _selectedVideo = null;
          _videoController?.dispose();
          _videoController = null;
          _selectedGifUrl = null;
          _selectedImages.addAll(images);
          // Limit to 5 images
          if (_selectedImages.length > 5) {
            _selectedImages = _selectedImages.take(5).toList();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chỉ có thể chọn tối đa 5 ảnh')));
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi chọn ảnh: $e')));
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        setState(() {
          // Xóa ảnh và GIF nếu đã chọn video (chỉ cho phép ảnh hoặc video hoặc GIF)
          _selectedImages.clear();
          _selectedGifUrl = null;
          _selectedVideo = video;
        });

        // Initialize video player for preview
        if (!kIsWeb) {
          _videoController?.dispose();
          _videoController = VideoPlayerController.file(File(video.path));
          await _videoController!.initialize();
          setState(() {});
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi chọn video: $e')));
    }
  }

  void _removeVideo() {
    setState(() {
      _videoController?.dispose();
      _videoController = null;
      _selectedVideo = null;
    });
  }

  Future<void> _pickFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85, // Chất lượng ảnh (0-100)
      );
      if (image != null) {
        setState(() {
          // Xóa video và GIF nếu đã chọn ảnh (chỉ cho phép ảnh hoặc video hoặc GIF)
          _selectedVideo = null;
          _videoController?.dispose();
          _videoController = null;
          _selectedGifUrl = null;

          // Thêm ảnh mới chụp
          _selectedImages.add(image);

          // Limit to 5 images
          if (_selectedImages.length > 5) {
            _selectedImages = _selectedImages.take(5).toList();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chỉ có thể chọn tối đa 5 ảnh')));
            }
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã chụp ảnh thành công'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
      ScaffoldMessenger.of(
        context,
        ).showSnackBar(SnackBar(content: Text('Lỗi chụp ảnh: ${e.toString()}'), backgroundColor: Colors.red));
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _showFeelingDialog() {
    final feelings = [
      '😊 Vui vẻ',
      '😍 Yêu thích',
      '😮 Ngạc nhiên',
      '😢 Buồn',
      '😡 Tức giận',
      '👍 Thích',
      '❤️ Yêu',
      '😂 Haha',
      '😮 Wow',
      '😢 Buồn',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Chọn cảm xúc', style: TextStyle(color: Colors.black)),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 3),
            itemCount: feelings.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(feelings[index], style: const TextStyle(color: Colors.black)),
                onTap: () {
                  setState(() {
                    _selectedFeeling = feelings[index];
                  });
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showMusicSearchDialog() async {
    final searchController = TextEditingController();
    List<DeezerTrack> searchResults = [];
    bool isSearching = false;
    bool suggestionsLoaded = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.grey[900],
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Text(
                        'Tìm kiếm nhạc',
                        style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Tự động load gợi ý nhạc nghe được lần đầu tiên mở dialog
                if (!suggestionsLoaded) ...[],
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: searchController,
                          style: const TextStyle(color: Colors.black),
                          decoration: InputDecoration(
                            hintText: 'Nhập tên bài hát hoặc nghệ sĩ...',
                            hintStyle: const TextStyle(color: Colors.grey),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search, color: Colors.black),
                              onPressed: () async {
                                if (searchController.text.trim().isEmpty) return;
                                setDialogState(() {
                                  isSearching = true;
                                });
                                try {
                                  final results = await _spotifyService.searchTracks(
                                        searchController.text.trim(),
                                        limit: 20,
                                      );
                                  setDialogState(() {
                                    searchResults = results;
                                    isSearching = false;
                                  });
                                } catch (e) {
                                  setDialogState(() {
                                    isSearching = false;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Lỗi tìm kiếm: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                          onSubmitted: (value) async {
                            if (value.trim().isEmpty) return;
                            setDialogState(() {
                              isSearching = true;
                            });
                            try {
                              final results = await _spotifyService.searchTracks(value.trim(), limit: 20);
                              setDialogState(() {
                                searchResults = results;
                                isSearching = false;
                              });
                            } catch (e) {
                              setDialogState(() {
                                isSearching = false;
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Lỗi tìm kiếm: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        if (!suggestionsLoaded) ...[
                          // Trigger load gợi ý sau frame đầu tiên
                          Builder(
                            builder: (ctx) {
                              suggestionsLoaded = true;
                              Future.microtask(() async {
                                setDialogState(() {
                                  isSearching = true;
                                });
                                try {
                                  final results = await _spotifyService.searchTracks('lofi chill', limit: 20);
                                  setDialogState(() {
                                    searchResults = results;
                                    isSearching = false;
                                  });
                                } catch (_) {
                                  setDialogState(() {
                                    isSearching = false;
                                  });
                                }
                              });
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                        if (isSearching)
                          const Expanded(child: Center(child: CircularProgressIndicator()))
                        else if (searchResults.isEmpty && searchController.text.isNotEmpty)
                          const Expanded(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('Không tìm thấy kết quả', style: TextStyle(color: Colors.grey)),
                              ),
                            ),
                          )
                        else if (searchResults.isNotEmpty)
                          Expanded(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: searchResults.length,
                              itemBuilder: (context, index) {
                                final track = searchResults[index];
                                return ListTile(
                                  leading: track.imageUrl != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: Image.network(
                                            track.imageUrl!,
                                            width: 50,
                                            height: 50,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return const Icon(Icons.music_note, color: Colors.black);
                                                },
                                          ),
                                        )
                                      : const Icon(Icons.music_note, color: Colors.black),
                                  title: Text(
                                    track.name,
                                    style: const TextStyle(color: Colors.black),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    track.artist,
                                    style: const TextStyle(color: Colors.grey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: track.previewUrl != null && track.previewUrl!.isNotEmpty
                                      ? const Text('Nghe 30s', style: TextStyle(color: Colors.green, fontSize: 11))
                                      : const Text('Không có demo', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  onTap: () async {
                                    setState(() {
                                      _selectedMusic = track;
                                    });
                                    Navigator.pop(context);

                                    // Tự phát nhạc ngay sau khi chọn
                                    final preview = track.previewUrl;
                                    final urlToOpen = (preview != null && preview.isNotEmpty)
                                        ? preview
                                        : (track.externalUrl.isNotEmpty ? track.externalUrl : null);
                                    if (urlToOpen != null) {
                                      final uri = Uri.parse(urlToOpen);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTagUserDialog() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final TextEditingController searchController = TextEditingController();
    List<UserModel> allUsers = [];
    List<UserModel> filteredUsers = [];

    // Load all users initially
    final strings = AppLocalizations.of(context);
    final usersStream = _userService.searchUsers('');
    final users = await usersStream.first;
    allUsers = users.where((user) => user.id != currentUser.id).toList();
    filteredUsers = allUsers;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Text(
                        strings?.postTagPeople ?? 'Gắn thẻ người khác',
                        style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black87),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    controller: searchController,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm người dùng...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        if (value.isEmpty) {
                          filteredUsers = allUsers;
                        } else {
                          final query = value.toLowerCase();
                          filteredUsers = allUsers.where((user) {
                            return user.fullName.toLowerCase().contains(query) ||
                                user.username.toLowerCase().contains(query) ||
                                user.email.toLowerCase().contains(query);
                          }).toList();
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: filteredUsers.isEmpty
                      ? const Center(
                          child: Text('Không tìm thấy người dùng', style: TextStyle(color: Colors.grey)),
                        )
                      : ListView.builder(
                          itemCount: filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final isTagged = _taggedUsers.any((u) => u.id == user.id);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                                child: user.avatarUrl == null
                                    ? Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U')
                                    : null,
                              ),
                              title: Text(user.fullName, style: const TextStyle(color: Colors.black87)),
                              subtitle: Text('@${user.username}', style: const TextStyle(color: Colors.grey)),
                              trailing: isTagged
                                  ? const Icon(Icons.check_circle, color: Colors.blue)
                                  : const Icon(Icons.add_circle_outline, color: Colors.grey),
                              onTap: () {
                                setDialogState(() {
                                  if (isTagged) {
                                    _taggedUsers.removeWhere((u) => u.id == user.id);
                                  } else {
                                    _taggedUsers.add(user);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
                if (_taggedUsers.isNotEmpty) ...[
                  const Divider(color: Colors.grey),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _taggedUsers.map((user) {
                        return Chip(
                          label: Text(user.fullName, style: const TextStyle(color: Colors.black87)),
                          avatar: CircleAvatar(
                            backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                            child: user.avatarUrl == null
                                ? Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U')
                                : null,
                          ),
                          deleteIcon: const Icon(Icons.close, color: Colors.black87, size: 18),
                          onDeleted: () {
                            setDialogState(() {
                              _taggedUsers.removeWhere((u) => u.id == user.id);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Hủy', style: TextStyle(color: Colors.black87)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Xong'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    searchController.dispose();
  }

  void _showMilestoneCategoryDialog() {
    final categories = [
      {
        'name': 'Công việc',
        'icon': Icons.work_outline,
        'events': ['Công việc mới', 'Thăng chức', 'Nghỉ hưu', 'Thay đổi công việc', 'Kỷ niệm làm việc'],
      },
      {
        'name': 'Học vấn',
        'icon': Icons.school_outlined,
        'events': ['Tốt nghiệp', 'Nhập học', 'Bằng cấp', 'Học bổng', 'Kỷ niệm học tập'],
      },
      {
        'name': 'Mối quan hệ',
        'icon': Icons.favorite_outline,
        'events': ['Kết hôn', 'Đính hôn', 'Bắt đầu hẹn hò', 'Kỷ niệm', 'Ly hôn'],
      },
      {
        'name': 'Living',
        'icon': Icons.home_outlined,
        'events': ['Chuyển nhà', 'Mua nhà', 'Thuê nhà', 'Sửa nhà', 'Kỷ niệm nhà'],
      },
      {
        'name': 'Gia đình',
        'icon': Icons.family_restroom,
        'events': ['Sinh con', 'Con chào đời', 'Kỷ niệm gia đình', 'Sự kiện gia đình'],
      },
      {
        'name': 'Du lịch',
        'icon': Icons.flight_takeoff_outlined,
        'events': ['Chuyến đi mới', 'Kỷ niệm du lịch', 'Điểm đến mới'],
      },
      {
        'name': 'Activities',
        'icon': Icons.sports_soccer_outlined,
        'events': ['Sự kiện thể thao', 'Hoạt động mới', 'Thành tích'],
      },
      {
        'name': 'Chăm sóc sức khỏe',
        'icon': Icons.favorite_outline,
        'events': ['Khám sức khỏe', 'Phẫu thuật', 'Hồi phục', 'Thành tích sức khỏe'],
      },
      {
        'name': 'Milestones',
        'icon': Icons.star_outline,
        'events': ['Sinh nhật', 'Kỷ niệm đặc biệt', 'Thành tựu', 'Mốc quan trọng'],
      },
      {
        'name': 'Tưởng nhớ',
        'icon': Icons.candlestick_chart_outlined,
        'events': ['Tưởng nhớ', 'Kỷ niệm'],
      },
    ];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Text(
                      'Tạo sự kiện trong đời',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Chia sẻ và ghi nhớ những khoảnh khắc quan trọng trong đời.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: categories.length + 1, // +1 for custom category
                  itemBuilder: (context, index) {
                    if (index == categories.length) {
                      // Custom category button
                      return InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(const SnackBar(content: Text('Tính năng tạo danh mục riêng đang phát triển')));
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[600]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.star_outline, size: 40, color: Colors.grey),
                              const SizedBox(height: 8),
                              const Text(
                                'Tạo danh mục của riêng bạn',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final category = categories[index];
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _showMilestoneEventDialog(category['name'] as String, category['events'] as List<String>);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[600]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(category['icon'] as IconData, size: 40, color: Colors.blue),
                            const SizedBox(height: 8),
                            Text(
                              category['name'] as String,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMilestoneEventDialog(String category, List<String> events) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () {
                        Navigator.pop(context);
                        _showMilestoneCategoryDialog();
                      },
                    ),
                    Expanded(
                      child: Text(
                        category,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return ListTile(
                      title: Text(event, style: const TextStyle(color: Colors.black)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                      onTap: () {
                        setState(() {
                          _selectedMilestoneCategory = category;
                          _selectedMilestoneEvent = event;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _searchGifs(String query) async {
    try {
      final url = Uri.parse(
        'https://api.giphy.com/v1/gifs/search?api_key=$_giphyApiKey&q=${Uri.encodeComponent(query)}&limit=25&rating=g',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> gifs = data['data'] ?? [];
        return gifs.map((gif) {
          return {
            'id': gif['id'],
            'url': gif['images']['original']['url'] ?? gif['images']['fixed_height']['url'],
            'title': gif['title'] ?? '',
            'preview': gif['images']['fixed_height_small']['url'] ?? gif['images']['fixed_height']['url'],
          };
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error searching GIFs: $e');
      return [];
    }
  }

  void _showGifSearchDialog() async {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> gifs = [];
    bool isSearching = false;
    bool initialLoad = true;

    // Load trending GIFs initially
    if (initialLoad) {
      try {
        final url = Uri.parse('https://api.giphy.com/v1/gifs/trending?api_key=$_giphyApiKey&limit=25&rating=g');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> gifsData = data['data'] ?? [];
          gifs = gifsData.map((gif) {
            return {
              'id': gif['id'],
              'url': gif['images']['original']['url'] ?? gif['images']['fixed_height']['url'],
              'title': gif['title'] ?? '',
              'preview': gif['images']['fixed_height_small']['url'] ?? gif['images']['fixed_height']['url'],
            };
          }).toList();
        }
      } catch (e) {
        debugPrint('Error loading trending GIFs: $e');
      }
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Text(
                        'Tìm kiếm GIF',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    controller: searchController,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm GIF...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white70),
                              onPressed: () {
                                searchController.clear();
                                setDialogState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey[300]!,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: (value) {
                      setDialogState(() {});
                    },
                    onSubmitted: (value) async {
                      if (value.trim().isEmpty) return;
                      setDialogState(() {
                        isSearching = true;
                        initialLoad = false;
                      });
                      final results = await _searchGifs(value.trim());
                      setDialogState(() {
                        gifs = results;
                        isSearching = false;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : gifs.isEmpty
                      ? const Center(
                          child: Text('Nhập từ khóa để tìm kiếm GIF', style: TextStyle(color: Colors.grey)),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1,
                              ),
                          itemCount: gifs.length,
                          itemBuilder: (context, index) {
                            final gif = gifs[index];
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedGifUrl = gif['url'] as String;
                                  // Xóa ảnh và video nếu đã chọn GIF
                                  _selectedImages.clear();
                                  _selectedVideo = null;
                                  _videoController?.dispose();
                                  _videoController = null;
                                });
                                Navigator.pop(context);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  gif['preview'] as String,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                        return Center(
                                          child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                  loadingProgress.expectedTotalBytes!
                                                : null,
                                          ),
                                        );
                                      },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(color: Colors.grey[300], child: const Icon(Icons.error));
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    searchController.dispose();
  }


  Future<void> _showCheckInDialog() async {
                  setState(() {
      _isLoading = true;
    });

    try {
      // Kiểm tra và yêu cầu permission
      final hasPermission = await _locationService.requestLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cần quyền truy cập vị trí để check in. Vui lòng cấp quyền trong Settings.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Lấy vị trí hiện tại
      final position = await _locationService.getCurrentPosition();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể lấy vị trí. Vui lòng kiểm tra quyền truy cập và đảm bảo GPS đã bật.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Lấy địa chỉ
      String? address;
      try {
        address = await _locationService.getAddressFromCoordinates(position.latitude, position.longitude);
      } catch (e) {
        address = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      }

      // Lưu location vào post
      setState(() {
        _selectedLocation = address;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã check in tại: ${address ?? "Vị trí hiện tại"}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi check in: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Gửi notification cho các user được gắn thẻ
  Future<void> _sendTagNotifications(String postId, String actorId) async {
    try {
      for (final taggedUser in _taggedUsers) {
        // Không gửi notification cho chính mình
        if (taggedUser.id == actorId) continue;
        
        try {
          await _notificationService.createNotification(
            NotificationModel(
              id: '',
              userId: taggedUser.id, // User được gắn thẻ
              actorId: actorId, // User tạo post
              type: NotificationType.mention, // Dùng mention type cho tag
              postId: postId,
              createdAt: DateTime.now(),
                  ),
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error sending tag notification to ${taggedUser.id}: $e');
          }
          // Tiếp tục gửi cho các user khác dù có lỗi
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in _sendTagNotifications: $e');
      }
    }
  }

  Future<void> _createPost() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Khi edit, cho phép chỉ có text
    final isEditMode = widget.postToEdit != null;
    if (!isEditMode && 
        _contentController.text.trim().isEmpty &&
        _selectedImages.isEmpty &&
        _selectedVideo == null &&
        _selectedGifUrl == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng nhập nội dung hoặc chọn ảnh/video')));
      return;
    }

    // AI Content Moderation - kiểm tra nội dung trước khi đăng
    final content = _contentController.text.trim();
    if (content.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _uploadStatus = 'Đang kiểm tra nội dung...';
      });

      try {
        final aiService = AIContentService();
        final moderation = await aiService.moderateContent(content);
        
        if (moderation.shouldBlock) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  moderation.reason ?? 'Nội dung không phù hợp. Vui lòng chỉnh sửa.',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
            return;
          }
        } else if (moderation.shouldWarn) {
          if (mounted) {
            final shouldContinue = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Cảnh báo nội dung'),
                content: Text(
                  moderation.reason ?? 'Nội dung có thể không phù hợp. Bạn có muốn tiếp tục đăng?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Hủy'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Tiếp tục'),
                  ),
                ],
              ),
            );
            if (shouldContinue != true) {
              setState(() {
                _isLoading = false;
              });
              return;
            }
          }
        }
      } catch (e) {
        // Nếu AI moderation fail, vẫn cho phép đăng (không block user)
        debugPrint('AI moderation error: $e');
      }
    }

    setState(() {
      _isLoading = true;
      _uploadStatus = '';
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get content without feeling (feeling will be stored separately)
      String content = _contentController.text.trim();

      // Upload images or video
      List<String> imageUrls = [];
      String? videoUrl;
      String? postId;
      
      // Nếu đang edit, sử dụng media URLs hiện có
      if (isEditMode) {
        imageUrls = List<String>.from(widget.postToEdit!.mediaUrls);
        videoUrl = widget.postToEdit!.videoUrl;
        postId = widget.postToEdit!.id;
      }

      if (_selectedVideo != null) {
        // Upload video (chỉ khi tạo mới hoặc thay đổi video)
        if (!isEditMode || widget.postToEdit!.videoUrl == null) {
          setState(() {
            _uploadStatus = 'Đang tải video lên...';
            _uploadProgress = 0.1;
          });
          final videoFile = File(_selectedVideo!.path);
          videoUrl = await _storageService.uploadVideo(videoFile, currentUser.id);
          setState(() {
            _uploadProgress = 1.0;
          });
        }

        // Create or update post with video
        final post = PostModel(
          id: isEditMode ? postId! : '',
          userId: currentUser.id,
          content: content,
          privacy: _selectedPrivacy,
          location: _selectedLocation,
          videoUrl: videoUrl,
          gifUrl: _selectedGifUrl,
          taggedUserIds: _taggedUsers.map((u) => u.id).toList(),
          feeling: _selectedFeeling,
          milestoneCategory: _selectedMilestoneCategory,
          milestoneEvent: _selectedMilestoneEvent,
          musicTrackId: _selectedMusic?.id,
          musicName: _selectedMusic?.name,
          musicArtist: _selectedMusic?.artist,
          musicPreviewUrl: _selectedMusic?.previewUrl,
          musicImageUrl: _selectedMusic?.imageUrl,
          musicExternalUrl: _selectedMusic?.externalUrl,
          createdAt: isEditMode ? widget.postToEdit!.createdAt : DateTime.now(),
          updatedAt: DateTime.now(),
        );
        if (isEditMode) {
          await _firestoreService.updatePost(post);
        } else {
          postId = await _firestoreService.createPost(post);
        }
      } else if (_selectedImages.isNotEmpty || (isEditMode && imageUrls.isNotEmpty)) {
        // Upload new images if any
        if (_selectedImages.isNotEmpty) {
          if (!isEditMode) {
        // Create post first to get ID
        final tempPost = PostModel(
          id: '',
          userId: currentUser.id,
          content: content,
          privacy: _selectedPrivacy,
          location: _selectedLocation,
          musicTrackId: _selectedMusic?.id,
          musicName: _selectedMusic?.name,
          musicArtist: _selectedMusic?.artist,
          musicPreviewUrl: _selectedMusic?.previewUrl,
          musicImageUrl: _selectedMusic?.imageUrl,
          musicExternalUrl: _selectedMusic?.externalUrl,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
            postId = await _firestoreService.createPost(tempPost);
          }

          // Upload new images - Upload song song để tăng tốc độ
          setState(() {
            _uploadStatus = 'Đang tải ảnh lên... (0/${_selectedImages.length})';
            _uploadProgress = 0.0;
          });
          
          // Upload tất cả ảnh song song
          final uploadFutures = <Future<String>>[];
          for (int i = 0; i < _selectedImages.length; i++) {
            final index = i;
            if (kIsWeb) {
              // Web: use bytes
              uploadFutures.add(
                _selectedImages[index].readAsBytes().then((bytes) async {
                  final url = await _storageService.uploadPostImageBytes(bytes);
                  if (mounted) {
                    setState(() {
                      _uploadStatus = 'Đang tải ảnh lên... (${index + 1}/${_selectedImages.length})';
                      _uploadProgress = (index + 1) / _selectedImages.length;
                    });
                  }
                  return url;
                }),
              );
            } else {
              // Mobile/Desktop: use File
              uploadFutures.add(
                Future(() async {
                  final file = File(_selectedImages[index].path);
                  final url = await _storageService.uploadPostImage(file, postId!, index);
                  if (mounted) {
                    setState(() {
                      _uploadStatus = 'Đang tải ảnh lên... (${index + 1}/${_selectedImages.length})';
                      _uploadProgress = (index + 1) / _selectedImages.length;
                    });
                  }
                  return url;
                }),
              );
            }
          }
          
          // Chờ tất cả ảnh upload xong
          final uploadedUrls = await Future.wait(uploadFutures);
          imageUrls.addAll(uploadedUrls);
        }

        // Update post with image URLs
        final updatedPost = PostModel(
          id: postId!,
          userId: currentUser.id,
          content: content,
          privacy: _selectedPrivacy,
          location: _selectedLocation,
          mediaUrls: imageUrls,
          gifUrl: _selectedGifUrl,
          taggedUserIds: _taggedUsers.map((u) => u.id).toList(),
          feeling: _selectedFeeling,
          milestoneCategory: _selectedMilestoneCategory,
          milestoneEvent: _selectedMilestoneEvent,
          musicTrackId: _selectedMusic?.id,
          musicName: _selectedMusic?.name,
          musicArtist: _selectedMusic?.artist,
          musicPreviewUrl: _selectedMusic?.previewUrl,
          musicImageUrl: _selectedMusic?.imageUrl,
          musicExternalUrl: _selectedMusic?.externalUrl,
          createdAt: isEditMode ? widget.postToEdit!.createdAt : DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _firestoreService.updatePost(updatedPost);
      } else {
        // Create or update post without media
        final post = PostModel(
          id: isEditMode ? postId! : '',
          userId: currentUser.id,
          content: content,
          privacy: _selectedPrivacy,
          location: _selectedLocation,
          gifUrl: _selectedGifUrl,
          taggedUserIds: _taggedUsers.map((u) => u.id).toList(),
          feeling: _selectedFeeling,
          milestoneCategory: _selectedMilestoneCategory,
          milestoneEvent: _selectedMilestoneEvent,
          musicTrackId: _selectedMusic?.id,
          musicName: _selectedMusic?.name,
          musicArtist: _selectedMusic?.artist,
          musicPreviewUrl: _selectedMusic?.previewUrl,
          musicImageUrl: _selectedMusic?.imageUrl,
          musicExternalUrl: _selectedMusic?.externalUrl,
          createdAt: isEditMode ? widget.postToEdit!.createdAt : DateTime.now(),
          updatedAt: DateTime.now(),
        );
        if (isEditMode) {
          await _firestoreService.updatePost(post);
        } else {
          postId = await _firestoreService.createPost(post);
        }
      }

      // Gửi notification cho các user được gắn thẻ (chỉ khi tạo mới) - chạy background
      if (!isEditMode && postId != null && _taggedUsers.isNotEmpty) {
        _sendTagNotifications(postId, currentUser.id).catchError((e) {
          // Ignore notification errors, không ảnh hưởng đến việc đăng bài
          debugPrint('Error sending tag notifications: $e');
        });
      }

      if (mounted) {
        setState(() {
          _uploadProgress = 1.0;
          _uploadStatus = 'Hoàn tất!';
        });
        // Đợi một chút để hiển thị "Hoàn tất" trước khi đóng
        await Future.delayed(const Duration(milliseconds: 300));
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          content: Text(isEditMode ? 'Đã cập nhật bài viết thành công!' : 'Đã tạo bài viết thành công!'),
            backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tạo bài viết: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadProgress = 0.0;
          _uploadStatus = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final strings = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.postToEdit != null ? 'Chỉnh sửa bài viết' : (strings?.createPostTitle ?? 'Tạo bài viết')),
        actions: [
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  if (_uploadStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        _uploadStatus,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                ],
              ),
            )
          else
            TextButton(
              onPressed: _createPost,
              style: TextButton.styleFrom(
                // Đảm bảo nút hiển thị rõ trên AppBar
                foregroundColor: Colors.black,
              ),
              child: Text(
                strings?.postShare ?? 'Đăng bài',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // User profile and settings
              if (currentUser != null) ...[
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: currentUser.avatarUrl != null ? NetworkImage(currentUser.avatarUrl!) : null,
                      child: currentUser.avatarUrl == null
                          ? Text(
                              currentUser.fullName.isNotEmpty ? currentUser.fullName[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.black),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(currentUser.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 4),
                          // Privacy and settings row
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _SettingButton(
                                icon: _selectedPrivacy.icon,
                                label: _selectedPrivacy.name,
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    builder: (context) => Container(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: PrivacyType.values.map((type) {
                                          return ListTile(
                                            leading: Icon(type.icon),
                                            title: Text(type.name),
                                            onTap: () {
                                              setState(() {
                                                _selectedPrivacy = type;
                                              });
                                              Navigator.pop(context);
                                            },
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              _SettingButton(
                                icon: Icons.add_photo_alternate,
                                label: '+ Album',
                                onTap: () {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(const SnackBar(content: Text('Tính năng album đang phát triển')));
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Content text field
              TextFormField(
                controller: _contentController,
                maxLines: 5,
                minLines: 1,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: strings?.postPlaceholder ?? 'Bạn đang nghĩ gì?',
                  hintStyle: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).hintColor,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                ),
                validator: (value) {
                  if ((value == null || value.trim().isEmpty) &&
                      _selectedImages.isEmpty &&
                      _selectedVideo == null &&
                      _selectedGifUrl == null) {
                    return 'Vui lòng nhập nội dung hoặc chọn ảnh/video/GIF';
                  }
                  return null;
                },
                onChanged: (value) {
                  // Trigger rebuild to show/hide AI assistant
                  setState(() {});
                  // Debounce quality check
                  _debounceQualityCheck();
                },
              ),
              const SizedBox(height: 16),
              
              // AI Content Quality Score
              if (_contentController.text.isNotEmpty)
                _buildContentQualityWidget(),
              
              const SizedBox(height: 16),
              
              // AI Content Assistant
              if (_contentController.text.isNotEmpty || _selectedImages.isNotEmpty)
                AIContentAssistantWidget(
                  text: _contentController.text,
                  imageUrl: _selectedImages.isNotEmpty ? _selectedImages.first.path : null,
                  onCaptionSelected: (caption) {
                    setState(() {
                      _contentController.text = caption;
                    });
                  },
                  onHashtagsSelected: (hashtags) {
                    setState(() {
                      final currentText = _contentController.text;
                      final hashtagsText = hashtags.join(' ');
                      _contentController.text = currentText.isEmpty
                          ? hashtagsText
                          : '$currentText\n\n$hashtagsText';
                    });
                  },
                  onTranslationSelected: (translation) {
                    setState(() {
                      _contentController.text = translation;
                    });
                  },
              ),
              const SizedBox(height: 16),

              // Selected GIF
              if (_selectedGifUrl != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _selectedGifUrl!,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 200,
                              color: Colors.grey[200],
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 200,
                              color: Colors.grey[200],
                              child: const Center(child: Icon(Icons.error, size: 50)),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.black),
                          style: IconButton.styleFrom(backgroundColor: Colors.white54),
                          onPressed: () {
                            setState(() {
                              _selectedGifUrl = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              // Selected video
              if (_selectedVideo != null && _videoController != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  height: 300,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.black),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.black,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_videoController!.value.isPlaying) {
                                    _videoController!.pause();
                                  } else {
                                    _videoController!.play();
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.black),
                          onPressed: _removeVideo,
                        ),
                      ),
                    ],
                  ),
                ),

              // Selected images
              if (_selectedImages.isNotEmpty)
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: kIsWeb
                                  ? null
                                  : DecorationImage(
                                      image: FileImage(File(_selectedImages[index].path)),
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 16,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.black),
                              onPressed: () => _removeImage(index),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

              const SizedBox(height: 16),

              // Tagged users display
              if (_taggedUsers.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.label, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _taggedUsers.length == 1
                                  ? 'Đã gắn thẻ ${_taggedUsers.first.fullName}'
                                  : 'Đã gắn thẻ ${_taggedUsers.map((u) => u.fullName).join(", ")}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                            ),
                        ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _taggedUsers.map((user) {
                          return Chip(
                            label: Text(user.fullName),
                            avatar: CircleAvatar(
                              backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                              child: user.avatarUrl == null
                                  ? Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U')
                                  : null,
                            ),
                            onDeleted: () {
                              setState(() {
                                _taggedUsers.removeWhere((u) => u.id == user.id);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Selected milestone display
              if (_selectedMilestoneCategory != null && _selectedMilestoneEvent != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.flag, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedMilestoneCategory!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(
                              _selectedMilestoneEvent!,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedMilestoneCategory = null;
                            _selectedMilestoneEvent = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Selected feeling display
              if (_selectedFeeling != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Text(_selectedFeeling!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedFeeling = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Selected music display
              if (_selectedMusic != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      if (_selectedMusic!.imageUrl != null)
                        Image.network(
                          _selectedMusic!.imageUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.music_note, size: 50);
                          },
                        )
                      else
                        const Icon(Icons.music_note, size: 50),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedMusic!.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _selectedMusic!.artist,
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedMusic = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Feature options list
              _FeatureOption(
                icon: Icons.image,
                iconColor: Colors.green,
                label: strings?.postPhotoVideo ?? 'Ảnh/video',
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.photo_library),
                            title: const Text('Chọn ảnh'),
                            onTap: () {
                              Navigator.pop(context);
                              _pickImages();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.video_library),
                            title: const Text('Chọn video'),
                            onTap: () {
                              Navigator.pop(context);
                              _pickVideo();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              _FeatureOption(
                icon: Icons.person_add,
                iconColor: Colors.blue,
                label: strings?.postTagPeople ?? 'Gắn thẻ người khác',
                onTap: _showTagUserDialog,
              ),
              _FeatureOption(
                icon: Icons.sentiment_satisfied,
                iconColor: Colors.yellow,
                label: strings?.postFeelings ?? 'Cảm xúc/hoạt động',
                onTap: _showFeelingDialog,
              ),
              _FeatureOption(
                icon: Icons.location_on,
                iconColor: Colors.red,
                label: 'Check in',
                onTap: _showCheckInDialog,
              ),
              _FeatureOption(icon: Icons.camera_alt, iconColor: Colors.blue, label: 'Camera', onTap: _pickFromCamera),
              _FeatureOption(icon: Icons.gif, iconColor: Colors.teal, label: 'File GIF', onTap: _showGifSearchDialog),
              _FeatureOption(
                icon: Icons.flag,
                iconColor: Colors.blue,
                label: 'Cột mốc',
                onTap: _showMilestoneCategoryDialog,
              ),
              _FeatureOption(
                icon: Icons.music_note,
                iconColor: Colors.orange,
                label: 'Nhạc',
                onTap: _showMusicSearchDialog,
              ),
            ],
          ),
        ),
      ),
          // Progress overlay khi đang upload
          if (_isLoading && _uploadProgress > 0)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_uploadStatus.isNotEmpty) ...[
                          Text(
                            _uploadStatus,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                        ],
                        SizedBox(
                          width: 200,
                          child: LinearProgressIndicator(
                            value: _uploadProgress,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_uploadProgress * 100).toInt()}%',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }
}

class _FeatureOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _FeatureOption({required this.icon, required this.iconColor, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(label),
      onTap: onTap,
    );
  }
}
