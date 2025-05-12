import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
// import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'web_utils_stub.dart'
    if (dart.library.html) 'web_utils.dart'
    as web_utils;
import 'qr_history_item.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';

class QrIsolateParams {
  final String qrData;
  final Uint8List? logoBytes;
  QrIsolateParams(this.qrData, this.logoBytes);
}

Future<Uint8List> generateQrWithLogo(QrIsolateParams params) async {
  final qrValidationResult = QrValidator.validate(
    data: params.qrData,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.H,
  );
  if (qrValidationResult.status != QrValidationStatus.valid) {
    throw Exception('Invalid QR data.');
  }
  final qrPainter = QrPainter(
    data: params.qrData,
    version: QrVersions.auto,
    gapless: false,
    errorCorrectionLevel: QrErrorCorrectLevel.H,
  );
  final picData = await qrPainter.toImageData(400, format: ImageByteFormat.png);
  if (picData == null) throw Exception('Failed to generate QR image');
  final qrImage = img.decodeImage(picData.buffer.asUint8List());
  img.Image? paddedQrImage;
  if (qrImage != null) {
    const padding = 60;
    paddedQrImage = img.Image(
      qrImage.width + padding * 2,
      qrImage.height + padding * 2,
    );
    img.copyInto(paddedQrImage, qrImage, dstX: padding, dstY: padding);
  }
  if (params.logoBytes != null && paddedQrImage != null) {
    final logoImage = img.decodeImage(params.logoBytes!);
    if (logoImage != null) {
      final logoSize = (qrImage!.width * 0.15).toInt();
      final resizedLogo = img.copyResize(
        logoImage,
        width: logoSize,
        height: logoSize,
      );
      final x = (paddedQrImage.width - logoSize) ~/ 2;
      final y = (paddedQrImage.height - logoSize) ~/ 2;
      final logoBackground = img.Image(logoSize + 40, logoSize + 40);
      img.fill(logoBackground, img.getColor(255, 255, 255));
      img.copyInto(logoBackground, resizedLogo, dstX: 20, dstY: 20);
      img.copyInto(
        paddedQrImage,
        logoBackground,
        dstX: x - 20,
        dstY: y - 20,
        blend: false,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(paddedQrImage!));
}

class QRHomePage extends StatefulWidget {
  final Function(Locale) onLocaleChanged;
  const QRHomePage({super.key, required this.onLocaleChanged});

  @override
  State<QRHomePage> createState() => _QRHomePageState();
}

class _QRHomePageState extends State<QRHomePage> {
  final TextEditingController _controller = TextEditingController();
  File? _logoFile;
  Uint8List? _logoBytes;
  String? _qrImagePath;
  List<QRHistoryItem> _history = [];
  bool _isGenerating = false;
  String _qrText = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? historyJson = prefs.getStringList('qr_history');
    if (historyJson != null) {
      setState(() {
        _history =
            historyJson
                .map(
                  (e) => QRHistoryItem.fromJson(
                    Map<String, dynamic>.from(
                      (e.isNotEmpty)
                          ? Map<String, dynamic>.from(Uri.splitQueryString(e))
                          : {},
                    ),
                  ),
                )
                .toList();
      });
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> historyJson =
        _history
            .map(
              (e) => e
                  .toJson()
                  .entries
                  .map(
                    (kv) => "${kv.key}=${Uri.encodeComponent(kv.value ?? '')}",
                  )
                  .join('&'),
            )
            .toList();
    await prefs.setStringList('qr_history', historyJson);
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _logoFile = File(picked.path);
        _logoBytes = bytes;
      });
    }
  }

  Future<void> _generateAndSaveQR() async {
    if (_controller.text.isEmpty) return;
    setState(() => _isGenerating = true);
    try {
      // Native (non-web) image processing
      final qrValidationResult = QrValidator.validate(
        data: _controller.text,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      );
      if (qrValidationResult.status != QrValidationStatus.valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.invalidQRData)),
        );
        setState(() => _isGenerating = false);
        return;
      }
      final qrPainter = QrPainter(
        data: _controller.text,
        version: QrVersions.auto,
        gapless: false,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      );
      final picData = await qrPainter.toImageData(
        800,
        format: ImageByteFormat.png,
      );
      if (picData == null) throw Exception('Failed to generate QR image');
      final qrImage = img.decodeImage(picData.buffer.asUint8List());

      img.Image? paddedQrImage;
      if (qrImage != null) {
        const padding = 60;
        paddedQrImage = img.Image(
          qrImage.width + padding * 2,
          qrImage.height + padding * 2,
        );
        img.copyInto(paddedQrImage, qrImage, dstX: padding, dstY: padding);
      }
      if (!kIsWeb && _logoFile != null && paddedQrImage != null) {
        final logoBytes = await _logoFile!.readAsBytes();
        final logoImage = img.decodeImage(logoBytes);
        if (logoImage != null) {
          final logoSize = (qrImage!.width * 0.15).toInt();
          final resizedLogo = img.copyResize(
            logoImage,
            width: logoSize,
            height: logoSize,
          );
          final x = (paddedQrImage.width - logoSize) ~/ 2;
          final y = (paddedQrImage.height - logoSize) ~/ 2;
          final logoBackground = img.Image(logoSize + 40, logoSize + 40);
          img.fill(logoBackground, img.getColor(255, 255, 255));
          img.copyInto(logoBackground, resizedLogo, dstX: 20, dstY: 20);
          img.copyInto(
            paddedQrImage,
            logoBackground,
            dstX: x - 20,
            dstY: y - 20,
            blend: false,
          );
        }
      }

      // 3. Save the final image
      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.qrDownloaded)),
          );
          await Future.delayed(Duration.zero);
        }
        // Move all image processing to an isolate
        final encodedBytes = await compute(
          generateQrWithLogo,
          QrIsolateParams(_controller.text, _logoBytes),
        );
        await web_utils.saveFileWeb(
          encodedBytes,
          'qr_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        setState(() {
          _qrImagePath = null; // No file path on web
          _history.insert(
            0,
            QRHistoryItem(
              data: _controller.text,
              imagePath: null,
              logoPath: null,
            ),
          );
        });
        await _saveHistory();
        setState(() => _isGenerating = false);
        return;
      }

      String? savePath;
      if (Platform.isWindows) {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Save QR Code',
          fileName: 'qr_${DateTime.now().millisecondsSinceEpoch}.png',
          type: FileType.custom,
          allowedExtensions: ['png'],
        );
        if (result == null) {
          setState(() => _isGenerating = false);
          return;
        }
        savePath = result;
      } else {
        final directory = await getSaveDirectory();
        final fileName = 'qr_${DateTime.now().millisecondsSinceEpoch}.png';
        savePath = '${directory.path}/$fileName';
      }

      final file = File(savePath);
      final finalImageBytes = img.encodePng(paddedQrImage!);
      await file.writeAsBytes(finalImageBytes);

      if (!Platform.isWindows) {
        await ImageGallerySaverPlus.saveFile(file.path);
      }

      setState(() {
        _qrImagePath = file.path;
        _history.insert(
          0,
          QRHistoryItem(
            data: _controller.text,
            imagePath: file.path,
            logoPath: _logoFile?.path,
          ),
        );
      });

      await _saveHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.qrSaved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _shareQR() async {
    if (kIsWeb) {
      try {
        final bytes = await _getCurrentQRBytes();
        await web_utils.shareFileWeb(bytes, _controller.text);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Center(
                child: Text(
                  'Sharing is not supported on this browser or failed. QR data copied to clipboard.',
                ),
              ),
            ),
          );
        }
      }
      return;
    }
    if (_qrImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseGenerateFirst),
        ),
      );
      return;
    }

    try {
      final file = File(_qrImagePath!);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Center(
                child: Text(AppLocalizations.of(context)!.qrFileNotFound),
              ),
            ),
          );
        }
        return;
      }

      final result = await Share.shareXFiles(
        [XFile(_qrImagePath!)],
        text: 'QR Code for: ${_controller.text}',
        subject: 'QR Code',
      );

      if (result.status == ShareResultStatus.dismissed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Center(
                child: Text(AppLocalizations.of(context)!.sharingCancelled),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Center(child: Text('Error sharing: $e'))),
        );
      }
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.clearHistory),
            content: Text(AppLocalizations.of(context)!.clearHistoryConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(AppLocalizations.of(context)!.clear),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      setState(() {
        _history.clear();
      });
      await _saveHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Center(
              child: Text(AppLocalizations.of(context)!.historyCleared),
            ),
          ),
        );
      }
    }
  }

  Future<Uint8List> _getCurrentQRBytes() async {
    final qrValidationResult = QrValidator.validate(
      data: _controller.text,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
    );
    if (qrValidationResult.status != QrValidationStatus.valid) {
      throw Exception('Invalid QR data.');
    }

    final qrPainter = QrPainter(
      data: _controller.text,
      version: QrVersions.auto,
      gapless: false,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
    );
    final picData = await qrPainter.toImageData(
      800,
      format: ImageByteFormat.png,
    );
    if (picData == null) throw Exception('Failed to generate QR image');
    final qrImage = img.decodeImage(picData.buffer.asUint8List());

    img.Image? paddedQrImage;
    if (qrImage != null) {
      const padding = 60;
      paddedQrImage = img.Image(
        qrImage.width + padding * 2,
        qrImage.height + padding * 2,
      );
      img.copyInto(paddedQrImage, qrImage, dstX: padding, dstY: padding);
    }

    if ((kIsWeb ? _logoBytes != null : _logoFile != null) &&
        paddedQrImage != null) {
      Uint8List logoBytes;
      if (kIsWeb) {
        if (_logoBytes == null) return Uint8List(0);
        logoBytes = _logoBytes!;
      } else {
        logoBytes = await _logoFile!.readAsBytes();
      }
      final logoImage = img.decodeImage(logoBytes);
      if (logoImage != null) {
        final logoSize = (qrImage!.width * 0.15).toInt();
        final resizedLogo = img.copyResize(
          logoImage,
          width: logoSize,
          height: logoSize,
        );
        final x = (paddedQrImage.width - logoSize) ~/ 2;
        final y = (paddedQrImage.height - logoSize) ~/ 2;
        final logoBackground = img.Image(logoSize + 40, logoSize + 40);
        img.fill(logoBackground, img.getColor(255, 255, 255));
        img.copyInto(logoBackground, resizedLogo, dstX: 20, dstY: 20);
        img.copyInto(
          paddedQrImage,
          logoBackground,
          dstX: x - 20,
          dstY: y - 20,
          blend: false,
        );
      }
    }
    return Uint8List.fromList(img.encodePng(paddedQrImage!));
  }

  // Helper to get image size
  Future<Size> _getImageSize(dynamic imageSource) async {
    Uint8List bytes;
    if (kIsWeb) {
      bytes = imageSource as Uint8List;
    } else {
      bytes = await (imageSource as File).readAsBytes();
    }
    final decoded = await decodeImageFromList(bytes);
    return Size(decoded.width.toDouble(), decoded.height.toDouble());
  }

  Widget _buildQR({
    required String data,
    File? logoFile,
    Uint8List? logoBytes,
    double size = 200,
  }) {
    final logoPadding = 20.0;
    final logoMaxPercent = 0.15; // 15% of QR size
    final hasLogo = kIsWeb ? (logoBytes != null) : (logoFile != null);
    final imageSource = kIsWeb ? logoBytes : logoFile;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          QrImageView(
            data: data,
            version: QrVersions.auto,
            size: size * 0.8,
            gapless: false,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
            // No embeddedImage here, we'll overlay manually
            backgroundColor: Colors.white,
          ),
          if (hasLogo)
            LayoutBuilder(
              builder: (context, constraints) {
                final qrRenderSize = size * 0.8;
                // Calculate max logo size
                final maxLogoWidth = qrRenderSize * logoMaxPercent;
                final maxLogoHeight = qrRenderSize * logoMaxPercent;
                return FutureBuilder<Size>(
                  future: _getImageSize(imageSource),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();
                    final original = snapshot.data!;
                    // Calculate new size preserving aspect ratio
                    double logoWidth = maxLogoWidth;
                    double logoHeight = maxLogoHeight;
                    final aspect = original.width / original.height;
                    if (aspect > 1) {
                      // Wider than tall
                      logoHeight = logoWidth / aspect;
                    } else {
                      // Taller than wide or square
                      logoWidth = logoHeight * aspect;
                    }
                    return Container(
                      width: logoWidth + logoPadding * 1.2,
                      height: logoHeight + logoPadding * 1.2,
                      decoration: BoxDecoration(
                        // color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child:
                            kIsWeb
                                ? Image.memory(
                                  logoBytes!,
                                  width: logoWidth,
                                  height: logoHeight,
                                  fit: BoxFit.contain,
                                )
                                : Image.file(
                                  logoFile!,
                                  width: logoWidth,
                                  height: logoHeight,
                                  fit: BoxFit.contain,
                                ),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qrSize = MediaQuery.of(context).size.width * 0.4;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          PopupMenuButton<Locale>(
            icon: const Icon(Icons.language),
            onSelected: widget.onLocaleChanged,
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: Locale('en'),
                    child: Text('English'),
                  ),
                  const PopupMenuItem(
                    value: Locale('ar'),
                    child: Text('العربية'),
                  ),
                ],
          ),
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearHistory,
              tooltip: l10n.clearHistory,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: l10n.enterData,
                hintText: l10n.enterData,
                prefixIcon: const Icon(Icons.qr_code),
              ),
              onChanged: (value) {
                setState(() {
                  _qrText = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(Icons.image),
                  label: Text(l10n.pickLogo),
                ),
                if (_logoFile != null || _logoBytes != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          kIsWeb
                              ? (_logoBytes != null
                                  ? Image.memory(_logoBytes!)
                                  : const SizedBox())
                              : (_logoFile != null
                                  ? Image.file(_logoFile!)
                                  : const SizedBox()),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed:
                  _qrText.isEmpty
                      ? null
                      : () {
                        setState(() {});
                      },
              icon: const Icon(Icons.qr_code),
              label: Text(l10n.generateQR),
            ),
            const SizedBox(height: 16),
            if (_controller.text.isNotEmpty)
              _buildQR(
                data: _controller.text,
                logoFile: _logoFile,
                logoBytes: _logoBytes,
                size: qrSize,
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateAndSaveQR,
                  icon: const Icon(Icons.save),
                  label: Text(l10n.save),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _qrImagePath == null ? null : _shareQR,
                  icon: const Icon(Icons.share),
                  label: Text(l10n.share),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            Text(
              l10n.history,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            if (_history.isEmpty) Text(l10n.noHistory),
            for (final item in _history)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          item.imagePath != null &&
                                  !kIsWeb &&
                                  File(item.imagePath!).existsSync()
                              ? Image.file(
                                File(item.imagePath!),
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                              )
                              : const Icon(Icons.qr_code),
                    ),
                  ),
                  title: Text(
                    item.data,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    setState(() {
                      _controller.text = item.data;
                      _logoFile =
                          item.logoPath != null ? File(item.logoPath!) : null;
                      _qrImagePath = item.imagePath;
                    });
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.share),
                    onPressed:
                        item.imagePath != null &&
                                !kIsWeb &&
                                File(item.imagePath!).existsSync()
                            ? () => Share.shareXFiles([XFile(item.imagePath!)])
                            : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<Directory> getSaveDirectory() async {
  if (Platform.isWindows) {
    // Use Desktop directory for Windows
    final userProfile = Platform.environment['USERPROFILE'];
    final desktopDir = Directory('$userProfile\\Desktop');
    if (await desktopDir.exists()) {
      return desktopDir;
    }
    return await getApplicationDocumentsDirectory();
  } else {
    return await getApplicationDocumentsDirectory();
  }
}
