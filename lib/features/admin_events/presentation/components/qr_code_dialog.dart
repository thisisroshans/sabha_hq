import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/config/app_urls.dart';
import '../../../../core/models/event.dart';
import '../../../../core/providers/current_org_provider.dart';
import '../../../../core/utils/file_saver.dart';

class QrCodeDialog extends ConsumerWidget {
  const QrCodeDialog({super.key, required this.event});

  final Event event;

  // The check-in link needs BOTH ids — the public check-in flow has no
  // admin claims to resolve an org from (it's a signed-out/anonymous
  // guest), so orgId has to travel in the URL itself. See
  // check_in_screen.dart and app_router.dart's /check-in route.
  //
  // publicAppOrigin rather than Uri.base.origin: on the Android/iOS apps
  // Uri.base has no http origin at all, which produced a QR code nobody
  // could open. See app_urls.dart.
  String _checkInUrl(String orgId) =>
      '$publicAppOrigin/check-in?orgId=$orgId&eventId=${event.id}';

  Future<void> _downloadQrCode(BuildContext context, String checkInUrl) async {
    try {
      final validation = QrValidator.validate(
        data: checkInUrl,
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

      if (!context.mounted) return;

      // Browser download on web, native share sheet on Android/iOS — see
      // file_saver.dart.
      await saveFile(
        context: context,
        bytes: bytes,
        fileName: 'event_qr_${event.id}.png',
        mimeType: 'image/png',
      );

      if (!context.mounted) return;

      // The share sheet is its own confirmation on mobile (and the user
      // may well have cancelled it) — only the silent browser download
      // needs a "it worked" toast.
      if (kIsWeb) {
        _showSnackBar(
          context,
          message: 'QR downloaded successfully',
          color: Colors.green,
        );
      }
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

  void _copyLink(BuildContext context, String checkInUrl) {
    Clipboard.setData(ClipboardData(text: checkInUrl));

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
  Widget build(BuildContext context, WidgetRef ref) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    // Scale QR size dynamically based on screen width
    final qrSize = isMobile
        ? (screenSize.width * 0.55).clamp(180.0, 240.0)
        : 280.0;

    final orgIdState = ref.watch(currentOrgIdProvider);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16.0 : 40.0,
        vertical: 24.0,
      ),

      child: SizedBox(
        width: isMobile ? 400 : 450,
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: orgIdState.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SizedBox(
              height: 200,
              child: Center(child: Text('Could not load org: $e')),
            ),
            data: (orgId) {
              if (orgId == null) {
                return const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('No organization found for this account.'),
                  ),
                );
              }

              final checkInUrl = _checkInUrl(orgId);

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Check-In: ${event.title}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 18 : 20,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: QrImageView(
                        data: checkInUrl,
                        version: QrVersions.auto,
                        size: qrSize,
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

                    const SizedBox(height: 16),

                    Text(
                      'Attendees can scan this QR at the venue\n'
                      'or you can share the check-in link directly.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: isMobile ? 12 : 14,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
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
                              checkInUrl,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: isMobile ? 11 : 12,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy Link',
                            icon: const Icon(
                              Icons.copy,
                              size: 18,
                              color: Color(0xFFc51f43),
                            ),
                            onPressed: () => _copyLink(context, checkInUrl),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          // Builder so the share sheet anchors to this
                          // button on iPad, not to the whole dialog.
                          child: Builder(
                            builder: (buttonContext) => FilledButton.icon(
                              onPressed: () =>
                                  _downloadQrCode(buttonContext, checkInUrl),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFc51f43),
                              ),
                              icon: const Icon(
                                kIsWeb ? Icons.download : Icons.share,
                                size: 18,
                              ),
                              label: const Text(
                                kIsWeb ? 'Download QR' : 'Share QR',
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
