// Server-side port of lib/core/utils/phone.dart's PhoneUtils. Dart and
// Node can't share code directly, so this is deliberately kept in sync by
// hand — same logic, same magic constants (10-digit canonical form, '91'
// default country code). If one changes, change both.
//
// This is the version that actually matters now: task #6 moves check-in
// writes here, off the client, so this is the copy that decides what
// counts as "the same phone number" for real.

const DEFAULT_COUNTRY_CODE = "91";

export function normalizePhone(raw: string): string {
  const digits = raw.replace(/\D/g, "");
  return digits.length > 10 ? digits.slice(-10) : digits;
}

export function phoneLookupVariants(raw: string): string[] {
  const core = normalizePhone(raw);
  if (!core) return [];

  const variants = new Set(
    [
      core,
      `${DEFAULT_COUNTRY_CODE}${core}`,
      `+${DEFAULT_COUNTRY_CODE}${core}`,
      `0${core}`,
      raw.trim(),
      raw.replace(/\s+/g, ""),
    ].filter((v) => v.length > 0)
  );

  return [...variants];
}
