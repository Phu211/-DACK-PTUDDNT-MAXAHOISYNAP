import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import '../../../data/models/story_element_model.dart';
import '../../widgets/story_editors/story_editors.dart';
import '../../../core/utils/error_message_helper.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';

class StoryEditScreen extends StatefulWidget {
  final File? imageFile;
  final Uint8List? webImageBytes;
  final int initialRotation;
  final List<StorySticker> initialStickers;
  final List<StoryTextOverlay> initialTextOverlays;
  final List<StoryDrawing> initialDrawings;
  final List<StoryMention> initialMentions;
  final StoryLink? initialLink;
  final String? initialEffect;

  const StoryEditScreen({
    super.key,
    this.imageFile,
    this.webImageBytes,
    this.initialRotation = 0,
    this.initialStickers = const [],
    this.initialTextOverlays = const [],
    this.initialDrawings = const [],
    this.initialMentions = const [],
    this.initialLink,
    this.initialEffect,
  });

  @override
  State<StoryEditScreen> createState() => _StoryEditScreenState();
}

class _StoryEditScreenState extends State<StoryEditScreen> {
  File? _editedImage;
  Uint8List? _editedWebImageBytes;
  int _imageRotation = 0;

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

  @override
  void initState() {
    super.initState();
    _editedImage = widget.imageFile;
    _editedWebImageBytes = widget.webImageBytes;
    _imageRotation = widget.initialRotation;
    _stickers = List.from(widget.initialStickers);
    _textOverlays = List.from(widget.initialTextOverlays);
    _drawings = List.from(widget.initialDrawings);
    _mentions = List.from(widget.initialMentions);
    _link = widget.initialLink;
    _selectedEffect = widget.initialEffect;
  }

