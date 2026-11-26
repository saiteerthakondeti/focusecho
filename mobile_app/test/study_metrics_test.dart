import 'package:flutter_test/flutter_test.dart';
import 'package:focus_echo_ai/core/models/distraction_event.dart';
import 'package:focus_echo_ai/core/models/focus_session.dart';
import 'package:focus_echo_ai/features/analytics/study_metrics.dart';

void main() {
  final now = DateTime(2026, 11, 24, 12);
  DistractionEvent drift(String id, DateTime start, [int? seconds]) =>
      DistractionEvent(
          id: id,
          sessionId: id,
          appLabel: 'Video',
          packageName: 'video',
          riskScore: 'low',
          triggeredAt: start,
          timeAwaySeconds: seconds);
  test(
      'Comparison splits midnight, merges overlaps and excludes unfinished intervals',
      () {
    final result = StudyMetrics.calculate([
      drift('a', DateTime(2026, 11, 23, 23, 59), 120),
      drift('b', DateTime(2026, 11, 24), 30),
      drift('c', DateTime(2026, 11, 23, 9), 40),
      drift('d', DateTime(2026, 11, 24, 11)),
    ], [], now);
    expect([result.today, result.yesterday, result.previousAtThisTime],
        [60, 100, 40]);
    expect(result.hour, isNull);
    final midnight = DateTime(now.year, now.month, now.day);
    FocusSession session(int startHour, int? endHour) => FocusSession(
          id: 'session-$startHour',
          userId: 'u',
          productiveApp: 'Notes',
          startTime: midnight.add(Duration(hours: startHour)),
          endTime:
              endHour == null ? null : midnight.add(Duration(hours: endHour)),
          status:
              endHour == null ? SessionStatus.active : SessionStatus.completed,
        );
    final focus = StudyMetrics.recordedFocus([
      session(-3, 2),
      session(1, 3),
      session(-24, null),
      session(11, 14),
    ]);
    expect(focus(midnight, now), 4 * 3600);
    final boundary = now.subtract(const Duration(days: 7));
    final recoveryEvents = [
      drift('previous', boundary.subtract(const Duration(seconds: 1))),
      drift('quick', boundary)
          .copyWith(isRecovered: true, recoveryTimeSeconds: 10),
      drift('slow', midnight)
          .copyWith(isRecovered: true, recoveryTimeSeconds: 30),
      drift('future', now.add(const Duration(hours: 1))),
    ];
    final current = StudyMetrics.recoveryStats(recoveryEvents, boundary, now);
    expect((current.total, current.rate, current.median), (2, 50.0, 20.0));
    final prior = StudyMetrics.recoveryStats(
        recoveryEvents, boundary.subtract(const Duration(days: 7)), boundary);
    expect((prior.total, prior.rate), (1, 0.0));
  });
  test(
      'Hour suggestion requires two sufficiently sampled windows and a measurable difference',
      () {
    final sessions = <FocusSession>[];
    final events = <DistractionEvent>[];
    for (final day in [20, 21, 22]) {
      for (final hour in [7, 15]) {
        final start = DateTime(2026, 11, day, hour);
        sessions.add(FocusSession(
            id: '$day-$hour',
            userId: 'test',
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            productiveApp: 'Notes',
            intent: '',
            status: SessionStatus.completed));
        events.add(drift('$day-$hour', start, hour == 7 ? 60 : 600));
      }
    }
    expect(StudyMetrics.calculate(events, sessions, now).hour, 7);
    expect(StudyMetrics.calculate([], sessions, now).hour, isNull);
    expect(StudyMetrics.calculate(events, sessions.take(4).toList(), now).hour,
        isNull);
  });
}
