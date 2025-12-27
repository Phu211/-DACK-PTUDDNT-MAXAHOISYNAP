import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// AES-GCM encryption service.
/// Derives per-keyId keys from an app secret to avoid reuse across conversations.
/// NOTE: For real E2EE, replace key derivation with proper key exchange and
///       rotate _appSecret. This is a client-side partitioning improvement.
class EncryptionService {
  static const _appSecret = 'synap-demo-secret-please-rotate';
  final _algo = AesGcm.with256bits();

  Future<Map<String, String>> encrypt(
    String plainText, {
    required String keyId,
  }) async {
    final nonce = _algo.newNonce();
    final secretKey = await _deriveKey(keyId);
    final secretBox = await _algo.encrypt(
      utf8.encode(plainText),
      secretKey: secretKey,
      nonce: nonce,
    );
    return {
      'cipherText': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  Future<String> decrypt({
    required String cipherText,
    required String nonce,
    required String keyId,
    String? mac,
  }) async {
    final secretKey = await _deriveKey(keyId);
    final secretBox = SecretBox(
      base64Decode(cipherText),
      nonce: base64Decode(nonce),
      mac: mac != null ? Mac(base64Decode(mac)) : Mac.empty,
    );
    final clearBytes = await _algo.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    return utf8.decode(clearBytes);
  }

  Future<SecretKey> _deriveKey(String keyId) async {
    final hash = await Sha256().hash(utf8.encode('$_appSecret::$keyId'));
    return SecretKey(hash.bytes);
  }
}


