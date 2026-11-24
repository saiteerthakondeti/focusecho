import '../../core/models/distraction_event.dart';
import '../../core/models/focus_session.dart';

class StudyMetrics {
  const StudyMetrics(this.today, this.yesterday, this.previousAtThisTime,
      this.hour, this.samples, this.hasDurations);
  final int today, yesterday, previousAtThisTime, samples;
  final int? hour;
  final bool hasDurations;
  static StudyMetrics calculate(List<DistractionEvent> events,
      List<FocusSession> sessions, DateTime now) {
    final midnight = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final priorCutoff = DateTime(
        now.year, now.month, now.day - 1, now.hour, now.minute, now.second);
    final intervals = <({DateTime start, DateTime end})>[];
    for (final e in events) {
      final start = e.triggeredAt.toLocal();
      final seconds = e.timeAwaySeconds ?? e.recoveryTimeSeconds;
      final end = e.recoveredAt?.toLocal() ??
          (seconds == null ? null : start.add(Duration(seconds: seconds)));
      if (end != null && end.isAfter(start)) {
        intervals.add((start: start, end: end));
      }
    }
    intervals.sort((a, b) => a.start.compareTo(b.start));
    int elapsed(DateTime from, DateTime until) {
      var cursor = from;
      var seconds = 0;
      for (final span in intervals) {
        final start = span.start.isAfter(cursor) ? span.start : cursor;
        final end = span.end.isBefore(until) ? span.end : until;
        if (end.isAfter(start)) {
          seconds += end.difference(start).inSeconds;
          cursor = end;
        }
      }
      return seconds;
    }

    final groups = <int, ({int count, int seconds, int drift})>{};
    for (final s in sessions) {
      final start = s.startTime.toLocal(), end = s.endTime?.toLocal();
      if (s.status != SessionStatus.completed ||
          end == null ||
          end.isAfter(now) ||
          start.isBefore(now.subtract(const Duration(days: 7)))) {continue;}
      final duration = end.difference(start).inSeconds;
      if (duration < 60) continue;
      final hour = start.hour;
      final old = groups[hour] ?? (count: 0, seconds: 0, drift: 0);
      groups[hour] = (
        count: old.count + 1,
        seconds: old.seconds + duration,
        drift: old.drift + elapsed(start, end)
      );
    }
    final ranked = groups.entries.where((e) => e.value.count >= 3).toList()
      ..sort((a, b) => (a.value.drift / a.value.seconds)
          .compareTo(b.value.drift / b.value.seconds));
    final best = ranked.length >= 2 &&
            ranked.first.value.drift / ranked.first.value.seconds <
                ranked[1].value.drift / ranked[1].value.seconds
        ? ranked.first
        : null;
    return StudyMetrics(elapsed(midnight, now), elapsed(yesterday, midnight),
        elapsed(yesterday, priorCutoff), best?.key, best?.value.count ?? 0, intervals.any((v)=>v.end.isAfter(yesterday)&&v.start.isBefore(now)));
  }
}
