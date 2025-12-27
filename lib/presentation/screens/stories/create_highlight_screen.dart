import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/story_model.dart';
import '../../../data/models/highlight_model.dart';
import '../../../data/services/story_service.dart';
import '../../../data/services/highlight_service.dart';
import '../../providers/auth_provider.dart';
import '../../../core/utils/error_message_helper.dart';

class CreateHighlightScreen extends StatefulWidget {
  const CreateHighlightScreen({super.key});

  @override
  State<CreateHighlightScreen> createState() => _CreateHighlightScreenState();
}

class _CreateHighlightScreenState extends State<CreateHighlightScreen> {
  final TextEditingController _titleController = TextEditingController();
  final StoryService _storyService = StoryService();
  final HighlightService _highlightService = HighlightService();
  List<StoryModel> _availableStories = [];
  Set<String> _selectedStoryIds = {};
  bool _isLoading = true;
  bool _isCreating = false;
  String? _selectedIconName;

  final List<String> _iconOptions = [
    '❤️', '😊', '🌟', '🎉', '🎂', '🎁', '🏆', '⭐', '💫', '✨',
    '🎈', '🎊', '🎀', '💝', '🎪', '🎭', '🎨', '🎬', '🎮', '🎯',
  ];

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadStories() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final stories = await _storyService.fetchStoriesByUserOnce(
        currentUser.id,
        viewerId: currentUser.id,
        includeExpired: true, // Include expired stories for highlights
      );
      if (mounted) {
        setState(() {
          _availableStories = stories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(
            e,
            defaultMessage: 'Không thể tải stories',
          ),
        );
      }
    }
  }

  Future<void> _createHighlight() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên highlight')),
      );
      return;
    }

    if (_selectedStoryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ít nhất một story')),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    setState(() => _isCreating = true);

    try {
      // Tìm story đầu tiên để lấy cover image
      final firstStory = _availableStories.firstWhere(
        (s) => _selectedStoryIds.contains(s.id),
      );
      String? coverImageUrl;
      
      if (firstStory.imageUrl != null) {
        coverImageUrl = firstStory.imageUrl;
      } else if (firstStory.videoUrl != null) {
        // Có thể extract frame từ video, nhưng tạm thời dùng null
        coverImageUrl = null;
      }

      final highlight = HighlightModel(
        id: '',
        userId: currentUser.id,
        title: _titleController.text.trim(),
        iconName: _selectedIconName ?? '⭐',
        coverImageUrl: coverImageUrl,
        storyIds: _selectedStoryIds.toList(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _highlightService.createHighlight(highlight);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tạo highlight thành công!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(
            e,
            defaultMessage: 'Không thể tạo highlight',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Tạo highlight mới'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        actions: [
          if (_isCreating)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            TextButton(
              onPressed: _createHighlight,
              child: const Text(
                'Tạo',
                style: TextStyle(color: Colors.blue, fontSize: 16),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _availableStories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.highlight_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Bạn chưa có story nào',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tạo story trước khi tạo highlight',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Title input
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Tên highlight',
                        hintText: 'Nhập tên highlight...',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 30,
                    ),
                    const SizedBox(height: 16),
                    
                    // Icon selection
                    const Text(
                      'Chọn icon',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _iconOptions.map((icon) {
                        final isSelected = _selectedIconName == icon;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedIconName = icon);
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.grey[200],
                              border: Border.all(
                                color: isSelected ? Colors.blue : Colors.grey,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(icon, style: const TextStyle(fontSize: 24)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    
                    // Stories selection
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Chọn stories (${_selectedStoryIds.length}/${_availableStories.length})',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_availableStories.any((s) => s.isExpired))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orange, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
                                const SizedBox(width: 4),
                                Text(
                                  'Có thể chọn story đã hết hạn',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _availableStories.length,
                      itemBuilder: (context, index) {
                        final story = _availableStories[index];
                        final isSelected = _selectedStoryIds.contains(story.id);
                        final isExpired = story.isExpired;
                        
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedStoryIds.remove(story.id);
                              } else {
                                _selectedStoryIds.add(story.id);
                              }
                            });
                          },
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected ? Colors.blue : Colors.grey,
                                    width: isSelected ? 3 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  children: [
                                    // Story media
                                    story.imageUrl != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(7),
                                            child: Image.network(
                                              story.imageUrl!,
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              height: double.infinity,
                                              color: isExpired ? Colors.black54 : null,
                                              colorBlendMode: isExpired ? BlendMode.darken : null,
                                            ),
                                          )
                                        : story.videoUrl != null
                                            ? Container(
                                                color: Colors.black,
                                                child: Center(
                                                  child: Icon(
                                                    Icons.play_circle_outline,
                                                    color: isExpired ? Colors.grey : Colors.white,
                                                    size: 32,
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                color: Colors.grey[300],
                                                child: const Center(
                                                  child: Icon(Icons.auto_stories, size: 32),
                                                ),
                                              ),
                                    // Overlay cho expired stories
                                    if (isExpired)
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(7),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.schedule,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Selected indicator
                              if (isSelected)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              // Expired indicator (nếu chưa được chọn)
                              if (isExpired && !isSelected)
                                Positioned(
                                  bottom: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Hết hạn',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              // Expired indicator (nếu chưa được chọn)
                              if (isExpired && !isSelected)
                                Positioned(
                                  bottom: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Hết hạn',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
    );
  }
}

