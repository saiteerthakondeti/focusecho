import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Moves device-cached Planner/Studio state when a guest identity is linked.
/// Existing destination rows win on ID collisions; migrated Planner rows stay
/// dirty so the authenticated account can upload them through normal RLS.
Future<void> migrateWorkspacePreferences(
  SharedPreferences prefs,
  String fromUserId,
  String toUserId,
) async {
  if (fromUserId == toUserId) return;

  final oldSlotsKey = 'study_slots_$fromUserId';
  final newSlotsKey = 'study_slots_$toUserId';
  final oldSlots = _decodeRows(prefs.getString(oldSlotsKey));
  if (oldSlots.isNotEmpty) {
    final destination = _decodeRows(prefs.getString(newSlotsKey));
    final merged = <String, Map<String, dynamic>>{
      for (final row in destination)
        if (row['id'] is String) row['id'] as String: row,
    };
    for (final row in oldSlots) {
      final id = row['id'];
      if (id is! String || merged.containsKey(id)) continue;
      merged[id] = {...row, 'user_id': toUserId, 'dirty': true};
    }
    await prefs.setString(newSlotsKey, jsonEncode(merged.values.toList()));
    await prefs.remove(oldSlotsKey);
  }

  for (final prefix in [
    'planner_sessions_',
    'studio_clock_',
    'session_break_',
  ]) {
    final oldKey = '$prefix$fromUserId';
    final newKey = '$prefix$toUserId';
    final oldRaw = prefs.getString(oldKey);
    if (oldRaw == null) continue;
    final targetRaw = prefs.getString(newKey);
    try {
      final oldValue = jsonDecode(oldRaw);
      final targetValue = targetRaw == null ? null : jsonDecode(targetRaw);
      if (oldValue is Map && targetValue is Map) {
        await prefs.setString(
            newKey, jsonEncode({...oldValue, ...targetValue}));
      } else if (targetRaw == null) {
        await prefs.setString(newKey, oldRaw);
      }
      await prefs.remove(oldKey);
    } on FormatException {
      // Preserve malformed source data for recovery instead of deleting it.
    }
  }
}

List<Map<String, dynamic>> _decodeRows(String? raw) {
  if (raw == null) return const [];
  try {
    final value = jsonDecode(raw);
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  } on FormatException {
    return const [];
  }
}