  // Crop image
  Future<void> _cropImage() async {
    if (_editedImage == null && _editedWebImageBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh trước')));
      }
      return;
    }

    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crop ảnh chưa hỗ trợ trên web')));
      }
      return;
    }

    if (_editedImage == null) return;

    // Kiểm tra file tồn tại trước khi crop
    try {
      if (!await _editedImage!.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File ảnh không tồn tại')));
        }
        return;
      }

      // Kiểm tra file path hợp lệ
      final filePath = _editedImage!.path;
      if (filePath.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đường dẫn ảnh không hợp lệ')));
        }
        return;
      }

      // Kiểm tra mounted trước khi gọi ImageCropper
      if (!mounted) return;

      // Thêm delay nhỏ để đảm bảo UI đã sẵn sàng
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: filePath,
        compressQuality: 90,
        maxWidth: 1080,
        maxHeight: 1920,
        aspectRatio: const CropAspectRatio(ratioX: 9, ratioY: 16), // Story aspect ratio
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Cắt ảnh',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
            showCropGrid: true,
            cropFrameColor: Colors.white,
            cropGridColor: Colors.white.withOpacity(0.5),
            cropFrameStrokeWidth: 2,
            cropGridStrokeWidth: 1,
            statusBarColor: Colors.black,
            backgroundColor: Colors.black,
          ),
          IOSUiSettings(
            title: 'Cắt ảnh',
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
          ),
        ],
      );

      // Kiểm tra mounted sau khi crop
      if (!mounted) return;

      if (croppedFile != null && croppedFile.path.isNotEmpty) {
        // Kiểm tra file cropped tồn tại
        final croppedFileExists = await File(croppedFile.path).exists();
        if (croppedFileExists) {
          setState(() {
            _editedImage = File(croppedFile.path);
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể lưu ảnh đã cắt')));
          }
        }
      }
    } catch (e, stackTrace) {
      // Log lỗi chi tiết để debug
      debugPrint('Lỗi crop ảnh: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorMessageHelper.getErrorMessage(e, defaultMessage: 'Không thể cắt ảnh. Vui lòng thử lại.'),
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Rotate image
  Future<void> _rotateImage() async {
    if (_editedImage == null && _editedWebImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ảnh trước')));
      return;
    }

    try {
      if (kIsWeb) {
        // Web: rotate in memory
        if (_editedWebImageBytes != null) {
          final image = img.decodeImage(_editedWebImageBytes!);
          if (image != null) {
            final rotated = img.copyRotate(image, angle: 90);
            setState(() {
              _editedWebImageBytes = Uint8List.fromList(img.encodePng(rotated));
              _imageRotation = (_imageRotation + 90) % 360;
            });
          }
        }
      } else {
        // Mobile/Desktop: rotate file
        if (_editedImage == null) return;

        final imageBytes = await _editedImage!.readAsBytes();
        final image = img.decodeImage(imageBytes);
        if (image != null) {
          _imageRotation = (_imageRotation + 90) % 360;
          final rotated = img.copyRotate(image, angle: _imageRotation);
          final rotatedBytes = Uint8List.fromList(img.encodeJpg(rotated));

          // Save rotated image
          final tempFile = File('${_editedImage!.path}_rotated.jpg');
          await tempFile.writeAsBytes(rotatedBytes);

          setState(() {
            _editedImage = tempFile;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e, defaultMessage: 'Không thể xoay ảnh'));
      }
    }
  }

  void _showStickerPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StickerPicker(
        onStickerSelected: (sticker) {
          setState(() {
            _stickers.add(sticker);
          });
        },
      ),
    );
  }

  void _showTextOverlayEditor() {
    showModalBottomSheet(
      context: context,
      builder: (context) => TextOverlayEditor(
        onTextAdded: (textOverlay) {
          setState(() {
            _textOverlays.add(textOverlay);
          });
        },
      ),
    );
  }

  void _showDrawingEditor() {
    showModalBottomSheet(
      context: context,
      builder: (context) => DrawingEditor(
        onDrawingComplete: (drawing) {
          setState(() {
            _drawings.add(drawing);
            // Offset mặc định là 0 cho drawing mới
            _drawingOffsets[_drawings.length - 1] = Offset.zero;
          });
        },
      ),
    );
  }

  void _showMentionPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => MentionPicker(
        onMentionSelected: (mention) {
          setState(() {
            _mentions.add(mention);
          });
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
    showModalBottomSheet(
      context: context,
      builder: (context) => EffectPicker(
        onEffectSelected: (effect) {
          setState(() {
            _selectedEffect = effect;
          });
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

  void _saveAndReturn() {
    // Áp dụng offset vào points của drawings trước khi trả về
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

    Navigator.of(context).pop({
      'imageFile': _editedImage,
      'webImageBytes': _editedWebImageBytes,
      'rotation': _imageRotation,
      'stickers': _stickers,
      'textOverlays': _textOverlays,
      'drawings': adjustedDrawings,
      'mentions': _mentions,
      'link': _link,
      'effect': _selectedEffect,
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Chỉnh sửa', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _saveAndReturn,
            child: const Text(
              'Xong',
              style: TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Image preview
          Expanded(
            child: Center(
              child: _editedImage != null
                  ? Stack(
                      children: [
                        Transform.rotate(
                          angle: _imageRotation * 3.14159 / 180,
                          child: _selectedEffect != null && _selectedEffect!.isNotEmpty
                              ? _buildEffectFilter(_selectedEffect!, Image.file(_editedImage!, fit: BoxFit.contain))
                              : Image.file(_editedImage!, fit: BoxFit.contain),
                        ),
                        // Drawings overlay - có thể di chuyển được
                        if (_drawings.isNotEmpty)
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
                      ],
                    )
                  : _editedWebImageBytes != null
                  ? Stack(
                      children: [
                        Transform.rotate(
                          angle: _imageRotation * 3.14159 / 180,
                          child: _selectedEffect != null && _selectedEffect!.isNotEmpty
                              ? _buildEffectFilter(
                                  _selectedEffect!,
                                  Image.memory(_editedWebImageBytes!, fit: BoxFit.contain),
                                )
                              : Image.memory(_editedWebImageBytes!, fit: BoxFit.contain),
                        ),
                        // Drawings overlay - có thể di chuyển được
                        if (_drawings.isNotEmpty)
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
                        if (_stickers.isNotEmpty)
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
                        if (_mentions.isNotEmpty)
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
                        if (_textOverlays.isNotEmpty)
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
                      ],
                    )
                  : const Center(
                      child: Text('Không có ảnh để chỉnh sửa', style: TextStyle(color: Colors.white70)),
                    ),
            ),
          ),

          // Bottom toolbar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Crop and Rotate buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildToolButton(icon: Icons.crop, label: 'Cắt', onTap: _cropImage),
                    _buildToolButton(icon: Icons.rotate_right, label: 'Xoay', onTap: _rotateImage),
                  ],
                ),
                const SizedBox(height: 16),
                // Edit tools
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildEditButton(
                        icon: Icons.emoji_emotions,
                        label: strings?.storyStickers ?? 'Nhãn dán',
                        onTap: _showStickerPicker,
                      ),
                      const SizedBox(width: 12),
                      _buildEditButton(
                        icon: Icons.text_fields,
                        label: strings?.storyTextTool ?? 'Văn bản',
                        onTap: _showTextOverlayEditor,
                      ),
                      const SizedBox(width: 12),
                      _buildEditButton(icon: Icons.edit, label: 'Vẽ', onTap: _showDrawingEditor),
                      const SizedBox(width: 12),
                      _buildEditButton(
                        icon: Icons.alternate_email,
                        label: strings?.storyMention ?? 'Nhắc đến',
                        onTap: _showMentionPicker,
                      ),
                      const SizedBox(width: 12),
                      _buildEditButton(icon: Icons.link, label: 'Liên kết', onTap: _showLinkEditor),
                      const SizedBox(width: 12),
                      _buildEditButton(
                        icon: Icons.auto_awesome,
                        label: strings?.storyEffects ?? 'Hiệu ứng',
                        onTap: _showEffectPicker,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// Custom painter để vẽ drawings lên preview
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
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              )
            : Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
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
      ),
    );
  }
}

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
