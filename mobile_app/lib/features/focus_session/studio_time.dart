import '../../core/models/distraction_event.dart';

/// Partition wall-clock seconds. Breaks override an open drift, and overlapping
/// events from two devices occupy the same seconds only once.
Map<String, int> studioTime(
    DateTime start,
    DateTime end,
    Iterable<DistractionEvent> events,
    Map<String, dynamic> pauses,
    Map<String, dynamic> returns) {
  final elapsed = end.difference(start).inSeconds.clamp(0, 1 << 31);
  final changes = <int, List<(int, int)>>{0: [], elapsed: []};
  void span(DateTime from, DateTime until, int phase) {
    final a = from.difference(start).inSeconds.clamp(0, elapsed);
    final b = until.difference(start).inSeconds.clamp(0, elapsed);
    if (b <= a) return;
    changes.putIfAbsent(a, () => []).add((phase, 1));
    changes.putIfAbsent(b, () => []).add((phase, -1));
  }

  for (final e in events) {
    final duration = e.timeAwaySeconds ?? e.recoveryTimeSeconds;
    final until = duration == null
        ? e.recoveredAt ?? end
        : e.triggeredAt.add(Duration(seconds: duration));
    final action = DateTime.tryParse(returns[e.id]?.toString() ?? '');
    if (action != null &&
        !action.isBefore(e.triggeredAt) &&
        action.isBefore(until)) {
      span(e.triggeredAt, action, 1);
      span(action, until, 2);
    } else {
      span(e.triggeredAt, until, 1);
    }
  }
  for (final row in [
    ...?pauses['windows'] as List?,
    if (pauses['since'] != null) pauses
  ]) {
    final since = DateTime.tryParse(row['since']?.toString() ?? '');
    if (since != null) {
      span(since, DateTime.tryParse(row['until']?.toString() ?? '') ?? end,
          row['reason'] == 'Paused' ? 3 : 4);
    }
  }
  final active = List.filled(5, 0);
  final totals = List.filled(5, 0);
  var previous = 0;
  for (final point in changes.keys.toList()..sort()) {
    final phase = active.lastIndexWhere((n) => n > 0);
    totals[phase < 0 ? 0 : phase] += point - previous;
    for (final (index, delta) in changes[point]!) {
      active[index] += delta;
    }
    previous = point;
  }
  return {
    'focus_seconds': totals[0],
    'recorded_drift_seconds': totals[1],
    'recovering_seconds': totals[2],
    'paused_seconds': totals[3],
    'break_seconds': totals[4],
    'wall_seconds': elapsed
  };
}
