import 'package:freezed_annotation/freezed_annotation.dart';
import 'converters/timestamp_converter.dart';

part 'event.freezed.dart';
part 'event.g.dart';

@freezed
abstract class Event with _$Event {
  const factory Event({
    required String id,
    required String title,
    @TimestampConverter() required DateTime date,
    required String location,

    @Default({}) Map<String, dynamic> branding,
    @Default(0) int totalRegistered,
    @Default(0) int totalCheckedIn,
  }) = _Event;

  factory Event.fromJson(Map<String, dynamic> json) => _$EventFromJson(json);
}
