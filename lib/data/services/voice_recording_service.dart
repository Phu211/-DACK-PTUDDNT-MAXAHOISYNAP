import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

/// Service để record và upload voice messages.
class VoiceRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  final StorageService _storageService = StorageService();

  bool _isRecording = false;
  String? _currentRecordingPath;
  Timer? _durationTimer;
  int _currentDuration = 0;
  StreamController<int>? _durationController;

  /// Stream để lắng nghe duration khi đang record.
  Stream<int>? get durationStream => _durationController?.stream;

  /// Kiểm tra xem có đang record không.
  bool get isRecording => _isRecording;

  /// Duration hiện tại (seconds).
  int get currentDuration => _currentDuration;

  /// Kiểm tra quyền microphone.
  Future<bool> hasPermission() async {
    try {
      final permission = await _recorder.hasPermission();
      return permission;
    } catch (e) {
      debugPrint('Error checking microphone permission: $e');
      return false;
    }
  }

  /// Bắt đầu record voice message.
  /// Trả về path của file đang record.
  Future<String> startRecording() async {
    try {
      if (kDebugMode) {
        debugPrint('=== VoiceRecordingService.startRecording ===');
      }

      // Kiểm tra permission
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (kDebugMode) {
          debugPrint('Microphone permission denied');
        }
        throw Exception(
          'Không có quyền ghi âm. Vui lòng cấp quyền trong Settings.',
        );
      }

      if (kDebugMode) {
        debugPrint('Permission granted, creating file path...');
      }

      // Tạo file path
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/voice_$timestamp.m4a';

      if (kDebugMode) {
        debugPrint('File path created: $path');
        debugPrint('Starting recorder...');
      }

      // Bắt đầu record
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _isRecording = true;
      _currentRecordingPath = path;
      _currentDuration = 0;
      _durationController = StreamController<int>.broadcast();

      if (kDebugMode) {
        debugPrint('Recording started successfully');
      }

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _currentDuration++;
        _durationController?.add(_currentDuration);
      });

      return path;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Error starting recording: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      _isRecording = false;
      rethrow;
    }
  }

  /// Dừng record và trả về file path.
  Future<String?> stopRecording() async {
    try {
      if (kDebugMode) {
        debugPrint('=== VoiceRecordingService.stopRecording ===');
        debugPrint('Is recording: $_isRecording');
        debugPrint('Current duration: $_currentDuration seconds');
      }

      if (!_isRecording) {
        if (kDebugMode) {
          debugPrint('Not recording, returning null');
        }
        return null;
      }

      if (kDebugMode) {
        debugPrint('Stopping recorder...');
      }

      final path = await _recorder.stop();

      if (kDebugMode) {
        debugPrint('Recorder stopped. Path: $path');
      }

      _isRecording = false;
      _durationTimer?.cancel();
      _durationTimer = null;
      _durationController?.close();
      _durationController = null;

      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final fileSize = await file.length();
          if (kDebugMode) {
            debugPrint('File exists. Size: $fileSize bytes');
          }
          if (fileSize > 0) {
            return path;
          } else {
            if (kDebugMode) {
              debugPrint('WARNING: File exists but size is 0');
            }
          }
        } else {
          if (kDebugMode) {
            debugPrint('WARNING: File does not exist: $path');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('WARNING: Recorder returned null path');
        }
      }

      return null;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Error stopping recording: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      _isRecording = false;
      _durationTimer?.cancel();
      _durationController?.close();
      return null;
    }
  }

  /// Hủy record hiện tại và xóa file.
  Future<void> cancelRecording() async {
    try {
      if (_isRecording) {
        await _recorder.stop();
        _isRecording = false;
      }

      _durationTimer?.cancel();
      _durationTimer = null;
      _durationController?.close();
      _durationController = null;

      // Xóa file nếu tồn tại
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _currentRecordingPath = null;
      }

      _currentDuration = 0;
    } catch (e) {
      debugPrint('Error canceling recording: $e');
    }
  }

  /// Upload voice file lên Cloudinary và trả về URL.
  /// duration: Thời lượng của voice message (seconds).
  Future<String> uploadVoiceFile(
    String filePath, {
    required int duration,
  }) async {
    try {
      final file = File(filePath);

      // Validate file exists
      if (!await file.exists()) {
        throw Exception('Voice file không tồn tại: $filePath');
      }

      // Validate file size
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('Voice file rỗng (size = 0): $filePath');
      }

      if (kDebugMode) {
        debugPrint('Uploading voice file: $filePath');
        debugPrint('File size: $fileSize bytes');
        debugPrint('Duration: $duration seconds');
      }

      // Double-check file still exists and is accessible before upload
      if (!await file.exists()) {
        throw Exception('Voice file đã bị xóa trước khi upload: $filePath');
      }
      final fileSizeBeforeUpload = await file.length();
      if (fileSizeBeforeUpload == 0) {
        throw Exception('Voice file rỗng trước khi upload: $filePath');
      }
      if (kDebugMode) {
        debugPrint(
          'File verified before upload. Size: $fileSizeBeforeUpload bytes',
        );
      }

      // Upload lên Cloudinary
      final url = await _storageService.uploadAudioFile(file);

      if (kDebugMode) {
        debugPrint('Voice file uploaded successfully: $url');
        debugPrint('URL length: ${url.length}');
        debugPrint('URL is empty: ${url.isEmpty}');
      }

      if (url.isEmpty) {
        throw Exception('URL trả về từ Cloudinary rỗng');
      }

      // Xóa file local sau khi upload thành công
      try {
        await file.delete();
        if (kDebugMode) {
          debugPrint('Local voice file deleted: $filePath');
        }
      } catch (deleteError) {
        // Log nhưng không throw - file đã upload thành công
        if (kDebugMode) {
          debugPrint('Warning: Could not delete local file: $deleteError');
        }
      }

      return url;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Error uploading voice file: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Dispose resources.
  void dispose() {
    _durationTimer?.cancel();
    _durationController?.close();
    _recorder.dispose();
  }
}
