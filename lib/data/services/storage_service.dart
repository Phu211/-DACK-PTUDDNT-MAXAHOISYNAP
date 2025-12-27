import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/cloudinary_constants.dart';

class StorageService {
  Future<String> _uploadToCloudinary(
    dynamic file, {
    required String preset,
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConstants.cloudName}/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = preset;

    if (file is File) {
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
    } else if (file is Uint8List) {
      request.files.add(
        http.MultipartFile.fromBytes('file', file, filename: 'upload'),
      );
    } else {
      throw ArgumentError('Unsupported file type for Cloudinary upload');
    }

    try {
      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Cloudinary upload failed: $body');
      }

      final data = json.decode(body) as Map<String, dynamic>;
      return data['secure_url'] as String;
    } on SocketException {
      throw Exception(
        'Không có kết nối internet. Vui lòng kiểm tra kết nối mạng và thử lại.',
      );
    } on HttpException catch (e) {
      throw Exception('Lỗi kết nối: ${e.message}');
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      // Kiểm tra các lỗi mạng phổ biến
      if (errorStr.contains('socketexception') ||
          errorStr.contains('failed host lookup') ||
          errorStr.contains('no address associated with hostname') ||
          errorStr.contains('network is unreachable')) {
        throw Exception(
          'Không có kết nối internet. Vui lòng kiểm tra kết nối mạng và thử lại.',
        );
      }
      // Retry once on connection reset (có thể do mạng tạm thời bị ngắt)
      if (errorStr.contains('connection reset')) {
        try {
          final retryRequest = http.MultipartRequest('POST', uri)
            ..fields['upload_preset'] = preset;

          if (file is File) {
            retryRequest.files.add(
              await http.MultipartFile.fromPath('file', file.path),
            );
          } else if (file is Uint8List) {
            retryRequest.files.add(
              http.MultipartFile.fromBytes('file', file, filename: 'upload'),
            );
          }

          final retryResponse = await retryRequest.send();
          final retryBody = await retryResponse.stream.bytesToString();

          if (retryResponse.statusCode != 200 &&
              retryResponse.statusCode != 201) {
            throw Exception('Cloudinary upload failed after retry: $retryBody');
          }

          final data = json.decode(retryBody) as Map<String, dynamic>;
          return data['secure_url'] as String;
        } catch (retryError) {
          throw Exception('Cloudinary upload failed: $retryError');
        }
      }
      rethrow;
    }
  }

  // Upload avatar
  Future<String> uploadAvatar(File imageFile, String userId) async {
    return _uploadToCloudinary(
      imageFile,
      preset: CloudinaryConstants.unsignedPresetPosts,
    );
  }

  // Upload cover photo
  Future<String> uploadCover(File imageFile, String userId) async {
    return _uploadToCloudinary(
      imageFile,
      preset: CloudinaryConstants.unsignedPresetPosts,
    );
  }

  // Upload post image
  Future<String> uploadPostImage(
    File imageFile,
    String postId,
    int index,
  ) async {
    return _uploadToCloudinary(
      imageFile,
      preset: CloudinaryConstants.unsignedPresetPosts,
    );
  }

  // Upload post image from bytes (for web)
  Future<String> uploadPostImageBytes(
    Uint8List bytes, {
    String? fileName,
  }) async {
    return _uploadToCloudinary(
      bytes,
      preset: CloudinaryConstants.unsignedPresetPosts,
    );
  }

  // Upload multiple post images
  Future<List<String>> uploadPostImages(
    List<File> imageFiles,
    String postId,
  ) async {
    final List<String> urls = [];
    for (int i = 0; i < imageFiles.length; i++) {
      final url = await uploadPostImage(imageFiles[i], postId, i);
      urls.add(url);
    }
    return urls;
  }

  // Upload comment image
  Future<String> uploadCommentImage(
    File imageFile,
    String postId,
    String userId,
  ) async {
    return _uploadToCloudinary(
      imageFile,
      preset: CloudinaryConstants.unsignedPresetPosts,
    );
  }

  // Upload video
  Future<String> uploadVideo(File videoFile, String userId) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConstants.cloudName}/video/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConstants.unsignedPresetPosts
      ..files.add(await http.MultipartFile.fromPath('file', videoFile.path));

    try {
      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Cloudinary video upload failed: $body');
      }

      final data = json.decode(body) as Map<String, dynamic>;
      return data['secure_url'] as String;
    } on SocketException {
      throw Exception(
        'Không có kết nối internet. Vui lòng kiểm tra kết nối mạng và thử lại.',
      );
    } on HttpException catch (e) {
      throw Exception('Lỗi kết nối: ${e.message}');
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('socketexception') ||
          errorStr.contains('failed host lookup') ||
          errorStr.contains('no address associated with hostname')) {
        throw Exception(
          'Không có kết nối internet. Vui lòng kiểm tra kết nối mạng và thử lại.',
        );
      }
      rethrow;
    }
  }

  // Upload audio file for voice messages
  Future<String> uploadAudioFile(File audioFile) async {
    return uploadMusic(audioFile, '');
  }

  // Upload music/audio file
  Future<String> uploadMusic(File audioFile, String userId) async {
    // Validate file exists and is not empty
    if (!await audioFile.exists()) {
      throw Exception('Audio file không tồn tại: ${audioFile.path}');
    }

    final fileSize = await audioFile.length();
    if (fileSize == 0) {
      throw Exception('Audio file rỗng (size = 0): ${audioFile.path}');
    }

    if (kDebugMode) {
      print('Uploading audio file: ${audioFile.path}, size: $fileSize bytes');
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConstants.cloudName}/raw/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConstants.unsignedPresetPosts
      ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

    try {
      if (kDebugMode) {
        print('Sending HTTP request to Cloudinary for audio upload...');
      }

      // Add timeout for Android compatibility (30 seconds)
      final response = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            'Upload timeout sau 30 giây. Vui lòng kiểm tra kết nối mạng và thử lại.',
            const Duration(seconds: 30),
          );
        },
      );

      if (kDebugMode) {
        print('HTTP request completed. Status: ${response.statusCode}');
      }

      // Add timeout for reading response body (10 seconds)
      final body = await response.stream.bytesToString().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException(
            'Timeout khi đọc response từ Cloudinary.',
            const Duration(seconds: 10),
          );
        },
      );

      if (kDebugMode) {
        print('Response body received. Length: ${body.length}');
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        if (kDebugMode) {
          print(
            'Cloudinary upload failed. Status: ${response.statusCode}, Body: $body',
          );
        }
        throw Exception('Cloudinary audio upload failed: $body');
      }

      if (kDebugMode) {
        print('Parsing Cloudinary response...');
        print(
          'Response body preview: ${body.length > 200 ? body.substring(0, 200) : body}',
        );
      }

      final data = json.decode(body) as Map<String, dynamic>;
      final secureUrl = data['secure_url'] as String?;

      if (kDebugMode) {
        print('Parsed secure_url: $secureUrl');
        print('Response keys: ${data.keys.toList()}');
      }

      if (secureUrl == null || secureUrl.isEmpty) {
        if (kDebugMode) {
          print(
            'ERROR: Cloudinary response missing secure_url. Full response: $body',
          );
        }
        throw Exception('Cloudinary không trả về URL: $body');
      }

      if (kDebugMode) {
        print('Audio uploaded successfully: $secureUrl');
      }

      return secureUrl;
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        print('Upload timeout: $e');
      }
      throw Exception(
        'Upload timeout. Vui lòng kiểm tra kết nối mạng và thử lại.',
      );
    } on SocketException catch (e) {
      if (kDebugMode) {
        print('SocketException during audio upload: $e');
      }
      throw Exception(
        'Không có kết nối internet. Vui lòng kiểm tra kết nối mạng và thử lại.',
      );
    } on HttpException catch (e) {
      if (kDebugMode) {
        print('HttpException during audio upload: $e');
      }
      throw Exception('Lỗi kết nối: ${e.message}');
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Unexpected error during audio upload: $e');
        print('Stack trace: $stackTrace');
      }
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('socketexception') ||
          errorStr.contains('failed host lookup') ||
          errorStr.contains('no address associated with hostname') ||
          errorStr.contains('timeout')) {
        throw Exception(
          'Không có kết nối internet hoặc timeout. Vui lòng kiểm tra kết nối mạng và thử lại.',
        );
      }
      rethrow;
    }
  }
}
