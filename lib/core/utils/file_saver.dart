import 'dart:typed_data';

import 'package:flutter/widgets.dart';

// package:web (and the dart:js_interop it's built on) only exist when
// compiling for the browser — importing either unconditionally is a hard
// compile error on Android/iOS, which is exactly what broke the mobile
// builds when the CSV export and QR download were written web-first.
// The conditional import keeps each platform's implementation out of the
// other's build entirely.
import 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    as impl;

/// Hands a generated file (CSV export/template, QR code PNG) to the user
/// the way each platform expects: a browser download on web, the native
/// share sheet on Android/iOS (where "Save to Files", Drive, WhatsApp,
/// email etc. all live — there's no user-visible Downloads folder an app
/// can just drop a file into on iOS).
///
/// [context] anchors the iPad share popover — iPadOS throws if a share
/// sheet is presented without a source rect — so pass the context of the
/// button that triggered the save, before any `await`.
Future<void> saveFile({
  required BuildContext context,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  return impl.saveFile(
    context: context,
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
}
