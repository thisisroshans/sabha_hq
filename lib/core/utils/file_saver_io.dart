import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Android/iOS half of file_saver.dart — see that file for why this is
/// split out.
Future<void> saveFile({
  required BuildContext context,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  // Read the anchor rect synchronously, before the first await — the
  // context may be unmounted (dialog closed) by the time the file is
  // written.
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;

  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles(
    [XFile(file.path, mimeType: mimeType, name: fileName)],
    subject: fileName,
    sharePositionOrigin: origin,
  );
}
