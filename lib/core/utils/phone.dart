/// Phone numbers reach the attendees collection from three places — CSV
/// import, the admin "add guest" form, and kiosk self-check-in — and each
/// historically stored a different shape for the same person
/// (`+91 98765 43210`, `919876543210`, `9876543210`).
///
/// Check-in looks guests up with an exact-match equality query, so any
/// mismatch silently fails to find a pre-registered attendee and registers
/// them again as a duplicate walk-in. Every read and write normalises
/// through here so that can't happen.
class PhoneUtils {
  const PhoneUtils._();

  /// Attendees enter 10 digits at the kiosk with no country code, so that's
  /// the canonical storage form. Kept as a constant since legacy records may
  /// carry it as a prefix.
  static const String defaultCountryCode = '91';

  /// Canonical storage form: the last 10 digits, no country code, no
  /// separators. Short/garbled input is returned as its bare digits rather
  /// than throwing — it simply won't match anything.
  static String normalize(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10
        ? digits.substring(digits.length - 10)
        : digits;
  }

  /// Every shape this number might *already* be stored as, for matching
  /// against records written before normalisation existed. Safe to hand
  /// straight to a Firestore `whereIn` — well under its 30-value cap.
  static List<String> lookupVariants(String raw) {
    final core = normalize(raw);
    if (core.isEmpty) return const [];

    return <String>{
      core,
      '$defaultCountryCode$core',
      '+$defaultCountryCode$core',
      '0$core',
      raw.trim(),
      // The shape the old import path produced: whitespace stripped only.
      raw.replaceAll(RegExp(r'\s+'), ''),
    }.where((variant) => variant.isNotEmpty).toList();
  }
}
