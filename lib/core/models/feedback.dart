import 'package:freezed_annotation/freezed_annotation.dart';
import 'converters/timestamp_converter.dart';

part 'feedback.freezed.dart';
part 'feedback.g.dart';

@freezed
abstract class EventFeedback with _$EventFeedback {
  const factory EventFeedback({
    required String id,
    required String eventId,
    required int rating,
    String? comment,
    @TimestampConverter() required DateTime submittedAt,
  }) = _EventFeedback;

  factory EventFeedback.fromJson(Map<String, dynamic> json) =>
      _$EventFeedbackFromJson(json);
}
