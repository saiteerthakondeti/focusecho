import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/user_profile.dart';
import '../../core/models/focus_session.dart';
import '../../core/providers/app_dependencies.dart';
import '../../local_db/focus_session_dao.dart';
import '../../services/supabase_service.dart';

class StreaksXpState {
  const StreaksXpState({
    this.userProfile,
    this.weeklyActivity = const [
      false,
      false,
      false,
      false,
      false,
      false,
      false
    ],
    this.xpToNextLevel = 0,
    this.progressPercent = 0,
    this.errorMessage,
    this.totalXp = 0,
    this.recentCompleted = 0,
    this.recordedDistractions = 0,
    this.hasCleanSession = false,
    this.streakDays = 0,
  });

  final UserProfile? userProfile;
  final List<bool> weeklyActivity;
  final int xpToNextLevel;
  final double progressPercent;
  final String? errorMessage;
  final int totalXp;
  final int recentCompleted;
  final int recordedDistractions;
  final bool hasCleanSession;
  final int streakDays;

  StreaksXpState copyWith({
    UserProfile? userProfile,
    List<bool>? weeklyActivity,
    int? xpToNextLevel,
    double? progressPercent,
    String? errorMessage,
    int? totalXp,
    int? recentCompleted,
    int? recordedDistractions,
    bool? hasCleanSession,
    int? streakDays,
  }) {
    return StreaksXpState(
      userProfile: userProfile ?? this.userProfile,
      weeklyActivity: weeklyActivity ?? this.weeklyActivity,
      xpToNextLevel: xpToNextLevel ?? this.xpToNextLevel,
      progressPercent: progressPercent ?? this.progressPercent,
      errorMessage: errorMessage,
      totalXp: totalXp ?? this.totalXp,
      recentCompleted: recentCompleted ?? this.recentCompleted,
      recordedDistractions: recordedDistractions ?? this.recordedDistractions,
      hasCleanSession: hasCleanSession ?? this.hasCleanSession,
      streakDays: streakDays ?? this.streakDays,
    );
  }
}

class StreaksXpViewModel extends StateNotifier<StreaksXpState> {
  StreaksXpViewModel(this._supabaseService, this._sessionDao, this._userId)
      : super(const StreaksXpState()) {
    loadStreaks();
    try {
      if (_supabaseService.currentUser != null) {
        _xpChannel = Supabase.instance.client
            .channel('user-xp-$_userId')
            .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'user_xp',
                callback: (_) => loadStreaks())
            .subscribe();
      }
    } catch (error) {
      debugPrint('XP realtime unavailable: ${error.runtimeType}');
    }
  }

  final SupabaseService _supabaseService;
  final FocusSessionDao _sessionDao;
  final String _userId;
  RealtimeChannel? _xpChannel;

  Future<void> loadStreaks() async {
    try {
      UserProfile? profile;
      if (_supabaseService.currentUser != null) {
        try {
          profile = await _supabaseService.getUserProfile(_userId);
        } catch (e) {
          debugPrint('Could not fetch profile for streaks: $e');
        }
      }

      final signedIn = _supabaseService.currentUser != null;
      final effectiveXp = profile?.totalXp ??
          (signedIn
              ? state.totalXp
              : AppDependencies.prefs.getInt(AppKeys.xpTotal) ?? 0);
      final effectiveStreak = profile?.streakDays ??
          (signedIn
              ? state.streakDays
              : AppDependencies.prefs.getInt(AppKeys.streakDays) ?? 0);
      final records = {
        for (final s in await _sessionDao.getSessionHistory(100))
          if (s.userId == _userId) s.id: s
      };
      if (_supabaseService.currentUser?.id == _userId) {
        try {
          final rows = await Supabase.instance.client
              .from('focus_sessions')
              .select()
              .eq('user_id', _userId)
              .order('start_time', ascending: false)
              .limit(100);
          for (final row in rows) {
            final session = FocusSession.fromSqliteMap(row);
            if (records[session.id]?.endTime == null || session.endTime != null)
              records[session.id] = session;
          }
        } catch (e) {
          debugPrint('Streak history unavailable: ${e.runtimeType}');
        }
      }
      if (!mounted) return;
      final sessions = records.values
          .where((s) => s.status == SessionStatus.completed)
          .toList();
      final now = DateTime.now();
      final weekly = List<bool>.generate(7, (idx) {
        final day = DateTime(now.year, now.month, now.day - 6 + idx);
        return sessions.any(
          (s) =>
              s.startTime.toLocal().year == day.year &&
              s.startTime.toLocal().month == day.month &&
              s.startTime.toLocal().day == day.day,
        );
      });
      state = state.copyWith(
          userProfile: profile,
          weeklyActivity: weekly,
          recentCompleted: sessions.length,
          hasCleanSession: sessions.any((s) => s.totalDistractions == 0),
          recordedDistractions:
              sessions.fold<int>(0, (sum, s) => sum + s.totalDistractions),
          totalXp: effectiveXp,
          streakDays: effectiveStreak,
          errorMessage: null);
      computeXpProgress();
    } catch (e) {
      debugPrint('Streaks load error: $e');
      state = state.copyWith(errorMessage: 'Could not load streaks data.');
    }
  }

  void computeXpProgress() {
    final xp = state.totalXp;
    int nextThreshold = AppXP.level2Min;
    int baseThreshold = 0;
    if (xp >= AppXP.level4Min) {
      nextThreshold = AppXP.level4Min;
      baseThreshold = AppXP.level4Min;
    } else if (xp >= AppXP.level3Min) {
      nextThreshold = AppXP.level4Min;
      baseThreshold = AppXP.level3Min;
    } else if (xp >= AppXP.level2Min) {
      nextThreshold = AppXP.level3Min;
      baseThreshold = AppXP.level2Min;
    }
    final span = (nextThreshold - baseThreshold).clamp(1, 100000);
    state = state.copyWith(
      xpToNextLevel: (nextThreshold - xp).clamp(0, nextThreshold),
      progressPercent:
          xp >= AppXP.level4Min ? 1 : ((xp - baseThreshold) / span).clamp(0, 1),
    );
  }

  @override
  void dispose() {
    final channel = _xpChannel;
    if (channel != null) {
      try {
        Supabase.instance.client.removeChannel(channel);
      } catch (_) {
        // No cloud channel exists in offline mode.
      }
    }
    super.dispose();
  }
}

final streaksXpProvider =
    StateNotifierProvider<StreaksXpViewModel, StreaksXpState>(
  (ref) => StreaksXpViewModel(
    AppDependencies.supabaseService,
    AppDependencies.sessionDao,
    AppDependencies.supabaseService.currentUser?.id ??
        AppDependencies.prefs.getString(AppKeys.userId) ??
        '',
  ),
);
