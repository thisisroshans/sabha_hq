import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web/web.dart' as web;

import '../../../../core/models/event.dart';

class QrCodeDialog extends StatelessWidget {
  const QrCodeDialog({super.key, required this.event});

  final Event event;

  String get _checkInUrl => '${Uri.base.origin}/check-in?eventId=${event.id}';

  Future<void> _downloadQrCode(BuildContext context) async {
    try {
      final validation = QrValidator.validate(
        data: _checkInUrl,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      );

      if (validation.status != QrValidationStatus.valid) {
        throw Exception('Invalid QR data');
      }

      final painter = QrPainter.withQr(
        qr: validation.qrCode!,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFFc51f43),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFFc51f43),
        ),
      );

      // High resolution export
      final ui.Image image = await painter.toImage(2048);

      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        throw Exception('Failed to generate QR image');
      }

      final Uint8List bytes = byteData.buffer.asUint8List();

      // Create blob
      final blob = web.Blob(
        [bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'image/png'),
      );

      // Create downloadable URL
      final url = web.URL.createObjectURL(blob);

      // Create hidden anchor
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = 'event_qr_${event.id}.png'
        ..style.display = 'none';

      // Append -> Click -> Remove
      web.document.body?.append(anchor);

      anchor.click();

      anchor.remove();

      // Cleanup memory
      web.URL.revokeObjectURL(url);

      if (!context.mounted) return;

      _showSnackBar(
        context,
        message: 'QR downloaded successfully',
        color: Colors.green,
      );
    } catch (e) {
      debugPrint('QR DOWNLOAD ERROR: $e');

      if (!context.mounted) return;

      _showSnackBar(
        context,
        message: 'Failed to download QR',
        color: Colors.red,
      );
    }
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _checkInUrl));

    _showSnackBar(
      context,
      message: 'Check-in link copied!',
      color: Colors.green,
    );
  }

  void _showSnackBar(
    BuildContext context, {
    required String message,
    required Color color,
  }) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: AlertDialog(
        title: Text(
          'Check-In: ${event.title}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),

        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: _checkInUrl,
                  version: QrVersions.auto,
                  size: 300,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFFc51f43),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFFc51f43),
                  ),
                  backgroundColor: Colors.white,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Attendees can scan this QR at the venue\n'
                'or you can share the check-in link directly.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.4),
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _checkInUrl,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                    ),

                    IconButton(
                      tooltip: 'Copy Link',
                      icon: const Icon(
                        Icons.copy,
                        size: 20,
                        color: Color(0xFFc51f43),
                      ),
                      onPressed: () => _copyLink(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        actions: [
          FilledButton.icon(
            onPressed: () => _downloadQrCode(context),
            icon: const Icon(Icons.download),
            label: const Text('Download QR'),
          ),

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
