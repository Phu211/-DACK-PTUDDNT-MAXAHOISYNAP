import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../../../flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/models/story_model.dart';
import '../../../data/models/story_element_model.dart';
import '../../../data/models/privacy_model.dart';
import '../../../data/models/story_privacy_settings.dart';
import '../../../data/services/story_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/deezer_service.dart';
import '../../../data/services/user_settings_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/story_editors/story_editors.dart';
import 'story_privacy_screen.dart';
import 'story_edit_screen.dart';
import '../../../core/utils/error_message_helper.dart';

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final StoryService _storyService = StoryService();
  final StorageService _storageService = StorageService();
  final DeezerService _spotifyService = DeezerService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  File? _selectedImage;
  File? _selectedVideo;
  DeezerTrack? _selectedMusic;
  VideoPlayerController? _videoController;
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;
  PrivacyType _selectedPrivacy = PrivacyType.public;
  List<String> _hiddenUsers = []; // Danh sách user IDs bị ẩn story
  List<String> _allowedUsers = []; // Danh sách user IDs được phép xem (Close Friends)
  String _selectedMenuOption = 'new'; // internal key, text from localization

  // Video options
  bool _isVideoLoop = false; // Loop video
  bool _isVideoMuted = false; // Mute video audio
  int _imageRotation = 0; // Rotation angle: 0, 90, 180, 270

  // Story options
  bool _aiLabelEnabled = false; // AI label toggle
  bool _shouldSaveStory = false; // Save story to saved stories

  // Story elements
  List<StorySticker> _stickers = [];
  List<StoryTextOverlay> _textOverlays = [];
  List<StoryDrawing> _drawings = [];
  List<StoryMention> _mentions = [];
  StoryLink? _link;
  String? _selectedEffect;

  // Offset cho mỗi drawing để có thể di chuyển
  final Map<int, Offset> _drawingOffsets = {};
  // Lưu containerSize thực tế để tính offset chính xác
  Size? _previewContainerSize;

  // Web-only preview data
  Uint8List? _webImageBytes;
  bool _isWebVideo = false;

  @override
  void dispose() {
    _textController.dispose();
    _videoController?.dispose();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Cho phép chọn **một file ảnh hoặc video** từ máy,
  /// dựa vào đuôi file để phân biệt ảnh / video.
  Future<void> _pickMedia() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media, // hỗ trợ cả image + video
        allowMultiple: false,
        withData: kIsWeb,
      );

      if (result == null || result.files.single.path == null) return;

      final file = result.files.single;
      final path = file.path;
      final ext = (file.extension ?? '').toLowerCase(); // ví dụ: jpg, png, mp4, mov...

      // Reset web preview flags
      _webImageBytes = null;
      _isWebVideo = false;

      // Giải phóng video cũ nếu có (mobile/desktop)
      _videoController?.dispose();

      // Một số đuôi phổ biến của video
      const videoExts = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'];

      if (videoExts.contains(ext)) {
        if (kIsWeb) {
          // Trên web, tạm thời không preview video, chỉ hiển thị thông báo
          setState(() {
            _selectedImage = null;
            _selectedVideo = null;
            _videoController = null;
            _isWebVideo = true;
          });
          return;
        }

        // Xử lý như video
        final newVideo = File(path!);
        final controller = VideoPlayerController.file(newVideo);
        await controller.initialize();
        controller.setLooping(_isVideoLoop); // Set loop option
        // Nếu đã có nhạc được chọn, tắt tiếng video để tránh chồng lên nhau
        // Nếu không có nhạc, áp dụng trạng thái mute của người dùng
        if (_selectedMusic != null) {
          controller.setVolume(0.0);
        } else {
          controller.setVolume(_isVideoMuted ? 0.0 : 1.0);
        }
        if (mounted) {
          setState(() {
            _selectedVideo = newVideo;
            _selectedImage = null;
            _videoController = controller;
          });
          _videoController!.play();
        } else {
          controller.dispose();
        }
      } else {
        if (kIsWeb) {
          // Trên web dùng bytes để hiển thị preview
          if (file.bytes != null) {
            setState(() {
              _webImageBytes = file.bytes;
              _selectedImage = null;
              _selectedVideo = null;
              _videoController = null;
              _isWebVideo = false;
            });
          }
        } else {
          // Mặc định coi là ảnh (mobile/desktop)
          setState(() {
            _selectedImage = File(path!);
            _selectedVideo = null;
            _videoController = null;
            _isWebVideo = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e, defaultMessage: 'Không thể chọn file'));
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        _videoController?.dispose();
        setState(() {
          _selectedImage = File(image.path);
          _selectedVideo = null;
          _videoController = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e, defaultMessage: 'Không thể chọn ảnh'));
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final video = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        _videoController?.dispose();
        final newVideo = File(video.path);
        final controller = VideoPlayerController.file(newVideo);
        await controller.initialize();
        controller.setLooping(_isVideoLoop); // Set loop option
        // Nếu đã có nhạc được chọn, tắt tiếng video để tránh chồng lên nhau
        // Nếu không có nhạc, áp dụng trạng thái mute của người dùng
        if (_selectedMusic != null) {
          controller.setVolume(0.0);
        } else {
          controller.setVolume(_isVideoMuted ? 0.0 : 1.0);
        }
        if (mounted) {
          setState(() {
            _selectedVideo = newVideo;
            _selectedImage = null;
            _videoController = controller;
          });
          _videoController!.play();
        } else {
          controller.dispose();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e, defaultMessage: 'Không thể chọn video'));
      }
    }
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
                        'Chọn nhạc từ Deezer',
                        style: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black87),
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
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'Nhập tên bài hát hoặc nghệ sĩ...',
                            hintStyle: const TextStyle(color: Colors.grey),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search, color: Colors.grey),
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
                                      SnackBar(
                                        content: Text(
                                          ErrorMessageHelper.getErrorMessage(e, defaultMessage: 'Không thể tìm kiếm'),
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
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
                        const SizedBox(height: 12),
                        if (!suggestionsLoaded) ...[
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
                          const Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator())
                        else
                          Expanded(
                            child: ListView.builder(
                              itemCount: searchResults.length,
                              itemBuilder: (context, index) {
                                final track = searchResults[index];
                                final hasPreview = track.previewUrl != null && track.previewUrl!.isNotEmpty;
                                return ListTile(
                                  leading: track.imageUrl != null
                                      ? Image.network(track.imageUrl!, width: 40, height: 40, fit: BoxFit.cover)
                                      : const Icon(Icons.music_note, color: Colors.grey),
                                  title: Text(track.name, style: const TextStyle(color: Colors.black87)),
                                  subtitle: Text(track.artist, style: const TextStyle(color: Colors.grey)),
                                  trailing: hasPreview
                                      ? const Text('Nghe 30s', style: TextStyle(color: Colors.green, fontSize: 11))
                                      : const Text('Không có demo', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  onTap: () async {
                                    // Dừng nhạc cũ nếu có
                                    await _audioPlayer.stop();

                                    setState(() {
                                      _selectedMusic = track;
                                      // Khi chọn nhạc, tự động tắt tiếng video
                                      _isVideoMuted = true;
                                    });

                                    // Tắt tiếng video nếu có video được chọn để tránh chồng lên nhau
                                    if (_videoController != null && _videoController!.value.isInitialized) {
                                      _videoController!.setVolume(0.0);
                                    }

                                    // Phát nhạc ngay nếu có preview
                                    if (hasPreview && track.previewUrl != null) {
                                      try {
                                        await _audioPlayer.play(UrlSource(track.previewUrl!));
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(SnackBar(content: Text('Không thể phát nhạc: $e')));
                                        }
                                      }
                                    } else {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Bài này không có đoạn nhạc 30s, story sẽ chỉ hiển thị tên nhạc.',
                                            ),
                                          ),
                                        );
                                      }
                                    }

                                    if (mounted) {
                                      Navigator.pop(context);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
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

  void _showPrivacySettings() async {
    final result = await Navigator.of(context).push<StoryPrivacySettings>(
      MaterialPageRoute(
        builder: (context) => StoryPrivacyScreen(
          initialPrivacy: _selectedPrivacy,
          initialHiddenUsers: List.from(_hiddenUsers), // Tạo copy để đảm bảo không bị thay đổi
          initialAllowedUsers: List.from(_allowedUsers), // Tạo copy để đảm bảo không bị thay đổi
        ),
      ),
    );
    if (result != null) {
      debugPrint(
        'CreateStoryScreen: Received privacy settings - privacy: ${result.privacy}, hiddenUsers: ${result.hiddenUsers.length}, allowedUsers: ${result.allowedUsers.length}',
      );
      setState(() {
        _selectedPrivacy = result.privacy;
        _hiddenUsers = List.from(result.hiddenUsers); // Tạo copy mới
        _allowedUsers = List.from(result.allowedUsers); // Tạo copy mới
      });
      debugPrint(
        'CreateStoryScreen: Updated state - _hiddenUsers: ${_hiddenUsers.length}, _allowedUsers: ${_allowedUsers.length}',
      );
    } else {
      debugPrint('CreateStoryScreen: Privacy settings result is null');
    }
  }

  void _showStickerPicker() {
    if (_selectedImage == null && _webImageBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh trước khi thêm nhãn dán')));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => StickerPicker(
        onStickerSelected: (sticker) {
          setState(() {
            _stickers.add(sticker);
          });
          debugPrint('Sticker added: ${sticker.emoji}, total: ${_stickers.length}');
        },
      ),
    );
  }

  void _showTextOverlayEditor() {
    if (_selectedImage == null && _webImageBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh trước khi thêm văn bản')));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => TextOverlayEditor(
        onTextAdded: (textOverlay) {
          setState(() {
            _textOverlays.add(textOverlay);
          });
          debugPrint('Text overlay added: ${textOverlay.text}, total: ${_textOverlays.length}');
        },
      ),
    );
  }

  void _showDrawingEditor() {
    if (_selectedImage == null && _webImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh trước khi vẽ')));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => DrawingEditor(
        onDrawingComplete: (drawing) {
          setState(() {
            _drawings.add(drawing);
            // Offset mặc định là 0 cho drawing mới
            _drawingOffsets[_drawings.length - 1] = Offset.zero;
          });
          debugPrint('Drawing added, total: ${_drawings.length}');
        },
      ),
    );
  }

  void _showMentionPicker() {
    if (_selectedImage == null && _webImageBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh trước khi thêm nhắc đến')));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => MentionPicker(
        onMentionSelected: (mention) {
          setState(() {
            _mentions.add(mention);
          });
          debugPrint('Mention added: ${mention.userName}, total: ${_mentions.length}');
        },
      ),
    );
  }

  void _showLinkEditor() {
    showModalBottomSheet(
      context: context,
      builder: (context) => LinkEditor(
        onLinkAdded: (link) {
          setState(() {
            _link = link;
          });
        },
      ),
    );
  }

  void _showEffectPicker() {
    if (_selectedImage == null && _webImageBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh trước khi thêm hiệu ứng')));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => EffectPicker(
        onEffectSelected: (effect) {
          setState(() {
            _selectedEffect = effect;
          });
          debugPrint('Effect selected: $effect');
        },
      ),
    );
  }

  // Build effect filter widget
  Widget _buildEffectFilter(String effect, Widget child) {
    switch (effect) {
      case 'black_white':
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        );
      case 'blur':
        return BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5), child: child);
      case 'bright':
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([1.2, 0, 0, 0, 0, 0, 1.2, 0, 0, 0, 0, 0, 1.2, 0, 0, 0, 0, 0, 1, 0]),
          child: child,
        );
      case 'dark':
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([0.7, 0, 0, 0, 0, 0, 0.7, 0, 0, 0, 0, 0, 0.7, 0, 0, 0, 0, 0, 1, 0]),
          child: child,
        );
      case 'saturated':
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([1.5, 0, 0, 0, 0, 0, 1.5, 0, 0, 0, 0, 0, 1.5, 0, 0, 0, 0, 0, 1, 0]),
          child: child,
        );
      case 'vintage':
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.9,
            0.5,
            0.1,
            0,
            0,
            0.3,
            0.8,
            0.1,
            0,
            0,
            0.2,
            0.3,
            0.5,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        );
      case 'sepia':
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.393,
            0.769,
            0.189,
            0,
            0,
            0.349,
            0.686,
            0.168,
            0,
            0,
            0.272,
            0.534,
            0.131,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        );
      default:
        return child;
    }
  }

  // Toggle video loop
  void _toggleVideoLoop() {
    setState(() {
      _isVideoLoop = !_isVideoLoop;
    });
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.setLooping(_isVideoLoop);
    }
  }

  // Toggle video mute
  void _toggleVideoMute() {
    setState(() {
      _isVideoMuted = !_isVideoMuted;
    });
    if (_videoController != null && _videoController!.value.isInitialized) {
      // Nếu có nhạc được chọn, luôn tắt tiếng video
      // Nếu không có nhạc, áp dụng trạng thái mute của người dùng
      if (_selectedMusic != null) {
        _videoController!.setVolume(0.0);
      } else {
        _videoController!.setVolume(_isVideoMuted ? 0.0 : 1.0);
      }
    }
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Loop video option
            if (_selectedVideo != null) ...[
              ListTile(
                leading: const Icon(Icons.loop),
                title: const Text('Lặp video'),
                trailing: Switch(
                  value: _isVideoLoop,
                  onChanged: (_) {
                    Navigator.pop(context);
                    _toggleVideoLoop();
                  },
                ),
              ),
              // Mute video option (chỉ hiển thị khi không có nhạc, vì nếu có nhạc thì tự động tắt tiếng)
              if (_selectedMusic == null)
                ListTile(
                  leading: Icon(_isVideoMuted ? Icons.volume_off : Icons.volume_up),
                  title: const Text('Tắt tiếng video'),
                  trailing: Switch(
                    value: _isVideoMuted,
                    onChanged: (_) {
                      Navigator.pop(context);
                      _toggleVideoMute();
                    },
                  ),
                ),
            ],
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Quyền riêng tư'),
              onTap: () {
                Navigator.pop(context);
                _showPrivacySettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Lưu'),
              subtitle: const Text('Lưu story vào bộ sưu tập của bạn'),
              trailing: Switch(
                value: _shouldSaveStory,
                onChanged: (value) {
                  setState(() {
                    _shouldSaveStory = value;
                  });
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Thêm nhãn AI'),
              subtitle: const Text(
                'Chúng tôi yêu cầu bạn gắn nhãn cho một số nội dung nhất định tạo bằng AI và cảm giác như thật. Tìm hiểu thêm',
              ),
              trailing: Switch(
                value: _aiLabelEnabled,
                onChanged: (value) async {
                  setState(() {
                    _aiLabelEnabled = value;
                  });
                  // Save AI label preference to user settings
                  try {
                    final authProvider = context.read<AuthProvider>();
                    final currentUser = authProvider.currentUser;
                    if (currentUser != null) {
                      final userSettingsService = UserSettingsService();
                      await userSettingsService.updateFields(currentUser.id, {'aiLabelEnabled': value});
                    }
                  } catch (e) {
                    if (kDebugMode) {
                      debugPrint('Error saving AI label setting: $e');
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createStory() async {
    final hasWebImage = kIsWeb && _webImageBytes != null;

    if (_selectedImage == null && _selectedVideo == null && !hasWebImage && _textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh/video hoặc nhập text')));
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String? imageUrl;
      String? videoUrl;
      String? musicUrl;

      if (_selectedImage != null || hasWebImage) {
        if (kIsWeb && hasWebImage) {
          imageUrl = await _storageService.uploadPostImageBytes(_webImageBytes!);
        } else if (_selectedImage != null) {
          imageUrl = await _storageService.uploadPostImage(_selectedImage!, 'story_${currentUser.id}', 0);
        }
      }

      if (_selectedVideo != null) {
        videoUrl = await _storageService.uploadVideo(_selectedVideo!, currentUser.id);
      }

      if (_selectedMusic != null) {
        // Deezer cung cấp preview ~30s, nhưng link có thể hết hạn
        // => tải preview và re-upload lên Cloudinary để dùng link bền vững
        final previewUrl = _selectedMusic!.previewUrl;
        if (previewUrl != null && previewUrl.isNotEmpty) {
          musicUrl = previewUrl;

          if (!kIsWeb) {
            try {
              final response = await http.get(Uri.parse(previewUrl));
              if (response.statusCode == 200) {
                final tempDir = await getTemporaryDirectory();
                final tempFile = File('${tempDir.path}/story_music_${DateTime.now().millisecondsSinceEpoch}.mp3');
                await tempFile.writeAsBytes(response.bodyBytes);

                musicUrl = await _storageService.uploadMusic(tempFile, currentUser.id);

                // Dọn temp file sau khi upload
                try {
                  await tempFile.delete();
                } catch (_) {}
              } else {
                debugPrint('Không tải được preview nhạc: ${response.statusCode}');
              }
            } catch (e) {
              debugPrint('Lỗi tải/upload nhạc preview: $e');
              // Giữ nguyên previewUrl để vẫn có nhạc nếu còn hạn
            }
          }
        }
      }

      debugPrint('Creating story with:');
      debugPrint('  - Privacy: $_selectedPrivacy');
      debugPrint('  - Hidden users: ${_hiddenUsers.length} - $_hiddenUsers');
      debugPrint('  - Allowed users: ${_allowedUsers.length} - $_allowedUsers');
      debugPrint('  - Stickers: ${_stickers.length}');
      debugPrint('  - Text overlays: ${_textOverlays.length}');
      debugPrint('  - Drawings: ${_drawings.length}');
      debugPrint('  - Mentions: ${_mentions.length}');
      debugPrint('  - Effect: $_selectedEffect');

      // Áp dụng offset vào points của drawings trước khi lưu
      final adjustedDrawings = _drawings.asMap().entries.map((entry) {
        final index = entry.key;
        final drawing = entry.value;
        final offset = _drawingOffsets[index];

        if (offset == null || offset == Offset.zero) {
          return drawing;
        }

        // Sử dụng containerSize thực tế nếu có, nếu không thì dùng MediaQuery size
        final containerSize = _previewContainerSize ?? MediaQuery.of(context).size;
        final offsetX = offset.dx / containerSize.width;
        final offsetY = offset.dy / containerSize.height;

        // Tạo points mới với offset đã áp dụng
        final adjustedPoints = drawing.points.map((point) {
          return DrawingPoint(x: (point.x + offsetX).clamp(0.0, 1.0), y: (point.y + offsetY).clamp(0.0, 1.0));
        }).toList();

        return StoryDrawing(points: adjustedPoints, color: drawing.color, strokeWidth: drawing.strokeWidth);
      }).toList();

      final story = StoryModel(
        id: '',
        userId: currentUser.id,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        text: _textController.text.trim().isEmpty ? null : _textController.text.trim(),
        musicUrl: musicUrl,
        musicName: _selectedMusic?.name,
        privacy: _selectedPrivacy,
        hiddenUsers: _hiddenUsers,
        allowedUsers: _allowedUsers,
        stickers: _stickers,
        textOverlays: _textOverlays,
        drawings: adjustedDrawings,
        mentions: _mentions,
        link: _link,
        effect: _selectedEffect,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      final storyId = await _storyService.createStory(story);
      debugPrint('Story created successfully with id: $storyId');

      // Save story to saved stories if user wants to save
      if (_shouldSaveStory) {
        try {
          final authProvider = context.read<AuthProvider>();
          final currentUser = authProvider.currentUser;
          if (currentUser != null) {
            await _storyService.saveStory(storyId, currentUser.id);
            debugPrint('Story saved to saved stories');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error saving story: $e');
          }
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã tạo story thành công!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e, defaultMessage: 'Không thể tạo story'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildRightMenu() {
    final strings = AppLocalizations.of(context);
    final menuItems = [
      {'key': 'new', 'icon': Icons.add_circle_outline},
      {'key': 'stickers', 'icon': Icons.emoji_emotions},
      {'key': 'text', 'icon': Icons.text_fields},
      {'key': 'music', 'icon': Icons.music_note},
      {'key': 'effects', 'icon': Icons.auto_awesome},
      {'key': 'mention', 'icon': Icons.alternate_email},
      {'name': 'Vẽ', 'icon': Icons.edit},
      {'name': 'Liên kết', 'icon': Icons.link},
    ];

    return Container(
      width: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Colors.grey.withOpacity(0.6), Colors.grey.withOpacity(0.3), Colors.transparent],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: menuItems.map((item) {
          final key = (item['key'] ?? item['name']) as String;
          final isSelected = _selectedMenuOption == key;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedMenuOption = key;
              });
              // Handle menu item selection
              switch (key) {
                case 'music':
                  _showMusicSearchDialog();
                  break;
                case 'stickers':
                  _showStickerPicker();
                  break;
                case 'text':
                  _showTextOverlayEditor();
                  break;
                case 'effects':
                  _showEffectPicker();
                  break;
                case 'mention':
                  _showMentionPicker();
                  break;
                case 'Vẽ':
                  _showDrawingEditor();
                  break;
                case 'Liên kết':
                  _showLinkEditor();
                  break;
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue.withOpacity(0.8) : Colors.grey.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.white.withOpacity(0.3),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item['icon'] as IconData, color: Colors.black, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    () {
                      switch (key) {
                        case 'new':
                          return strings?.storyNew ?? 'Mới';
                        case 'stickers':
                          return strings?.storyStickers ?? 'Nhãn dán';
                        case 'text':
                          return strings?.storyTextTool ?? 'Văn bản';
                        case 'music':
                          return strings?.storyMusic ?? 'Nhạc';
                        case 'effects':
                          return strings?.storyEffects ?? 'Hiệu ứng';
                        case 'mention':
                          return strings?.storyMention ?? 'Nhắc đến';
                        default:
                          return (item['name'] as String?) ?? '';
                      }
                    }(),
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.grey.withOpacity(0.7), Colors.grey.withOpacity(0.3), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.black, size: 20),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                  ),
                  if (currentUser != null) ...[
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: currentUser.avatarUrl != null ? NetworkImage(currentUser.avatarUrl!) : null,
                      child: currentUser.avatarUrl == null ? Text(currentUser.fullName[0].toUpperCase()) : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentUser.fullName,
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                          if (_selectedMusic != null)
                            Text(
                              'Nhạc gợi ý: ${_selectedMusic!.name}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    // Nút đổi ảnh khi đã chọn ảnh
                    if (_selectedImage != null || _webImageBytes != null)
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), shape: BoxShape.circle),
                          child: const Icon(Icons.image, color: Colors.black, size: 20),
                        ),
                        tooltip: 'Đổi ảnh',
                        onPressed: () async {
                          // Xóa ảnh cũ và các elements
                          setState(() {
                            _selectedImage = null;
                            _webImageBytes = null;
                            _stickers = [];
                            _textOverlays = [];
                            _drawings = [];
                            _mentions = [];
                            _link = null;
                            _selectedEffect = null;
                            _imageRotation = 0;
                          });
                          // Chọn ảnh mới
                          await _pickMedia();
                        },
                        padding: EdgeInsets.zero,
                      ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), shape: BoxShape.circle),
                        child: const Icon(Icons.edit, color: Colors.black, size: 20),
                      ),
                      tooltip: 'Chỉnh sửa',
                      onPressed: () async {
                        if (_selectedImage == null && _webImageBytes == null) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh trước')));
                          return;
                        }

                        final result = await Navigator.of(context).push<Map<String, dynamic>>(
                          MaterialPageRoute(
                            builder: (_) => StoryEditScreen(
                              imageFile: _selectedImage,
                              webImageBytes: _webImageBytes,
                              initialRotation: _imageRotation,
                              initialStickers: _stickers,
                              initialTextOverlays: _textOverlays,
                              initialDrawings: _drawings,
                              initialMentions: _mentions,
                              initialLink: _link,
                              initialEffect: _selectedEffect,
                            ),
                          ),
                        );

                        if (result != null) {
                          setState(() {
                            _selectedImage = result['imageFile'] as File?;
                            _webImageBytes = result['webImageBytes'] as Uint8List?;
                            _imageRotation = result['rotation'] as int? ?? 0;
                            _stickers = result['stickers'] as List<StorySticker>? ?? [];
                            _textOverlays = result['textOverlays'] as List<StoryTextOverlay>? ?? [];
                            _drawings = result['drawings'] as List<StoryDrawing>? ?? [];
                            _mentions = result['mentions'] as List<StoryMention>? ?? [];
                            _link = result['link'] as StoryLink?;
                            _selectedEffect = result['effect'] as String?;
                            // Reset offsets vì drawings đã được điều chỉnh
                            _drawingOffsets.clear();
                          });
                        }
                      },
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),

            // Main content area
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      // Media preview
                      Center(
                        child: _selectedImage != null
                            ? Transform.rotate(
                                angle: _imageRotation * 3.14159 / 180, // Convert to radians
                                child: _selectedEffect != null && _selectedEffect!.isNotEmpty
                                    ? _buildEffectFilter(
                                        _selectedEffect!,
                                        Image.file(_selectedImage!, fit: BoxFit.contain),
                                      )
                                    : Image.file(_selectedImage!, fit: BoxFit.contain),
                              )
                            : _webImageBytes != null
                            ? Transform.rotate(
                                angle: _imageRotation * 3.14159 / 180,
                                child: _selectedEffect != null && _selectedEffect!.isNotEmpty
                                    ? _buildEffectFilter(
                                        _selectedEffect!,
                                        Image.memory(_webImageBytes!, fit: BoxFit.contain),
                                      )
                                    : Image.memory(_webImageBytes!, fit: BoxFit.contain),
                              )
                            : _selectedVideo != null && _videoController != null
                            ? _videoController!.value.isInitialized
                                  ? Stack(
                                      children: [
                                        AspectRatio(
                                          aspectRatio: _videoController!.value.aspectRatio,
                                          child: VideoPlayer(_videoController!),
                                        ),
                                        // Hiển thị indicator nếu video đang loop
                                        if (_isVideoLoop)
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.loop, color: Colors.black, size: 16),
                                                  SizedBox(width: 4),
                                                  Text('Loop', style: TextStyle(color: Colors.black, fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    )
                                  : const CircularProgressIndicator()
                            : _isWebVideo
                            ? const Text(
                                'Xem trước video chưa được hỗ trợ trên web',
                                style: TextStyle(color: Colors.black87),
                              )
                            : Container(
                                color: Colors.black26,
                                child: Center(
                                  child: ElevatedButton.icon(
                                    onPressed: _pickMedia,
                                    icon: const Icon(Icons.perm_media),
                                    label: Text(AppLocalizations.of(context)?.storyChooseMedia ?? 'Chọn ảnh / video'),
                                  ),
                                ),
                              ),
                      ),

                      // Drawings overlay - có thể di chuyển được
                      if (_drawings.isNotEmpty && (_selectedImage != null || _webImageBytes != null))
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Stack(
                                children: [
                                  // Vẽ tất cả drawings với offset
                                  CustomPaint(
                                    painter: _StoryDrawingPainter(
                                      drawings: _drawings,
                                      offsets: _drawingOffsets,
                                      containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                                    ),
                                    child: Container(),
                                  ),
                                  // Lưu containerSize để sử dụng khi lưu
                                  Builder(
                                    builder: (context) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (_previewContainerSize !=
                                            Size(constraints.maxWidth, constraints.maxHeight)) {
                                          setState(() {
                                            _previewContainerSize = Size(constraints.maxWidth, constraints.maxHeight);
                                          });
                                        }
                                      });
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                  // Overlay để di chuyển và xóa từng drawing
                                  ..._drawings.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final drawing = entry.value;
                                    if (drawing.points.isEmpty) return const SizedBox.shrink();

                                    // Tính bounding box của drawing (không có offset)
                                    double minX = double.infinity;
                                    double maxX = double.negativeInfinity;
                                    double minY = double.infinity;
                                    double maxY = double.negativeInfinity;

                                    for (final point in drawing.points) {
                                      final x = point.x * constraints.maxWidth;
                                      final y = point.y * constraints.maxHeight;
                                      minX = minX < x ? minX : x;
                                      maxX = maxX > x ? maxX : x;
                                      minY = minY < y ? minY : y;
                                      maxY = maxY > y ? maxY : y;
                                    }

                                    final offset = _drawingOffsets[index] ?? Offset.zero;
                                    final centerX = (minX + maxX) / 2;
                                    final centerY = (minY + maxY) / 2;
                                    final width = maxX - minX;
                                    final height = maxY - minY;

                                    return _DraggableDrawingWidget(
                                      key: ValueKey('drawing_$index'),
                                      index: index,
                                      left: minX + offset.dx,
                                      top: minY + offset.dy,
                                      width: width,
                                      height: height,
                                      centerX: centerX + offset.dx,
                                      centerY: centerY + offset.dy,
                                      currentOffset: offset,
                                      onOffsetUpdate: (newOffset) {
                                        setState(() {
                                          _drawingOffsets[index] = newOffset;
                                        });
                                      },
                                      onDelete: () {
                                        setState(() {
                                          _drawings.removeAt(index);
                                          // Xóa offset và rebuild map cho các drawings sau
                                          _drawingOffsets.remove(index);
                                          // Rebuild offsets map với index mới
                                          final newOffsets = <int, Offset>{};
                                          for (int i = 0; i < _drawings.length; i++) {
                                            if (i < index) {
                                              // Giữ nguyên offset cho drawings trước
                                              if (_drawingOffsets.containsKey(i)) {
                                                newOffsets[i] = _drawingOffsets[i]!;
                                              }
                                            } else {
                                              // Di chuyển offset của drawings sau lên 1 index
                                              if (_drawingOffsets.containsKey(i + 1)) {
                                                newOffsets[i] = _drawingOffsets[i + 1]!;
                                              }
                                            }
                                          }
                                          _drawingOffsets.clear();
                                          _drawingOffsets.addAll(newOffsets);
                                        });
                                      },
                                    );
                                  }).toList(),
                                ],
                              );
                            },
                          ),
                        ),

                      // Stickers overlay
                      if ((_selectedImage != null || _webImageBytes != null) && _stickers.isNotEmpty)
                        ..._stickers.asMap().entries.map((entry) {
                          final index = entry.key;
                          final sticker = entry.value;
                          return _DraggableScalableElement(
                            key: ValueKey('sticker_$index'),
                            x: sticker.x,
                            y: sticker.y,
                            scale: sticker.scale,
                            rotation: sticker.rotation,
                            onUpdate: (newX, newY, newScale) {
                              setState(() {
                                _stickers[index] = StorySticker(
                                  emoji: sticker.emoji,
                                  x: newX,
                                  y: newY,
                                  scale: newScale,
                                  rotation: sticker.rotation,
                                );
                              });
                            },
                            onDelete: () {
                              setState(() {
                                _stickers.removeAt(index);
                              });
                            },
                            child: Text(sticker.emoji, style: const TextStyle(fontSize: 30)),
                          );
                        }).toList(),

                      // Mentions overlay
                      if (_mentions.isNotEmpty && (_selectedImage != null || _webImageBytes != null))
                        ..._mentions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final mention = entry.value;
                          return _DraggableScalableElement(
                            key: ValueKey('mention_$index'),
                            x: mention.x,
                            y: mention.y,
                            scale: mention.scale,
                            rotation: 0.0,
                            onUpdate: (newX, newY, newScale) {
                              setState(() {
                                _mentions[index] = StoryMention(
                                  userId: mention.userId,
                                  userName: mention.userName,
                                  x: newX,
                                  y: newY,
                                  scale: newScale,
                                );
                              });
                            },
                            onDelete: () {
                              setState(() {
                                _mentions.removeAt(index);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue, width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.alternate_email, color: Colors.blue, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    mention.userName,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),

                      // Text overlays overlay
                      if (_textOverlays.isNotEmpty && (_selectedImage != null || _webImageBytes != null))
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Stack(
                                children: _textOverlays.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final textOverlay = entry.value;
                                  // Parse color từ hex string
                                  Color textColor;
                                  try {
                                    final colorString = textOverlay.color.replaceFirst('#', '');
                                    if (colorString.length == 6) {
                                      final colorValue = int.parse(colorString, radix: 16);
                                      textColor = Color(0xFF000000 | colorValue);
                                    } else if (colorString.length == 8) {
                                      textColor = Color(int.parse(colorString, radix: 16));
                                    } else {
                                      textColor = Colors.white;
                                    }
                                  } catch (e) {
                                    textColor = Colors.white;
                                  }

                                  return _DraggableScalableElement(
                                    key: ValueKey('text_$index'),
                                    x: textOverlay.x,
                                    y: textOverlay.y,
                                    scale: textOverlay.scale,
                                    rotation: textOverlay.rotation,
                                    onUpdate: (newX, newY, newScale) {
                                      setState(() {
                                        _textOverlays[index] = StoryTextOverlay(
                                          text: textOverlay.text,
                                          x: newX,
                                          y: newY,
                                          color: textOverlay.color,
                                          fontSize: textOverlay.fontSize,
                                          fontFamily: textOverlay.fontFamily,
                                          isBold: textOverlay.isBold,
                                          isItalic: textOverlay.isItalic,
                                          textAlign: textOverlay.textAlign,
                                          rotation: textOverlay.rotation,
                                          scale: newScale,
                                        );
                                      });
                                    },
                                    onDelete: () {
                                      setState(() {
                                        _textOverlays.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
                                      child: Text(
                                        textOverlay.text,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: textOverlay.fontSize,
                                          fontWeight: textOverlay.isBold ? FontWeight.bold : FontWeight.normal,
                                          fontStyle: textOverlay.isItalic ? FontStyle.italic : FontStyle.normal,
                                          fontFamily: textOverlay.fontFamily,
                                        ),
                                        textAlign: textOverlay.textAlign,
                                        maxLines: null,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),

                      // Right menu
                      Positioned(right: 0, top: 0, bottom: 0, child: _buildRightMenu()),
                    ],
                  );
                },
              ),
            ),

            // Bottom bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.grey.withOpacity(0.8), Colors.grey.withOpacity(0.4), Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), shape: BoxShape.circle),
                      child: const Icon(Icons.settings, color: Colors.black, size: 20),
                    ),
                    onPressed: _showMoreOptions,
                    padding: EdgeInsets.zero,
                  ),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _createStory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      elevation: 4,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Chia sẻ',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Widget nút xóa cho drawing - tap 1 lần để hiện, tap 1 lần vào X để xóa
class _DrawingDeleteButton extends StatefulWidget {
  final double centerX;
  final double centerY;
  final VoidCallback onDelete;

  const _DrawingDeleteButton({required this.centerX, required this.centerY, required this.onDelete});

  @override
  State<_DrawingDeleteButton> createState() => _DrawingDeleteButtonState();
}

class _DrawingDeleteButtonState extends State<_DrawingDeleteButton> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.centerX - 20,
      top: widget.centerY - 20,
      child: GestureDetector(
        onTap: () {
          if (_isVisible) {
            // Tap vào nút X để xóa
            widget.onDelete();
          } else {
            // Tap lần đầu để hiện nút X
            setState(() {
              _isVisible = true;
            });
          }
        },
        child: _isVisible
            ? Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.close, color: Colors.black, size: 18),
              )
            : Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black.withOpacity(0.8), width: 1.5),
                ),
                child: const Icon(Icons.close, color: Colors.black, size: 16),
              ),
      ),
    );
  }
}

