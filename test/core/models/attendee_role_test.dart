import 'package:flutter_test/flutter_test.dart';
import 'package:sabha_hq/core/models/attendee.dart';

void main() {
  group('AttendeeRole', () {
    test('guests are shown as Movers, participants as Pitchers', () {
      expect(AttendeeRole.label('guest'), 'Mover');
      expect(AttendeeRole.label('participant'), 'Pitcher');
      expect(AttendeeRole.pluralLabel('guest'), 'Movers');
      expect(AttendeeRole.pluralLabel('participant'), 'Pitchers');
    });

    test('stored values are unchanged by the rename', () {
      expect(AttendeeRole.mover, 'guest');
      expect(AttendeeRole.pitcher, 'participant');
    });

    test('a doc with no role reads as a Mover', () {
      final attendee = Attendee.fromMap({'name': 'Ravi'}, 'att-1');
      expect(attendee.role, AttendeeRole.mover);
      expect(attendee.roleLabel, 'Mover');
      expect(attendee.isPitcher, isFalse);
    });

    test('CSV import accepts both the new labels and the old values', () {
      expect(AttendeeRole.fromInput('Pitcher'), AttendeeRole.pitcher);
      expect(AttendeeRole.fromInput(' participant '), AttendeeRole.pitcher);
      expect(AttendeeRole.fromInput('Mover'), AttendeeRole.mover);
      expect(AttendeeRole.fromInput('GUEST'), AttendeeRole.mover);
      expect(AttendeeRole.fromInput(''), AttendeeRole.mover);
    });

    test('an exported label round-trips through import', () {
      for (final role in [AttendeeRole.mover, AttendeeRole.pitcher]) {
        expect(AttendeeRole.fromInput(AttendeeRole.label(role)), role);
      }
    });
  });
}
