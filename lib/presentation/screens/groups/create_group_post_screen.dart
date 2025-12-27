import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import '../../../data/models/post_model.dart';
import '../../../data/models/privacy_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/deezer_service.dart';
import '../../../data/services/location_sharing_service.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/ai_content_service.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/ai_content_assistant_widget.dart';

class CreateGroupPostScreen extends StatefulWidget {
  final GroupModel group;

  const CreateGroupPostScreen({super.key, required this.group});

  @override
  State<CreateGroupPostScreen> createState() => _CreateGroupPostScreenState();
}

class _CreateGroupPostScreenState extends State<CreateGroupPostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  final LocationSharingService _locationService = LocationSharingService();
  final NotificationService _notificationService = NotificationService();
  final ImagePicker _imagePicker = ImagePicker();
  List<XFile> _selectedImages = [];
  XFile? _selectedVideo;
  VideoPlayerController? _videoController;
  bool _isLoading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';
  String? _selectedFeeling;
  String? _selectedLocation;
  DeezerTrack? _selectedMusic;
  List<UserModel> _taggedUsers = [];
  String? _selectedMilestoneCategory;
  String? _selectedMilestoneEvent;
  String? _selectedGifUrl;
  // TODO: Thay YOUR_GIPHY_API_KEY bằng Giphy API key thực tế của bạn
  // Lấy tại: https://developers.giphy.com/dashboard/
  static const String _giphyApiKey = 'YOUR_GIPHY_API_KEY';
  AIContentQuality? _contentQuality;
  bool _isLoadingQuality = false;
  Timer? _qualityDebounceTimer;

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
          _selectedImages = images;
          _selectedVideo = null; // Clear video if images selected
          _videoController?.dispose();
          _videoController = null;
        });
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        setState(() {
          _selectedVideo = video;
          _selectedImages = []; // Clear images if video selected
          _videoController?.dispose();
          _videoController = VideoPlayerController.file(File(video.path))
            ..initialize().then((_) {
              setState(() {});
            });
        });
      }
    } catch (e) {
      debugPrint('Error picking video: $e');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _removeVideo() {
    setState(() {
      _selectedVideo = null;
      _videoController?.dispose();
      _videoController = null;
    });
  }

  void _showFeelingDialog() {
    final feelings = [
      '😊 Vui vẻ',
      '😍 Yêu thích',
      '😮 Ngạc nhiên',
      '😢 Buồn',
      '😡 Tức giận',
      '😴 Buồn ngủ',
      '🤔 Suy nghĩ',
      '😎 Cool',
      '🥳 Party',
      '❤️ Yêu thương',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chọn cảm xúc'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: feelings.map((feeling) {
              final isSelected = _selectedFeeling == feeling;
              return ChoiceChip(
                label: Text(feeling),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedFeeling = selected ? feeling : null;
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _pickLocation() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Kiểm tra và yêu cầu permission
      final hasPermission = await _locationService.requestLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cần quyền truy cập vị trí. Vui lòng cấp quyền trong Settings.'),
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
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Lấy địa chỉ
      String? address;
      try {
        address = await _locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
      } catch (e) {
        address = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      }

      if (mounted) {
        setState(() {
          _selectedLocation = address ?? '${position.latitude}, ${position.longitude}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi lấy vị trí: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showMusicSearchDialog() async {
    final TextEditingController searchController = TextEditingController();
    final DeezerService deezerService = DeezerService();
    List<DeezerTrack> tracks = [];
    bool isSearching = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tìm nhạc'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Tìm kiếm bài hát...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (query) async {
                    if (query.trim().isEmpty) return;
                    setDialogState(() {
                      isSearching = true;
                    });
                    try {
                      final results = await deezerService.searchTracks(query);
                      setDialogState(() {
                        tracks = results;
                        isSearching = false;
                      });
                    } catch (e) {
                      setDialogState(() {
                        isSearching = false;
                      });
                      debugPrint('Error searching music: $e');
                    }
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : tracks.isEmpty
                          ? const Center(child: Text('Nhập từ khóa để tìm kiếm'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: tracks.length,
                              itemBuilder: (context, index) {
                                final track = tracks[index];
                                return ListTile(
                                  leading: track.imageUrl != null
                                      ? Image.network(track.imageUrl!, width: 50, height: 50, fit: BoxFit.cover)
                                      : const Icon(Icons.music_note),
                                  title: Text(track.name),
                                  subtitle: Text(track.artist),
                                  onTap: () {
                                    setState(() {
                                      _selectedMusic = track;
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
          ],
        ),
      ),
    );
    searchController.dispose();
  }

  Future<void> _showGifPicker() async {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> gifs = [];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tìm GIF'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Tìm kiếm GIF...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (query) async {
                    if (query.trim().isEmpty) return;
                    try {
                      final response = await http.get(
                        Uri.parse('https://api.giphy.com/v1/gifs/search?api_key=$_giphyApiKey&q=$query&limit=20'),
                      );
                      if (response.statusCode == 200) {
                        final data = json.decode(response.body) as Map<String, dynamic>;
                        setDialogState(() {
                          gifs = List<Map<String, dynamic>>.from(data['data'] ?? []);
                        });
                      }
                    } catch (e) {
                      debugPrint('Error searching GIF: $e');
                    }
                  },
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: gifs.isEmpty
                      ? const Text('Nhập từ khóa để tìm kiếm')
                      : GridView.builder(
                          shrinkWrap: true,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1,
                          ),
                          itemCount: gifs.length,
                          itemBuilder: (context, index) {
                            final gif = gifs[index];
                            final gifUrl = gif['images']['fixed_height']['url'] as String;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedGifUrl = gifUrl;
                                });
                                Navigator.pop(context);
                              },
                              child: Image.network(gifUrl, fit: BoxFit.cover),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createPost() async {
    if (!_formKey.currentState!.validate()) return;

    final content = _contentController.text.trim();
    if (content.isEmpty &&
        _selectedImages.isEmpty &&
        _selectedVideo == null &&
        _selectedGifUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập nội dung hoặc chọn ảnh/video')),
      );
      return;
    }

    // AI Content Moderation - kiểm tra nội dung trước khi đăng
    if (content.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _uploadStatus = 'Đang kiểm tra nội dung...';
      });

      try {
        final aiService = AIContentService();
        final moderation = await aiService.moderateContent(content);
        
        if (moderation.isSpam || moderation.isToxic) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(moderation.reason ?? 'Nội dung không phù hợp'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('Error moderating content: $e');
        // Tiếp tục đăng bài nếu moderation lỗi
      }
    }

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
      _uploadProgress = 0.0;
      _uploadStatus = 'Đang tạo bài viết...';
    });

    try {
      String? postId;

      if (_selectedVideo != null) {
        setState(() {
          _uploadStatus = 'Đang upload video...';
        });

        final videoFile = File(_selectedVideo!.path);
        final videoUrl = await _storageService.uploadVideo(videoFile, 'posts');
        setState(() {
          _uploadProgress = 0.8;
        });

        final post = PostModel(
          id: '',
          userId: currentUser.id,
          content: content,
          privacy: PrivacyType.public, // Chỉ có công khai cho nhóm
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
          groupId: widget.group.id, // Gán groupId
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        postId = await _firestoreService.createPost(post);
      } else if (_selectedImages.isNotEmpty) {
        setState(() {
          _uploadStatus = 'Đang upload ảnh...';
        });

        final tempPost = PostModel(
          id: '',
          userId: currentUser.id,
          content: content,
          privacy: PrivacyType.public,
          location: _selectedLocation,
          musicTrackId: _selectedMusic?.id,
          musicName: _selectedMusic?.name,
          musicArtist: _selectedMusic?.artist,
          musicPreviewUrl: _selectedMusic?.previewUrl,
          musicImageUrl: _selectedMusic?.imageUrl,
          musicExternalUrl: _selectedMusic?.externalUrl,
          groupId: widget.group.id,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        postId = await _firestoreService.createPost(tempPost);
        if (postId.isEmpty) {
          throw Exception('Không thể tạo bài viết');
        }

        final imageUrls = <String>[];
        for (int i = 0; i < _selectedImages.length; i++) {
          setState(() {
            _uploadProgress = 0.3 + (i / _selectedImages.length) * 0.5;
            _uploadStatus = 'Đang upload ảnh ${i + 1}/${_selectedImages.length}...';
          });

          final imageFile = File(_selectedImages[i].path);
          final imageUrl = await _storageService.uploadPostImage(
            imageFile,
            postId,
            i,
          );
          imageUrls.add(imageUrl);
        }

        final updatedPost = PostModel(
          id: postId,
          userId: currentUser.id,
          content: content,
          privacy: PrivacyType.public,
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
          groupId: widget.group.id,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await _firestoreService.updatePost(updatedPost);
      } else {
        final post = PostModel(
          id: '',
          userId: currentUser.id,
          content: content,
          privacy: PrivacyType.public, // Chỉ có công khai cho nhóm
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
          groupId: widget.group.id, // Gán groupId
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        postId = await _firestoreService.createPost(post);
      }

      // Gửi notification cho các user được gắn thẻ
      if (postId.isNotEmpty && _taggedUsers.isNotEmpty) {
        _sendTagNotifications(postId, currentUser.id).catchError((e) {
          debugPrint('Error sending tag notifications: $e');
        });
      }

      if (mounted) {
        setState(() {
          _uploadProgress = 1.0;
          _uploadStatus = 'Hoàn thành!';
        });

        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã đăng bài thành công!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi đăng bài: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendTagNotifications(String postId, String currentUserId) async {
    for (final taggedUser in _taggedUsers) {
      try {
        await _notificationService.createNotification(
          NotificationModel(
            id: '',
            userId: taggedUser.id,
            actorId: currentUserId,
            type: NotificationType.mention, // Dùng mention type cho tag
            postId: postId,
            createdAt: DateTime.now(),
          ),
        );
      } catch (e) {
        debugPrint('Error sending tag notification: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Đăng bài trong ${widget.group.name}',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: _uploadProgress,
                ),
              ),
            )
          else
            TextButton(
              onPressed: _createPost,
              child: const Text(
                'Đăng',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
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
                  // User profile
                  if (currentUser != null) ...[
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage: currentUser.avatarUrl != null
                              ? NetworkImage(currentUser.avatarUrl!)
                              : null,
                          child: currentUser.avatarUrl == null
                              ? Text(
                                  currentUser.fullName.isNotEmpty
                                      ? currentUser.fullName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(color: Colors.black),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentUser.fullName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.public, size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Công khai',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
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
                      hintText: 'Bạn đang nghĩ gì?',
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
                      setState(() {});
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
                      imageUrl: _selectedImages.isNotEmpty
                          ? _selectedImages.first.path
                          : null,
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
                                          ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 200,
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: Icon(Icons.error, size: 50),
                                  ),
                                );
                              },
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
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

                  // Selected images
                  if (_selectedImages.isNotEmpty)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            Image.file(
                              File(_selectedImages[index].path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () => _removeImage(index),
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                  // Selected video
                  if (_selectedVideo != null && _videoController != null)
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: _removeVideo,
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // Action buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildActionButton(
                        icon: Icons.photo_library,
                        label: 'Ảnh',
                        onTap: _pickImages,
                      ),
                      _buildActionButton(
                        icon: Icons.video_library,
                        label: 'Video',
                        onTap: _pickVideo,
                      ),
                      _buildActionButton(
                        icon: Icons.emoji_emotions_outlined,
                        label: _selectedFeeling ?? 'Cảm xúc',
                        onTap: _showFeelingDialog,
                        isSelected: _selectedFeeling != null,
                      ),
                      _buildActionButton(
                        icon: Icons.location_on,
                        label: _selectedLocation != null ? 'Đã chọn' : 'Vị trí',
                        onTap: _pickLocation,
                        isSelected: _selectedLocation != null,
                      ),
                      _buildActionButton(
                        icon: Icons.music_note,
                        label: _selectedMusic != null ? 'Đã chọn' : 'Nhạc',
                        onTap: _showMusicSearchDialog,
                        isSelected: _selectedMusic != null,
                      ),
                      _buildActionButton(
                        icon: Icons.gif_box,
                        label: 'GIF',
                        onTap: _showGifPicker,
                        isSelected: _selectedGifUrl != null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading && _uploadStatus.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.black87,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: _uploadProgress),
                    const SizedBox(height: 8),
                    Text(
                      _uploadStatus,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: isSelected ? Colors.blue : Colors.black87),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? Colors.blue : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