// Widget có thể drag để di chuyển drawing
class _DraggableDrawingWidget extends StatefulWidget {
  final int index;
  final double left;
  final double top;
  final double width;
  final double height;
  final double centerX;
  final double centerY;
  final Offset currentOffset;
  final Function(Offset) onOffsetUpdate;
  final VoidCallback onDelete;

  const _DraggableDrawingWidget({
    super.key,
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.centerX,
    required this.centerY,
    required this.currentOffset,
    required this.onOffsetUpdate,
    required this.onDelete,
  });

  @override
  State<_DraggableDrawingWidget> createState() => _DraggableDrawingWidgetState();
}

class _DraggableDrawingWidgetState extends State<_DraggableDrawingWidget> {
  bool _isSelected = false;
  Offset? _panStart;
  late Offset _currentOffset;

  @override
  void initState() {
    super.initState();
    _currentOffset = widget.currentOffset;
  }

  @override
  void didUpdateWidget(_DraggableDrawingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentOffset != widget.currentOffset) {
      _currentOffset = widget.currentOffset;
    }
  }

  void _onPanStart(DragStartDetails details) {
    _panStart = details.localPosition;
    setState(() {
      _isSelected = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_panStart != null) {
      final delta = details.localPosition - _panStart!;
      setState(() {
        _currentOffset = _currentOffset + delta;
      });
      widget.onOffsetUpdate(_currentOffset);
      _panStart = details.localPosition;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _panStart = null;
  }

  void _onTap() {
    setState(() {
      _isSelected = !_isSelected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left - 10,
      top: widget.top - 10,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _onTap,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Container(
          width: widget.width + 20,
          height: widget.height + 20,
          decoration: _isSelected
              ? BoxDecoration(
                  border: Border.all(color: Colors.blue.withOpacity(0.6), width: 2),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Nút xóa khi được chọn - đặt ở góc trên bên phải của bounding box
              if (_isSelected)
                Positioned(
                  top: -16,
                  right: -16,
                  child: GestureDetector(
                    onTap: () {
                      widget.onDelete();
                      setState(() {
                        _isSelected = false;
                      });
                    },
                    behavior: HitTestBehavior.translucent,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 3),
                        boxShadow: [
                          BoxShadow(color: Colors.grey.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: const Icon(Icons.close, color: Colors.black, size: 18),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom painter để vẽ drawings lên preview với offset
class _StoryDrawingPainter extends CustomPainter {
  final List<StoryDrawing> drawings;
  final Map<int, Offset> offsets;
  final Size containerSize;

  _StoryDrawingPainter({required this.drawings, required this.offsets, required this.containerSize});

  @override
  void paint(Canvas canvas, Size size) {
    for (int index = 0; index < drawings.length; index++) {
      final drawing = drawings[index];
      if (drawing.points.isEmpty) continue;

      final offset = offsets[index] ?? Offset.zero;

      // Parse color từ hex string
      Color color;
      try {
        final colorString = drawing.color.replaceFirst('#', '');
        if (colorString.length == 6) {
          // Format: RRGGBB
          final colorValue = int.parse(colorString, radix: 16);
          color = Color(0xFF000000 | colorValue);
        } else if (colorString.length == 8) {
          // Format: AARRGGBB
          color = Color(int.parse(colorString, radix: 16));
        } else {
          // Fallback to black
          color = Colors.black;
        }
      } catch (e) {
        // Fallback to black nếu parse lỗi
        color = Colors.black;
      }

      final paint = Paint()
        ..color = color
        ..strokeWidth = drawing.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      // Vẽ các đường nối giữa các điểm với offset
      for (int i = 0; i < drawing.points.length - 1; i++) {
        final point1 = drawing.points[i];
        final point2 = drawing.points[i + 1];

        canvas.drawLine(
          Offset(point1.x * size.width, point1.y * size.height) + offset,
          Offset(point2.x * size.width, point2.y * size.height) + offset,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StoryDrawingPainter oldDelegate) {
    return oldDelegate.drawings != drawings ||
        oldDelegate.offsets != offsets ||
        oldDelegate.containerSize != containerSize;
  }
}

// Widget có thể drag và scale với nút xóa
class _DraggableScalableElement extends StatefulWidget {
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final Widget child;
  final Function(double newX, double newY, double newScale) onUpdate;
  final VoidCallback? onDelete;

  const _DraggableScalableElement({
    super.key,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.child,
    required this.onUpdate,
    this.onDelete,
  });

  @override
  State<_DraggableScalableElement> createState() => _DraggableScalableElementState();
}

class _DraggableScalableElementState extends State<_DraggableScalableElement> {
  late double _x;
  late double _y;
  late double _scale;
  double _baseScale = 1.0;
  bool _isSelected = false;

  @override
  void initState() {
    super.initState();
    _x = widget.x;
    _y = widget.y;
    _scale = widget.scale;
  }

  @override
  void didUpdateWidget(_DraggableScalableElement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.x != widget.x || oldWidget.y != widget.y || oldWidget.scale != widget.scale) {
      _x = widget.x;
      _y = widget.y;
      _scale = widget.scale;
    }
  }

  Offset _initialPositionPixels = Offset.zero;
  bool _isDragging = false;

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    // Lưu vị trí pixel ban đầu
    final size = MediaQuery.of(context).size;
    _initialPositionPixels = Offset(_x * size.width, _y * size.height);
    _isDragging = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size containerSize) {
    _isDragging = true;
    setState(() {
      // Handle scaling when multiple fingers or scale changed
      if (details.pointerCount > 1 || details.scale != 1.0) {
        _scale = (_baseScale * details.scale).clamp(0.5, 3.0);
      }

      // Handle panning (translation) through scale gesture
      // Sử dụng focalPointDelta để tính delta tương đối
      final delta = details.focalPointDelta;
      _initialPositionPixels = _initialPositionPixels + delta;
      // Normalize về 0.0-1.0
      _x = (_initialPositionPixels.dx / containerSize.width).clamp(0.0, 1.0);
      _y = (_initialPositionPixels.dy / containerSize.height).clamp(0.0, 1.0);
    });
    widget.onUpdate(_x, _y, _scale);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // Nếu không phải drag, thì là tap
    if (!_isDragging) {
      setState(() {
        _isSelected = !_isSelected;
      });
    }
    _isDragging = false;
  }

  void _onTap() {
    // Chỉ hiện/ẩn nút xóa khi tap, không drag
    if (!_isDragging) {
      setState(() {
        _isSelected = !_isSelected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lấy size từ MediaQuery
    final size = MediaQuery.of(context).size;

    return Positioned(
      left: _x * size.width,
      top: _y * size.height,
      child: GestureDetector(
        onTap: _onTap,
        onScaleStart: _onScaleStart,
        onScaleUpdate: (details) {
          // Lấy size từ context mỗi lần update
          final containerSize = MediaQuery.of(context).size;
          _onScaleUpdate(details, containerSize);
        },
        onScaleEnd: _onScaleEnd,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.rotate(
              angle: widget.rotation * 3.14159 / 180,
              child: Transform.scale(scale: _scale, alignment: Alignment.center, child: widget.child),
            ),
            // Nút xóa khi được chọn
            if (_isSelected && widget.onDelete != null)
              Positioned(
                top: -16,
                right: -16,
                child: GestureDetector(
                  onTap: () {
                    // Ngăn event bubble lên parent
                    widget.onDelete?.call();
                    setState(() {
                      _isSelected = false;
                    });
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 3),
                      boxShadow: [
                        BoxShadow(color: Colors.grey.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: const Icon(Icons.close, color: Colors.black, size: 18),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
