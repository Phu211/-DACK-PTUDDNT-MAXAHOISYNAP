import 'dart:convert';

import 'package:http/http.dart' as http;

class DeezerTrack {
  final String id;
  final String name;
  final String artist;
  final String? album;
  final String? previewUrl; // luôn là demo ~30s nếu có
  final String? imageUrl;
  final String externalUrl;

  DeezerTrack({
    required this.id,
    required this.name,
    required this.artist,
    this.album,
    this.previewUrl,
    this.imageUrl,
    required this.externalUrl,
  });

  factory DeezerTrack.fromJson(Map<String, dynamic> json) {
    final artistName = (json['artist']?['name'] as String?) ?? '';
    final albumName = (json['album']?['title'] as String?);
    final image = (json['album']?['cover_medium'] as String?) ??
        (json['album']?['cover'] as String?);

    return DeezerTrack(
      id: (json['id'] ?? '').toString(),
      name: json['title'] as String? ?? '',
      artist: artistName,
      album: albumName,
      previewUrl: json['preview'] as String?,
      imageUrl: image,
      externalUrl: json['link'] as String? ?? '',
    );
  }
}

class DeezerService {
  static const String _apiBaseUrl = 'https://api.deezer.com';

  // Search for tracks
  Future<List<DeezerTrack>> searchTracks(String query,
      {int limit = 20}) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/search?q=$encodedQuery&limit=$limit'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final items = data['data'] as List<dynamic>? ?? [];

        return items
            .map((item) => DeezerTrack.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Deezer search failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching Deezer tracks: $e');
    }
  }

  // Get track by ID
  Future<DeezerTrack?> getTrack(String trackId) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/track/$trackId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return DeezerTrack.fromJson(data);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}



