import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import '../../core/constants/app_constants.dart';
import '../../core/providers/app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import 'dashboard_viewmodel.dart';
import 'session_app_logo.dart';

String? dashboardGreetingName(User? user, String? profileName) {
  if (user == null || user.isAnonymous) return null;
  final metadata = user.userMetadata;
  for (final candidate in [
    metadata?['full_name'],
    metadata?['name'],
    metadata?['given_name'],
    profileName,
    user.email?.split('@').first,
  ]) {
    if (candidate is String && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
  }
  return null;
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final vm = ref.read(dashboardProvider.notifier);
    final now = DateTime.now();
    final greeting =
        now.hour < 12 ? 'morning' : (now.hour < 18 ? 'afternoon' : 'evening');
    final auth = AppDependencies.supabaseService;
    final totalXp = state.userProfile?.totalXp ?? 0;
    final xpBase = totalXp >= AppXP.level4Min
        ? AppXP.level4Min
        : totalXp >= AppXP.level3Min
            ? AppXP.level3Min
            : totalXp >= AppXP.level2Min
                ? AppXP.level2Min
                : 0;
    final xpNext = xpBase == AppXP.level4Min
        ? AppXP.level4Min
        : xpBase == AppXP.level3Min
            ? AppXP.level4Min
            : xpBase == AppXP.level2Min
                ? AppXP.level3Min
                : AppXP.level2Min;
    final xpProgress = xpBase == AppXP.level4Min
        ? 1.0
        : ((totalXp - xpBase) / (xpNext - xpBase)).clamp(0.0, 1.0);
    final xpRemaining = (xpNext - totalXp).clamp(0, xpNext);

    final trend = state.recoveryRateTrend;
    final streak = state.userProfile?.streakDays ?? 0;
    final best = state.userProfile?.longestStreak ?? 0;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
            gradient: RadialGradient(
          center: Alignment(0.65, -1.35),
          radius: 1.35,
          colors: [Color(0xff124265), Color(0xff0b192d), Color(0xff080f1d)],
        )),
        child: SafeArea(
            child: RefreshIndicator(
          onRefresh: vm.loadDashboard,
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760 &&
                MediaQuery.textScalerOf(context).scale(16) < 24;
            final recovery = _metric(Icons.eco_rounded, 'Recovery rate',
                '${state.recoveryRate.toStringAsFixed(0)}%',
                accent: const Color(0xff45efbb),
                detail:
                    '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)} pts vs last week'
                    '${state.medianRecoverySeconds > 0 ? ' · Median return: ${state.medianRecoverySeconds.round()}s' : ''}');
            final streakCard = _metric(Icons.local_fire_department_rounded,
                'Focus streak', '$streak ${streak == 1 ? 'day' : 'days'}',
                accent: const Color(0xffffc74e),
                detail: 'Personal best: $best ${best == 1 ? 'day' : 'days'}');
            final stats = [
              _metric(Icons.calendar_today_outlined, 'Sessions',
                  '${state.todaySessions.length}',
                  compact: !wide),
              _metric(Icons.track_changes, 'Focus min',
                  '${state.totalFocusMinutesToday}',
                  compact: !wide),
              _metric(Icons.shield_outlined, 'Distractions',
                  '${state.todayDistractionCount}',
                  compact: !wide),
            ];
            final bar = ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                    minHeight: 10,
                    value: xpProgress,
                    color: _cyan,
                    backgroundColor: const Color(0xff233d59)));
            final xp = Text('$totalXp XP', style: AppTextStyles.displayMedium);
            final remaining = Text(xpRemaining == 0
                ? 'Zen Monk level reached'
                : '$xpRemaining XP to next level');
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1520),
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              wide ? 36 : 14, 14, wide ? 36 : 14, 24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(spacing: 8, runSpacing: 6, children: [
                                  for (final w in [
                                    (
                                      '/planner',
                                      'Planner',
                                      Icons.calendar_month
                                    ),
                                    (
                                      '/studio',
                                      'Focus Studio',
                                      Icons.timer_outlined
                                    ),
                                    (
                                      '/recovery',
                                      'Recovery Lab',
                                      Icons.favorite_outline
                                    ),
                                    (
                                      '/echo-coach',
                                      'EchoCoach AI',
                                      Icons.auto_awesome
                                    )
                                  ])
                                    ActionChip(
                                        avatar: Icon(w.$3, size: 18),
                                        label: Text(w.$2),
                                        onPressed: () => context.push(w.$1))
                                ]),
                                const SizedBox(height: 12),
                                StreamBuilder<AuthState>(
                                    stream: auth.authChanges,
                                    builder: (context, snapshot) {
                                      final user = auth.currentUser;
                                      final profile = state.userProfile;
                                      final name = dashboardGreetingName(
                                          user,
                                          profile?.id == user?.id
                                              ? profile?.displayName
                                              : null);
                                      return Row(children: [
                                        Icon(
                                            now.hour >= 18
                                                ? Icons.nights_stay_outlined
                                                : Icons.wb_sunny_outlined,
                                            color: _cyan),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Text(
                                                name == null
                                                    ? 'Good $greeting'
                                                    : 'Good $greeting, $name',
                                                style: AppTextStyles
                                                    .displayLarge
                                                    .copyWith(
                                                        fontSize:
                                                            wide ? 32 : 24))),
                                      ]);
                                    }),
                                if (state.errorMessage != null)
                                  Text(state.errorMessage!,
                                      style: const TextStyle(
                                          color: AppColors.accentRed)),
                                const SizedBox(height: 16),
                                _panel(
                                    Row(children: [
                                      _badge(Icons.layers_rounded, _cyan),
                                      const SizedBox(width: 14),
                                      Expanded(
                                          child: wide
                                              ? Row(children: [
                                                  xp,
                                                  const SizedBox(width: 28),
                                                  Expanded(child: bar),
                                                  const SizedBox(width: 24),
                                                  remaining
                                                ])
                                              : Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                      xp,
                                                      const SizedBox(height: 6),
                                                      bar,
                                                      const SizedBox(height: 6),
                                                      remaining
                                                    ])),
                                      IconButton(
                                          tooltip: 'View XP and streaks',
                                          onPressed: () =>
                                              context.go(AppRoutes.streaksXp),
                                          icon:
                                              const Icon(Icons.chevron_right)),
                                    ]),
                                    accent: _cyan),
                                const SizedBox(height: 12),
                                _columns(stats),
                                const SizedBox(height: 12),
                                if (wide)
                                  _columns([recovery, streakCard])
                                else ...[
                                  recovery,
                                  const SizedBox(height: 10),
                                  streakCard
                                ],
                                const SizedBox(height: 16),
                                DecoratedBox(
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(28),
                                        gradient: const LinearGradient(
                                            colors: [Color(0xff007ca9), Color(0xff0065cc)]),
                                        boxShadow: const [
                                          BoxShadow(
                                              color: Color(0x3300bfff),
                                              blurRadius: 18)
                                        ]),
                                    child: TextButton.icon(
                                        onPressed: () =>
                                            context.go(AppRoutes.focusSession),
                                        style: TextButton.styleFrom(
                                            minimumSize: const Size(0, 52),
                                            foregroundColor: Colors.white),
                                        icon: const Icon(
                                            Icons.play_arrow_rounded),
                                        label: const Text('Start Focus Session',
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold)))),
                                const SizedBox(height: 22),
                                Row(children: [
                                  const Icon(Icons.history),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text('Recent Sessions',
                                          style: AppTextStyles.displayMedium))
                                ]),
                                const SizedBox(height: 10),
                                if (state.todaySessions.isEmpty)
                                  _panel(state.isLoading
                                      ? const LinearProgressIndicator()
                                      : const Text(
                                          'No sessions today. Start one!'))
                                else
                                  for (final s in state.todaySessions.take(5))
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: _panel(Row(children: [
                                          SessionAppLogo(s.productiveApp),
                                          const SizedBox(width: 14),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    SessionAppLogo.label(
                                                        s.productiveApp),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                Text(
                                                    DateFormat('MMM d, HH:mm')
                                                        .format(s.startTime
                                                            .toLocal()),
                                                    style: AppTextStyles
                                                        .bodySmall),
                                              ])),
                                          if (wide) ...[
                                            Chip(label: Text(s.status.name)),
                                            const SizedBox(width: 20)
                                          ],
                                          Text(
                                              '${s.totalXpEarned} XP\nScore ${s.focusScore.round()}',
                                              textAlign: TextAlign.end),
                                        ]))),
                              ])))),
            );
          }),
        )),
      ),
    );
  }

  static const _cyan = Color(0xff38dcff);

  Widget _columns(List<Widget> children) => Row(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ]);

  Widget _panel(Widget child,
          {Color accent = const Color(0xff5980a4), double padding = 16}) =>
      Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                      accent.withValues(alpha: 0.12), const Color(0xff102235)),
                  const Color(0xff0e192b),
                ]),
            border: Border.all(color: accent.withValues(alpha: 0.32)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: child);

  Widget _badge(IconData icon, Color color) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, color: color));

  Widget _metric(IconData icon, String label, String value,
      {Color accent = _cyan, String? detail, bool compact = false}) {
    final text = Column(
        crossAxisAlignment:
            compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTextStyles.displayMedium),
          Text(label, textAlign: compact ? TextAlign.center : TextAlign.start),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail, style: AppTextStyles.bodySmall)
          ],
        ]);
    return _panel(
        compact
            ? Column(children: [Icon(icon, color: accent, size: 20), text])
            : Row(children: [
                _badge(icon, accent),
                const SizedBox(width: 12),
                Expanded(child: text)
              ]),
        accent: accent,
        padding: compact ? 8 : 18);
  }
}
