import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Session-owned snapshot. Editing a future plan cannot change an active intervention.
class PlannedFocus {
  const PlannedFocus(
      this.id, this.subject, this.nextStep, this.minutes, this.apps, this.sites,
      [this.remaining = const []]);
  final String id, subject, nextStep;
  final int minutes;
  final List<String> apps, sites, remaining;
  String get objective =>
      nextStep.isEmpty ? subject : '$subject · Next: $nextStep';
  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'step': nextStep,
        'minutes': minutes,
        'apps': apps,
        'sites': sites,
        'remaining': remaining
      };
  static List<String> strings(dynamic value) =>
      value is List ? value.whereType<String>().toList() : [];
  factory PlannedFocus.fromJson(Map<String, dynamic> row) => PlannedFocus(
      row['id'],
      row['subject'],
      row['step'] ?? '',
      row['minutes'] ?? 25,
      strings(row['apps']),
      strings(row['sites']),
      strings(row['remaining']));
  factory PlannedFocus.fromSlot(Map<String, dynamic> row) {
    final details = row['details'] as Map? ?? {};
    final done = strings(details['done']);
    final next =
        strings(details['steps']).where((v) => !done.contains(v)).firstOrNull;
    final duration = DateTime.parse(row['ends_at'])
        .difference(DateTime.parse(row['starts_at']))
        .inMinutes;
    return PlannedFocus(
        row['id'],
        row['subject'],
        next ?? '',
        duration,
        strings(details['apps']),
        strings(details['sites']),
        strings(details['steps']).where((v) => !done.contains(v)).toList());
  }
}

class PlannerSessions {
  PlannerSessions(this.prefs, this.user);
  final SharedPreferences prefs;
  final String user;
  String get key => 'planner_sessions_$user';
  Map<String, dynamic> get records =>
      jsonDecode(prefs.getString(key) ?? '{}') as Map<String, dynamic>;
  PlannedFocus? task(String sessionId) {
    final row = records[sessionId];
    return row == null || row['id'] == null ? null : PlannedFocus.fromJson(row);
  }

  Future<void> link(String sessionId, PlannedFocus task) async {
    await prefs.setString(
        key, jsonEncode(records..[sessionId] = task.toJson()));
  }

  Future<void> finish(String sessionId, Map<String, int> times, String mode,
      bool cancelled) async {
    final data = records;
    data[sessionId] = {
      ...?data[sessionId] as Map?,
      ...times,
      'mode': mode,
      'cancelled': cancelled,
      'pending': true
    };
    await prefs.setString(key, jsonEncode(data));
  }

  /// A completed snapshot belongs to the device that recorded the session.
  /// Keep local edits queued until the owned parent row acknowledges the write.
  Future<void> synchronize({
    required Future<bool> Function(String, Map<String, dynamic>) upload,
    required Future<Map<String, dynamic>> Function() download,
    required bool Function() allowed,
  }) async {
    if (!allowed()) return;
    for (final entry in records.entries) {
      final snapshot = Map<String, dynamic>.from(entry.value);
      if (snapshot['focus_seconds'] == null || snapshot['pending'] == false)
        continue;
      if (!allowed()) return;
      if (!await upload(entry.key, Map.of(snapshot)..remove('pending')))
        continue;
      if (!allowed()) return;
      final latest = records;
      if (jsonEncode(latest[entry.key]) == jsonEncode(snapshot)) {
        latest[entry.key]['pending'] = false;
        await prefs.setString(key, jsonEncode(latest));
      }
    }
    if (!allowed()) return;
    final cloud = await download();
    if (!allowed()) return;
    final latest = records;
    for (final entry in cloud.entries) {
      final current = latest[entry.key];
      if (current == null || current['pending'] == false) {
        latest[entry.key] = {...entry.value as Map, 'pending': false};
      }
    }
    await prefs.setString(key, jsonEncode(latest));
  }
}
