import 'package:flutter/material.dart';

/// Parses Event.branding['primaryColor'] (a user-typed hex string like
/// "#c51f43", validated in edit_event_screen.dart to at least start with
/// '#') into a Color. Written but never read until task #8 — the kiosk
/// hardcoded 0xFFc51f43 everywhere regardless of what an event's branding
/// actually said.
Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;

  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value'; // assume opaque if no alpha given

  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}
