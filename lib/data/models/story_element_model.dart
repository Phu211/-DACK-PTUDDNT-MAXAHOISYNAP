// Model for story elements (stickers, text overlays, drawings, etc.)
import 'package:flutter/material.dart';

class StorySticker {
  final String emoji; // Emoji or sticker URL
  final double x; // Position X (0.0 to 1.0)
  final double y; // Position Y (0.0 to 1.0)
  final double scale; // Scale factor
  final double rotation; // Rotation in degrees

  StorySticker({
    required this.emoji,
    required this.x,
    required this.y,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'emoji': emoji,
      'x': x,
      'y': y,
      'scale': scale,
      'rotation': rotation,
    };
  }

  factory StorySticker.fromMap(Map<String, dynamic> map) {
    return StorySticker(
      emoji: map['emoji'] ?? '',
      x: (map['x'] ?? 0.0).toDouble(),
      y: (map['y'] ?? 0.0).toDouble(),
      scale: (map['scale'] ?? 1.0).toDouble(),
      rotation: (map['rotation'] ?? 0.0).toDouble(),
    );
  }
}

class StoryTextOverlay {
  final String text;
  final double x; // Position X (0.0 to 1.0)
  final double y; // Position Y (0.0 to 1.0)
  final String color; // Hex color
  final double fontSize;
  final String fontFamily;
  final bool isBold;
  final bool isItalic;
  final TextAlign textAlign;
  final double rotation;
  final double scale; // Scale factor

  StoryTextOverlay({
    required this.text,
    required this.x,
    required this.y,
    this.color = '#FFFFFF',
    this.fontSize = 24.0,
    this.fontFamily = 'Roboto',
    this.isBold = false,
    this.isItalic = false,
    this.textAlign = TextAlign.center,
    this.rotation = 0.0,
    this.scale = 1.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'x': x,
      'y': y,
      'color': color,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'isBold': isBold,
      'isItalic': isItalic,
      'textAlign': textAlign.toString().split('.').last,
      'rotation': rotation,
      'scale': scale,
    };
  }

  factory StoryTextOverlay.fromMap(Map<String, dynamic> map) {
    return StoryTextOverlay(
      text: map['text'] ?? '',
      x: (map['x'] ?? 0.0).toDouble(),
      y: (map['y'] ?? 0.0).toDouble(),
      color: map['color'] ?? '#FFFFFF',
      fontSize: (map['fontSize'] ?? 24.0).toDouble(),
      fontFamily: map['fontFamily'] ?? 'Roboto',
      isBold: map['isBold'] ?? false,
      isItalic: map['isItalic'] ?? false,
      textAlign: _parseTextAlign(map['textAlign']),
      rotation: (map['rotation'] ?? 0.0).toDouble(),
      scale: (map['scale'] ?? 1.0).toDouble(),
    );
  }

  static TextAlign _parseTextAlign(String? align) {
    switch (align) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      case 'center':
        return TextAlign.center;
      case 'justify':
        return TextAlign.justify;
      default:
        return TextAlign.center;
    }
  }
}

class StoryDrawing {
  final List<DrawingPoint> points;
  final String color;
  final double strokeWidth;

  StoryDrawing({
    required this.points,
    this.color = '#000000',
    this.strokeWidth = 3.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'points': points.map((p) => p.toMap()).toList(),
      'color': color,
      'strokeWidth': strokeWidth,
    };
  }

  factory StoryDrawing.fromMap(Map<String, dynamic> map) {
    return StoryDrawing(
      points: (map['points'] as List<dynamic>?)
              ?.map((p) => DrawingPoint.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      color: map['color'] ?? '#000000',
      strokeWidth: (map['strokeWidth'] ?? 3.0).toDouble(),
    );
  }
}

class DrawingPoint {
  final double x;
  final double y;

  DrawingPoint({required this.x, required this.y});

  Map<String, dynamic> toMap() {
    return {'x': x, 'y': y};
  }

  factory DrawingPoint.fromMap(Map<String, dynamic> map) {
    return DrawingPoint(
      x: (map['x'] ?? 0.0).toDouble(),
      y: (map['y'] ?? 0.0).toDouble(),
    );
  }
}

class StoryMention {
  final String userId;
  final String userName;
  final double x; // Position X (0.0 to 1.0)
  final double y; // Position Y (0.0 to 1.0)
  final double scale; // Scale factor

  StoryMention({
    required this.userId,
    required this.userName,
    required this.x,
    required this.y,
    this.scale = 1.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'x': x,
      'y': y,
      'scale': scale,
    };
  }

  factory StoryMention.fromMap(Map<String, dynamic> map) {
    return StoryMention(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      x: (map['x'] ?? 0.0).toDouble(),
      y: (map['y'] ?? 0.0).toDouble(),
      scale: (map['scale'] ?? 1.0).toDouble(),
    );
  }
}

class StoryLink {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;

  StoryLink({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
    };
  }

  factory StoryLink.fromMap(Map<String, dynamic> map) {
    return StoryLink(
      url: map['url'] ?? '',
      title: map['title'],
      description: map['description'],
      imageUrl: map['imageUrl'],
    );
  }
}


