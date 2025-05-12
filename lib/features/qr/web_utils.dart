// This file is only used when running on web
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveFileWeb(Uint8List bytes, String fileName) async {
  final blob = html.Blob([bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);

  // Create a download link with the specified filename
  final anchor =
      html.AnchorElement(href: url)
        ..download = fileName
        ..style.display = 'none';

  // Add to document and trigger click
  html.document.body!.children.add(anchor);
  anchor.click();

  // Delay revoking the URL to ensure the download starts
  await Future.delayed(const Duration(seconds: 1));
  html.Url.revokeObjectUrl(url);
  anchor.remove();
}

Future<void> shareFileWeb(Uint8List bytes, String text) async {
  // ignore: unnecessary_null_comparison
  if (html.window.navigator.share != null) {
    final blob = html.Blob([bytes], 'image/png');
    final file = html.File([blob], 'qr.png', {'type': 'image/png'});
    final data = {
      'files': [file],
      'title': 'QR Code',
      'text': 'QR Code for: $text',
    };
    await html.window.navigator.share(data);
  } else {
    // Fallback: copy QR data to clipboard
    await html.window.navigator.clipboard!.writeText(text);
  }
}
