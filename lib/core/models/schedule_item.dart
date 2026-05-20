import 'package:freezed_annotation/freezed_annotation.dart';
import 'converters/timestamp_converter.dart';

part 'schedule_item.freezed.dart';
part 'schedule_item.g.dart';

@freezed
abstract class ScheduleItem with _$ScheduleItem {
  const factory ScheduleItem({
    required String id,
    required String eventId,
    required String title,
    @TimestampConverter() required DateTime startTime,
    @TimestampConverter() required DateTime endTime,
    String? speaker,
    String? description,
  }) = _ScheduleItem;

  factory ScheduleItem.fromJson(Map<String, dynamic> json) =>
      _$ScheduleItemFromJson(json);
}
