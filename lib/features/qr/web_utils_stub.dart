import 'dart:typed_data';

// No-op implementations for non-web platforms.
Future<void> saveFileWeb(Uint8List bytes, String fileName) async {}
Future<void> shareFileWeb(Uint8List bytes, String text) async {}
