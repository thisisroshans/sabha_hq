import 'package:flutter_test/flutter_test.dart';
import 'package:sabha_hq/core/utils/phone.dart';

void main() {
  group('PhoneUtils.normalize', () {
    test('collapses every shape of the same number to 10 bare digits', () {
      const expected = '9876543210';
      for (final input in [
        '9876543210',
        '+919876543210',
        '+91 98765 43210',
        '91 9876543210',
        '09876543210',
        '098765 43210',
        '(+91) 98765-43210',
      ]) {
        expect(PhoneUtils.normalize(input), expected, reason: 'input: $input');
      }
    });

    test('returns bare digits for short input instead of throwing', () {
      expect(PhoneUtils.normalize('12345'), '12345');
      expect(PhoneUtils.normalize(''), '');
      expect(PhoneUtils.normalize('not a number'), '');
    });
  });

  group('PhoneUtils.lookupVariants', () {
    test('covers the legacy shapes a record may already be stored as', () {
      final variants = PhoneUtils.lookupVariants('9876543210');

      expect(variants, contains('9876543210'));
      expect(variants, contains('919876543210'));
      expect(variants, contains('+919876543210'));
      expect(variants, contains('09876543210'));
    });

    test('a kiosk entry finds a guest imported with a +91 prefix', () {
      // The bug this fix exists for: CSV held "+91 98765 43210", the
      // attendee types the bare 10 digits at the kiosk.
      final typedAtKiosk = PhoneUtils.lookupVariants('9876543210');
      const storedByOldImport = '+919876543210';

      expect(typedAtKiosk, contains(storedByOldImport));
    });

    test('stays within the Firestore whereIn cap and has no duplicates', () {
      final variants = PhoneUtils.lookupVariants('+91 98765 43210');

      expect(variants.length, lessThanOrEqualTo(10));
      expect(variants.toSet().length, variants.length);
    });

    test('is empty for unusable input so no query is attempted', () {
      expect(PhoneUtils.lookupVariants(''), isEmpty);
      expect(PhoneUtils.lookupVariants('   '), isEmpty);
    });
  });
}
