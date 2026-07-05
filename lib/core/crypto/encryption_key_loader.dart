import 'dart:io';

import 'package:flutter/services.dart';

const String _encryptionKeyAssetPath = 'Encryption_key';

Future<Uint8List> loadEncryptionKey() async {
  final content = await _loadEncryptionKeyContent();
  return parseEncryptionKey(content);
}

Uint8List parseEncryptionKey(String content) {
  final lines = content
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList(growable: false);

  if (lines.isEmpty) {
    throw const FormatException('Encryption_key does not contain a usable key');
  }

  final keyHex = lines.first;
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(keyHex)) {
    throw const FormatException(
      'Encryption_key must place a 32-character hexadecimal key on the first non-comment line',
    );
  }

  return _hexToBytes(keyHex);
}

Future<String> _loadEncryptionKeyContent() async {
  try {
    final content = await rootBundle.loadString(_encryptionKeyAssetPath);
    if (content.trim().isNotEmpty) {
      return content;
    }
  } catch (_) {
    // Fall back to a local file so tests and local development still work.
  }

  final keyFile = File(_encryptionKeyAssetPath);
  if (await keyFile.exists()) {
    return keyFile.readAsString();
  }

  throw const FormatException(
    'Encryption_key is missing. Create a root-level Encryption_key file (for example from Encryption_key.example) and rebuild the client with the same key as the server.',
  );
}

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}
