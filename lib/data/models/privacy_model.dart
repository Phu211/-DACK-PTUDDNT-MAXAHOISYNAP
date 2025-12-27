import 'package:flutter/material.dart';

enum PrivacyType {
  public,    // Công khai
  friends,   // Bạn bè
  onlyMe,    // Chỉ mình tôi
}

extension PrivacyTypeExtension on PrivacyType {
  String get name {
    switch (this) {
      case PrivacyType.public:
        return 'Công khai';
      case PrivacyType.friends:
        return 'Bạn bè';
      case PrivacyType.onlyMe:
        return 'Chỉ mình tôi';
    }
  }

  IconData get icon {
    switch (this) {
      case PrivacyType.public:
        return Icons.public;
      case PrivacyType.friends:
        return Icons.people;
      case PrivacyType.onlyMe:
        return Icons.lock;
    }
  }

  static PrivacyType? fromString(String value) {
    switch (value) {
      case 'public':
        return PrivacyType.public;
      case 'friends':
        return PrivacyType.friends;
      case 'onlyMe':
        return PrivacyType.onlyMe;
      default:
        return PrivacyType.public;
    }
  }

  String toValue() {
    switch (this) {
      case PrivacyType.public:
        return 'public';
      case PrivacyType.friends:
        return 'friends';
      case PrivacyType.onlyMe:
        return 'onlyMe';
    }
  }
}


