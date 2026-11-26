import '../analytics/study_metrics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/focus_session.dart';
import '../../core/models/distraction_event.dart';
import '../../core/models/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/app_dependencies.dart';
import '../../local_db/distraction_event_dao.dart';
import '../../local_db/focus_session_dao.dart';
import '../../services/supabase_service.dart';
import '../../core/utils/fe_logger.dart';

class DashboardState {
  const DashboardState({
    this.userProfile,
    this.todaySessions = const [],
    this.recentSessions = const [],
    this.todayDistractionCount = 0,
    this.totalFocusMinutesToday = 0,
    this.recoveryRate = 0,
    this.recoveryRateTrend = 0,
    this.medianRecoverySeconds = 0,
    this.isLoading = false,
    this.errorMessage,
  });

  final UserProfile? userProfile;
  final List<FocusSession> todaySessions;
  final List<FocusSession> recentSessions;
  final int todayDistractionCount;
  final int totalFocusMinutesToday;
  final double recoveryRate;
  final double recoveryRateTrend;
  final double medianRecoverySeconds;
  final bool isLoading;
  final String? errorMessage;

  DashboardState copyWith({
    UserProfile? userProfile,
    List<FocusSession>? todaySessions,
    List<FocusSession>? recentSessions,
    int? todayDistractionCount,
    int? totalFocusMinutesToday,
    double? recoveryRate,
    double? recoveryRateTrend,
    double? medianRecoverySeconds,
    bool? isLoading,
    String? errorMessage,
  }) {
    return DashboardState(
      userProfile: userProfile ?? this.userProfile,
      todaySessions: todaySessions ?? this.todaySessions,
      recentSessions: recentSessions ?? this.recentSessions,
      todayDistractionCount:
          todayDistractionCount ?? this.todayDistractionCount,
      totalFocusMinutesToday:
          totalFocusMinutesToday ?? this.totalFocusMinutesToday,
      recoveryRate: recoveryRate ?? this.recoveryRate,
      recoveryRateTrend: recoveryRateTrend ?? this.recoveryRateTrend,
      medianRecoverySeconds:
          medianRecoverySeconds ?? this.medianRecoverySeconds,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class DashboardViewModel extends StateNotifier<DashboardState> {
  DashboardViewModel(this._supabaseService, this._focusSessionDao,
      this._eventDao, this._userId)
      : super(const DashboardState()) {
    loadDashboard();
    _subscribeRealtimeDashboard();
  }

  final SupabaseService _supabaseService;
  final FocusSessionDao _focusSessionDao;
  final DistractionEventDao _eventDao;
  final String _userId;
  RealtimeChannel? _realtimeChannel;

  /// Feature 3 — same primary definition as analytics:
  /// % of distractions recovered within 30 seconds, rolling week,
  /// with a week-over-week trend.

  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final authUser = _supabaseService.currentUser;
      final liveUserId = authUser?.id ?? _userId;
      FELog.i('Dashboard',
          'Starting loadDashboard (userId: $liveUserId, authed: ${authUser != null})');

      UserProfile? profile;
      if (authUser != null) {
        try {
          profile = await _supabaseService.getUserProfile(liveUserId);
          FELog.d('Dashboard',
              'UserProfile fetched from Supabase: ${profile?.email}');
        } catch (e) {
          FELog.w('Dashboard', 'Could not fetch profile from Supabase: $e');
        }
      }

      // Load full 7-day history so UTC-offset sessions from earlier today
      // are never missed, then narrow to local-calendar today for the stats.
      final history = await _loadSessionsFromCloud();
      final today = DateTime.now();
      final midnight = DateTime(today.year, today.month, today.day);
      final todaySessions = history.where((s) {
        final localStart = s.startTime.toLocal();
        return !localStart.isBefore(midnight) && !localStart.isAfter(today);
      }).toList();
      final distractions =
          todaySessions.fold<int>(0, (sum, s) => sum + s.totalDistractions);
      final minutes =
          StudyMetrics.recordedFocus(history)(midnight, today) ~/ 60;

      // Feature 3 — headline Recovery Rate over rolling 7 days.
      final now = DateTime.now();
      final recentEvents = await _loadEventsFromCloud(history);
      final weekStart = now.subtract(const Duration(days: 7));
      final thisWeek = StudyMetrics.recoveryStats(recentEvents, weekStart, now);
      final lastWeek = StudyMetrics.recoveryStats(
          recentEvents, weekStart.subtract(const Duration(days: 7)), weekStart);

      FELog.i(
        'Dashboard',
        'Dashboard computed: todaySessions=${todaySessions.length}, totalHistory=${history.length}, '
            'distractions=$distractions, minutes=$minutes, recoveryRate=${thisWeek.rate.toStringAsFixed(1)}%, '
            'median=${thisWeek.median}s',
      );

      state = state.copyWith(
        userProfile: profile,
        todaySessions: todaySessions,
        recentSessions: history,
        todayDistractionCount: distractions,
        totalFocusMinutesToday: minutes,
        recoveryRate: thisWeek.rate,
        recoveryRateTrend: thisWeek.rate - lastWeek.rate,
        medianRecoverySeconds: thisWeek.median,
        isLoading: false,
      );
    } catch (e, st) {
      FELog.e('Dashboard', 'Dashboard load failed', e, st);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not load dashboard data. Pull to retry.',
      );
    }
  }

