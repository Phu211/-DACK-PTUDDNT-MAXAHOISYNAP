import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../models/highlight_model.dart';

class HighlightService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Tạo highlight mới
  Future<String> createHighlight(HighlightModel highlight) async {
    try {
      final docRef = await _firestore
          .collection(AppConstants.highlightsCollection)
          .add(highlight.toMap());
      return docRef.id;
    } catch (e) {
      throw Exception('Create highlight failed: $e');
    }
  }

  /// Cập nhật highlight
  Future<void> updateHighlight(HighlightModel highlight) async {
    try {
      await _firestore
          .collection(AppConstants.highlightsCollection)
          .doc(highlight.id)
          .update(highlight.toMap());
    } catch (e) {
      throw Exception('Update highlight failed: $e');
    }
  }

  /// Xóa highlight
  Future<void> deleteHighlight(String highlightId) async {
    try {
      await _firestore
          .collection(AppConstants.highlightsCollection)
          .doc(highlightId)
          .delete();
    } catch (e) {
      throw Exception('Delete highlight failed: $e');
    }
  }

  /// Lấy tất cả highlights của user
  Stream<List<HighlightModel>> getHighlightsByUser(String userId) {
    debugPrint('HighlightService: Creating stream for user $userId');
    
    // Query không có orderBy để tránh lỗi thiếu index
    // Sẽ sắp xếp thủ công trong map
    return _firestore
        .collection(AppConstants.highlightsCollection)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snapshot) {
            debugPrint('HighlightService: Received snapshot with ${snapshot.docs.length} docs');
            final highlights = snapshot.docs
                .map((doc) {
                  try {
                    final data = doc.data();
                    debugPrint('HighlightService: Parsing highlight ${doc.id}, title: ${data['title']}');
                    final highlight = HighlightModel.fromMap(doc.id, data);
                    debugPrint('HighlightService: Successfully parsed highlight: ${highlight.title}');
                    return highlight;
                  } catch (e, stackTrace) {
                    debugPrint('Error parsing highlight ${doc.id}: $e');
                    debugPrint('Stack trace: $stackTrace');
                    debugPrint('Data: ${doc.data()}');
                    return null;
                  }
                })
                .whereType<HighlightModel>()
                .toList();
            
            // Sắp xếp thủ công theo createdAt (mới nhất trước)
            highlights.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            
            debugPrint('HighlightService: Found ${highlights.length} highlights for user $userId');
            return highlights;
          },
        )
        .handleError((error, stackTrace) {
          debugPrint('HighlightService: Stream error: $error');
          debugPrint('Stack trace: $stackTrace');
          // Trả về empty list nếu có lỗi
          return <HighlightModel>[];
        });
  }

  /// Lấy highlights của user (one-time fetch)
  Future<List<HighlightModel>> fetchHighlightsByUser(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.highlightsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => HighlightModel.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      throw Exception('Fetch highlights failed: $e');
    }
  }
}
