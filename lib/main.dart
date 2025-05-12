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
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Generator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3), // Material Blue
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF2196F3),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2196F3), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        scaffoldBackgroundColor: Colors.white,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: Colors.white,
        ),
        dividerTheme: const DividerThemeData(
          color: Colors.grey,
          thickness: 0.5,
        ),
      ),
      home: const QRHomePage(),
    );
  }
}

class QRHistoryItem {
  final String data;
  final String? imagePath;
  final String? logoPath;
  QRHistoryItem({required this.data, this.imagePath, this.logoPath});

  Map<String, dynamic> toJson() => {
    'data': data,
    'imagePath': imagePath,
    'logoPath': logoPath,
  };
  factory QRHistoryItem.fromJson(Map<String, dynamic> json) => QRHistoryItem(
    data: json['data'],
    imagePath: json['imagePath'],
    logoPath: json['logoPath'],
  );
}

class QRHomePage extends StatefulWidget {
  const QRHomePage({super.key});

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
      final qrValidationResult = QrValidator.validate(
        data: _controller.text,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      );
      if (qrValidationResult.status != QrValidationStatus.valid) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid QR data.')));
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

      // 1. Decode the QR image
      final qrImage = img.decodeImage(picData.buffer.asUint8List());

      // Add padding around the QR image
      img.Image? paddedQrImage;
      if (qrImage != null) {
        const padding = 60;
        paddedQrImage = img.Image(
          qrImage.width + padding * 2,
          qrImage.height + padding * 2,
        );
        img.copyInto(paddedQrImage, qrImage, dstX: padding, dstY: padding);
      }

      // 2. If logo is selected, overlay it with padding
      if (_logoFile != null && paddedQrImage != null) {
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
      final finalImageBytes = img.encodePng(paddedQrImage!);

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
      await file.writeAsBytes(finalImageBytes);

      if (!Platform.isWindows) {
        await ImageGallerySaver.saveFile(file.path);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('QR saved successfully!')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _shareQR() async {
    if (_qrImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please generate and save the QR code first.'),
        ),
      );
      return;
    }

    try {
      final file = File(_qrImagePath!);
      if (!await file.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR code file not found.')),
        );
        return;
      }

      final result = await Share.shareXFiles(
        [XFile(_qrImagePath!)],
        text: 'QR Code for: ${_controller.text}',
        subject: 'QR Code',
      );

      if (result.status == ShareResultStatus.dismissed) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sharing cancelled')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sharing: $e')));
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear History'),
            content: const Text(
              'Are you sure you want to clear all QR code history?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      setState(() {
        _history.clear();
      });
      await _saveHistory();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('History cleared')));
    }
  }

  Widget _buildQR({required String data, File? logoFile, double size = 200}) {
    final logoPadding = 20.0;
    final logoMaxPercent = 0.15; // 15% of QR size
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
          if (logoFile != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final qrRenderSize = size * 0.8;
                // Calculate max logo size
                final maxLogoWidth = qrRenderSize * logoMaxPercent;
                final maxLogoHeight = qrRenderSize * logoMaxPercent;
                return FutureBuilder<Size>(
                  future: _getImageSize(logoFile),
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
                      width: logoWidth + logoPadding * 1.5,
                      height: logoHeight + logoPadding * 1.5,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Image.file(
                          logoFile,
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

  // Helper to get image size
  Future<Size> _getImageSize(File file) async {
    final bytes = await file.readAsBytes();
    final decoded = await decodeImageFromList(bytes);
    return Size(decoded.width.toDouble(), decoded.height.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final qrSize = MediaQuery.of(context).size.width * 0.4;
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Generator'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearHistory,
              tooltip: 'Clear History',
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
              decoration: const InputDecoration(
                labelText: 'Enter data for QR',
                hintText: 'Enter URL, text, or other data',
                prefixIcon: Icon(Icons.qr_code),
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
                  label: const Text('Pick Logo (optional)'),
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
              label: const Text('Generate QR Code'),
            ),
            const SizedBox(height: 16),
            if (_controller.text.isNotEmpty)
              _buildQR(
                data: _controller.text,
                logoFile: _logoFile,
                size: qrSize,
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateAndSaveQR,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _qrImagePath == null ? null : _shareQR,
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const Text(
              'History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            if (_history.isEmpty) const Text('No QR history yet.'),
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
