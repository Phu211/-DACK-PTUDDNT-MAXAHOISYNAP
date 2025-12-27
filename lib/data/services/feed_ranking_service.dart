import '../models/post_model.dart';
import 'friend_service.dart';

class FeedRankingService {
  final FriendService _friendService = FriendService();

  // Rank posts based on relevance
  Future<List<PostModel>> rankPosts(
    List<PostModel> posts,
    String currentUserId,
  ) async {
    // Get user's friends
    final friendIds = await _friendService.getFriends(currentUserId);
    
    // Calculate score for each post
    final scoredPosts = <_ScoredPost>[];
    
    for (final post in posts) {
      double score = 0.0;
      
      // Base score from engagement
      score += post.likesCount * 0.1;
      score += post.commentsCount * 0.2;
      score += post.sharesCount * 0.15;
      
      // Friend boost (posts from friends get higher score)
      if (friendIds.contains(post.userId)) {
        score += 10.0;
      }
      
      // Recency boost (newer posts get higher score)
      final hoursSincePost = DateTime.now().difference(post.createdAt).inHours;
      if (hoursSincePost < 1) {
        score += 5.0;
      } else if (hoursSincePost < 24) {
        score += 2.0;
      } else if (hoursSincePost < 168) { // 1 week
        score += 1.0;
      }
      
      // Media boost (posts with images get higher score)
      if (post.mediaUrls.isNotEmpty) {
        score += 2.0;
      }
      
      scoredPosts.add(_ScoredPost(post: post, score: score));
    }
    
    // Sort by score descending
    scoredPosts.sort((a, b) => b.score.compareTo(a.score));
    
    return scoredPosts.map((sp) => sp.post).toList();
  }
}

class _ScoredPost {
  final PostModel post;
  final double score;

  _ScoredPost({required this.post, required this.score});
}


