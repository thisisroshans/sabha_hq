import 'package:freezed_annotation/freezed_annotation.dart';
import 'converters/timestamp_converter.dart';

part 'attendee.freezed.dart';
part 'attendee.g.dart';

@freezed
abstract class Attendee with _$Attendee {
  const factory Attendee({
    required String id,
    required String eventId,
    required String name,
    required String email,
    required String phone,

    @Default('guest') String role,
    @Default(false) bool isCheckedIn,
    @OptionalTimestampConverter() DateTime? checkInTime,
  }) = _Attendee;

  factory Attendee.fromJson(Map<String, dynamic> json) =>
      _$AttendeeFromJson(json);
}
