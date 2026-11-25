import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/focusecho_brand.dart';
import 'streaks_xp_viewmodel.dart';

class StreaksXpScreen extends ConsumerWidget {
  const StreaksXpScreen({super.key});
  static const thresholds = [
    0,
    AppXP.level2Min,
    AppXP.level3Min,
    AppXP.level4Min
  ];
  static const names = [
    AppStrings.level1,
    AppStrings.level2,
    AppStrings.level3,
    AppStrings.level4
  ];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(streaksXpProvider);
    final level = thresholds.lastIndexWhere((v) => s.totalXp >= v).clamp(0, 3);
    final today = DateTime.now();
    const violet = Color(0xffbb8dff),
        gold = Color(0xffffc657),
        mint = Color(0xff4be8be);
    Widget heading(IconData icon, String title) => Row(children: [
          Icon(icon, color: violet),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppTextStyles.displayMedium))
        ]);
    final hero = NeonPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gold.withValues(alpha: .12),
                boxShadow: [
                  BoxShadow(
                      color: violet.withValues(alpha: .14), blurRadius: 22)
                ]),
            child:
                const Icon(Icons.emoji_events_rounded, color: gold, size: 44)),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s.totalXp} XP', style: AppTextStyles.displayLarge),
          Text('Level ${level + 1} · ${names[level]}'),
        ]))
      ]),
      const SizedBox(height: 18),
      LinearProgressIndicator(
          value: s.progressPercent,
          minHeight: 10,
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xff30ddd9),
          backgroundColor: const Color(0xff2a3156)),
      const SizedBox(height: 8),
      Text(level == 3
          ? 'Highest level reached'
          : '${s.xpToNextLevel} XP to Level ${level + 2}'),
    ]));
    final milestones = NeonPanel(
        child: Column(children: [
      heading(Icons.track_changes, 'Milestones'),
      const Divider(),
      for (var i = 0; i < thresholds.length; i++)
        ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: i == level ? const Color(0xff322554) : null,
            leading: Icon(
                i < level
                    ? Icons.check_circle
                    : i == level
                        ? Icons.stars_rounded
                        : Icons.lock_outline,
                color: i < level ? mint : violet),
            title: Text('Level ${i + 1} · ${names[i]}'),
            subtitle: Text('${thresholds[i]} XP'),
            trailing: i == level ? const Text('Current') : null)
    ]));
    final calendar = NeonPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading(Icons.calendar_month, '7-Day Streak Calendar'),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < 7; i++)
          Semantics(
              label: s.weeklyActivity[i]
                  ? 'Session completed'
                  : 'No completed session',
              child: Container(
                  width: 54,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                      color: (s.weeklyActivity[i] ? mint : violet)
                          .withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Icon(
                        s.weeklyActivity[i]
                            ? Icons.check_circle
                            : Icons.remove_circle_outline,
                        color: s.weeklyActivity[i] ? mint : Colors.white54),
                    Text(DateFormat.E().format(
                        DateTime(today.year, today.month, today.day - 6 + i)))
                  ])))
      ])
    ]));
    final achievements = NeonPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading(Icons.workspace_premium, 'Achievements'),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final badge in [
          (
            'First Session',
            Icons.rocket_launch,
            s.recentCompleted > 0 || (s.userProfile?.totalSessions ?? 0) > 0
          ),
          (
            '7 Day Streak',
            Icons.event_available,
            s.streakDays >= 7 || (s.userProfile?.longestStreak ?? 0) >= 7
          ),
          ('1,000 XP', Icons.stars, s.totalXp >= 1000),
          ('No Distractions', Icons.visibility_off, s.hasCleanSession),
        ])
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: badge.$3
                      ? const Color(0xff19403e)
                      : const Color(0xff21243f)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(badge.$2, color: badge.$3 ? gold : violet),
                Text(badge.$1),
                Text(badge.$3 ? 'Unlocked' : 'Locked',
                    style: AppTextStyles.bodySmall)
              ]))
      ])
    ]));
    final stats = NeonPanel(
        accent: gold,
        child: Wrap(spacing: 24, runSpacing: 12, children: [
          for (final stat in [
            ('Day streak', s.streakDays, Icons.bolt, gold),
            ('Recent sessions', s.recentCompleted, Icons.track_changes, violet),
            ('Distractions', s.recordedDistractions, Icons.bar_chart, mint)
          ])
            Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(stat.$3, color: stat.$4, size: 32),
              Text('${stat.$2}', style: AppTextStyles.displayMedium),
              Text(stat.$1)
            ])
        ]));
    return Scaffold(
        backgroundColor: const Color(0xff090e20),
        body: SafeArea(child: LayoutBuilder(builder: (context, c) {
          final wide =
              c.maxWidth / (MediaQuery.textScalerOf(context).scale(16) / 16) >=
                  940;
          return RefreshIndicator(
              onRefresh: ref.read(streaksXpProvider.notifier).loadStreaks,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(wide ? 24 : 14),
                  children: [
                    Text('Streaks & XP', style: AppTextStyles.displayLarge),
                    const SizedBox(height: 16),
                    if (s.errorMessage != null) Text(s.errorMessage!),
                    if (wide) ...[
                      Row(children: [
                        Expanded(child: hero),
                        const SizedBox(width: 16),
                        Expanded(child: stats)
                      ]),
                      const SizedBox(height: 16),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: milestones),
                            const SizedBox(width: 16),
                            Expanded(
                                child: Column(children: [
                              calendar,
                              const SizedBox(height: 14),
                              achievements
                            ]))
                          ])
                    ] else
                      for (final card in [
                        hero,
                        stats,
                        milestones,
                        calendar,
                        achievements
                      ])
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: card),
                  ]));
        })));
  }
}