  Future<List<FocusSession>> _loadSessionsFromCloud() async {
    try {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 14))
          .toIso8601String();
      final client = Supabase.instance.client;
      final userId = _supabaseService.currentUser?.id;
      if (userId == null) return _focusSessionDao.getSessionHistory(50);
      final rows = await client
          .from('focus_sessions')
          .select()
          .eq('user_id', userId)
          .gte('start_time', cutoff)
          .order('start_time', ascending: false);
      final cloudSessions = (rows as List)
          .map((row) =>
              FocusSession.fromSqliteMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      FELog.d('Dashboard',
          'Cloud query: fetched ${cloudSessions.length} sessions (since $cutoff)');
      if (cloudSessions.isNotEmpty) return cloudSessions;
    } catch (e) {
      FELog.w('Dashboard',
          'Cloud session query failed, falling back to local cache: $e');
    }
    return _focusSessionDao.getSessionHistory(50);
  }

  Future<List<DistractionEvent>> _loadEventsFromCloud(
      List<FocusSession> sessions) async {
    try {
      if (sessions.isNotEmpty) {
        final rows = await Supabase.instance.client
            .from('distraction_events')
            .select()
            .inFilter('session_id', sessions.map((s) => s.id).toList())
            .order('triggered_at');
        final cloudEvents = (rows as List)
            .map((row) => DistractionEvent.fromSqliteMap(
                Map<String, dynamic>.from(row as Map)))
            .toList();
        FELog.d('Dashboard',
            'Cloud query: fetched ${cloudEvents.length} distraction events');
        if (cloudEvents.isNotEmpty) return cloudEvents;
      }
    } catch (e) {
      FELog.w('Dashboard',
          'Cloud event query failed, falling back to local cache: $e');
    }
    // Fallback: local cache per-session + recent events (mirrors Analytics)
    final events = <DistractionEvent>[];
    for (final session in sessions) {
      events.addAll(await _eventDao.getEventsForSession(session.id));
    }
    final recentLocal =
        await _eventDao.getRecentEvents(100, eventType: 'distraction');
    final seenIds = events.map((e) => e.id).toSet();
    for (final e in recentLocal) {
      if (!seenIds.contains(e.id)) events.add(e);
    }
    FELog.d('Dashboard', 'Total events resolved: ${events.length}');
    return events;
  }

  void _subscribeRealtimeDashboard() {
    try {
      if (_supabaseService.currentUser == null) return;
      _realtimeChannel = Supabase.instance.client
          .channel('dashboard-$_userId')
          .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'focus_sessions',
              callback: (_) => loadDashboard())
          .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'distraction_events',
              callback: (_) => loadDashboard())
          .subscribe();
    } catch (error) {
      FELog.d('Dashboard', 'Realtime unavailable: ${error.runtimeType}');
    }
  }

  @override
  void dispose() {
    final channel = _realtimeChannel;
    if (channel != null) {
      try {
        Supabase.instance.client.removeChannel(channel);
      } catch (_) {
        // There is no channel to remove in offline mode.
      }
    }
    super.dispose();
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardViewModel, DashboardState>(
  (ref) => DashboardViewModel(
    AppDependencies.supabaseService,
    AppDependencies.sessionDao,
    AppDependencies.eventDao,
    // Use live auth id; prefs value may be stale before OTP login completes.
    AppDependencies.supabaseService.currentUser?.id ??
        AppDependencies.prefs.getString(AppKeys.userId) ??
        '',
  ),
);
