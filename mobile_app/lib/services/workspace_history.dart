import '../core/constants/app_constants.dart';
import '../core/models/distraction_event.dart';
import '../core/models/focus_session.dart';
import '../core/models/intervention_event.dart';
import '../core/providers/app_dependencies.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared recent history for the signed-in workspace, with offline local rows.
class WorkspaceHistory {
  final sessions = <String, FocusSession>{};
  final events = <String, DistractionEvent>{};
  final interventions = <String, InterventionEvent>{};
  bool cloudRead = false;

  static Future<WorkspaceHistory> read(String owner,
      {bool includeEvents = true, bool includeActions = false}) async {
    final result = WorkspaceHistory();
    final prefs = AppDependencies.prefs;
    bool allowed() =>
        prefs.getString(AppKeys.userId) == owner &&
        AppDependencies.supabaseService.currentUser?.id == owner &&
        prefs.getBool(AppKeys.localOnlyMode) != true &&
        prefs.getBool(AppKeys.syncEnabled) != false;

    for (final s in await AppDependencies.sessionDao.getSessionHistory(100)) {
      if (s.userId == owner) result.sessions[s.id] = s;
    }
    if (includeEvents) {
      for (final e in await AppDependencies.eventDao
          .getRecentEvents(1000, eventType: 'distraction')) {
        if (result.sessions.containsKey(e.sessionId)) result.events[e.id] = e;
      }
    }
    if (includeActions) {
      for (final id
          in result.events.values.map((e) => e.sessionId).toSet().take(12)) {
        for (final a
            in await AppDependencies.interventionDao.getEventsForSession(id)) {
          result.interventions[a.id] = a;
        }
      }
    }
    if (!allowed()) return result;
    try {
      final db = Supabase.instance.client;
      final rows = await db
          .from('focus_sessions')
          .select()
          .eq('user_id', owner)
          .order('start_time', ascending: false)
          .limit(100);
      if (!allowed()) return WorkspaceHistory();
      final ids = <String>[];
      for (final row in rows) {
        final s = FocusSession.fromSqliteMap(row);
        ids.add(s.id);
        final local = result.sessions[s.id];
        if (local == null || local.isSynced || local.endTime == null)
          result.sessions[s.id] = s;
      }
      if (includeEvents && ids.isNotEmpty) {
        final rows = await db
            .from('distraction_events')
            .select()
            .inFilter('session_id', ids)
            .eq('event_type', 'distraction')
            .order('triggered_at', ascending: false)
            .limit(1000);
        if (!allowed()) return WorkspaceHistory();
        for (final row in rows) {
          final e = DistractionEvent.fromSqliteMap(row);
          if (e.isRecovered || result.events[e.id]?.isRecovered != true)
            result.events[e.id] = e;
        }
      }
      if (includeActions && ids.isNotEmpty) {
        final rows = await db
            .from('intervention_events')
            .select()
            .inFilter('session_id', ids)
            .order('timestamp', ascending: false)
            .limit(1000);
        if (!allowed()) return WorkspaceHistory();
        for (final row in rows) {
          final a = InterventionEvent.fromSqliteMap(row);
          result.interventions[a.id] = a;
        }
      }
      result.cloudRead = true;
    } on Exception {
      // Offline reads remain usable and the screen reports the available source.
    }
    return result;
  }
}
