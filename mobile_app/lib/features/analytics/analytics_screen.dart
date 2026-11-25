import '../focus_session/planned_focus.dart';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../services/backend_analytics_service.dart';
import '../focus_session/focus_session_viewmodel.dart';
import 'analytics_viewmodel.dart';
import 'analytics_overview.dart';
import '../dashboard/session_app_logo.dart';
import '../focus_session/study_planner.dart';
import '../../services/ai_coach_service.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';

// AnalyticsScreen is a ConsumerStatefulWidget so it can use ref.listen
// to detect when a focus session completes and immediately reload analytics
// without requiring the user to pull-to-refresh.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  late final Future<bool> _coachConsent = AiCoachService().getOptInStatus();
  String _duration(int seconds) => '${seconds ~/ 60}m ${seconds % 60}s';
  static const _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun'
  ];

  /// Computes dynamic 3-letter weekday labels for [today - 6 days ... today].
  /// Index 0 is 6 days ago; index 6 is always Today.
  static List<String> get slidingDayLabels {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    return List.generate(7, (i) {
      final d = DateTime(now.year, now.month, todayMidnight.day - 6 + i);
      return _weekdayNames[d.weekday - 1];
    });
  }

  static const _pieColors = [
    Color(0xFF6366F1),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFF06B6D4),
  ];

  static double _niceAxisInterval(double maxY) {
    // Aim for about four readable intervals instead of labeling every count.
    final roughInterval = maxY / 4;
    final magnitude =
        math.pow(10, (math.log(roughInterval) / math.ln10).floor());
    final normalized = roughInterval / magnitude;
    final niceStep = normalized <= 1
        ? 1
        : normalized <= 2
            ? 2
            : normalized <= 5
                ? 5
                : 10;
    return (niceStep * magnitude).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsProvider);
    final taskTimes = <String, int>{};
    final taskNames = <String, String>{};
    for (final entry in ref
        .read(focusSessionProvider.notifier)
        .plannerSessions
        .records
        .values) {
      if (entry['focus_seconds'] is! int ||
          entry['id'] is! String ||
          entry['cancelled'] == true) continue;
      final id = entry['id'] as String;
      taskNames[id] = entry['subject'];
      taskTimes[id] = (taskTimes[id] ?? 0) + (entry['focus_seconds'] as int);
    }
    final vm = ref.read(analyticsProvider.notifier);
    final dayLabels = slidingDayLabels;

    // Reload analytics whenever a focus session transitions from active → done.
    // This covers both manual stop and timer expiry so charts update immediately
    // after the user dismisses the session summary and taps Analytics.
    ref.listen(focusSessionProvider, (previous, next) {
      final wasActive = previous?.isActive ?? false;
      if (wasActive && !next.isActive) {
        ref.read(analyticsProvider.notifier).loadAnalytics();
      }
    });

    final appEntries = state.appDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topApps = appEntries.take(5).toList();
    final maxDailyDistractions = state.dailyDistractions
        .fold<int>(0, (maximum, count) => math.max(maximum, count))
        .toDouble();
    final dailyDistractionsMaxY =
        (maxDailyDistractions * 1.3).clamp(4.0, double.infinity).toDouble();
    final dailyDistractionsInterval = _niceAxisInterval(dailyDistractionsMaxY);

    final focus = SizedBox(
      height: 220,
      child: Builder(
        builder: (context) {
          final maxMins =
              state.weeklyFocusMinutes.reduce((a, b) => a > b ? a : b);
          final maxY = (maxMins * 1.25).clamp(10, double.infinity).toDouble();
          return BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final day = dayLabels[group.x.toInt() % dayLabels.length];
                    return BarTooltipItem(
                      '$day: ${rod.toY.toInt()}m focus',
                      AppTextStyles.bodySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ),
              barGroups: List.generate(7, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: state.weeklyFocusMinutes[i],
                      width: 20,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                      gradient: const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xFF6366F1),
                          Color(0xFF06B6D4),
                        ],
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxY,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ],
                );
              }),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.max) return const SizedBox();
                      return Text(
                        '${value.toInt()}m',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary, fontSize: 10),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= dayLabels.length) {
                        return const SizedBox();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          dayLabels[idx],
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary, fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) => const FlLine(
                  color: Colors.white10,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
            ),
          );
        },
      ),
    );
    final daily = SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: 6,
          minY: 0,
          maxY: dailyDistractionsMaxY,
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final day = dayLabels[spot.x.toInt() % dayLabels.length];
                  return LineTooltipItem(
                    '$day: ${spot.y.toInt()} distraction${spot.y.toInt() == 1 ? '' : 's'}',
                    AppTextStyles.bodySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                7,
                (i) =>
                    FlSpot(i.toDouble(), state.dailyDistractions[i].toDouble()),
              ),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5E62), Color(0xFFFF9966)],
              ),
              isCurved: true,
              preventCurveOverShooting: true,
              barWidth: 3.0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 3.5,
                  color: const Color(0xFFFF5E62),
                  strokeColor: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFF5E62).withValues(alpha: 0.28),
                    const Color(0xFFFF9966).withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= dayLabels.length) {
                    return const SizedBox();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dayLabels[idx],
                      style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: dailyDistractionsInterval,
                getTitlesWidget: (value, meta) {
                  if (value != value.roundToDouble()) {
                    return const SizedBox();
                  }
                  if (value == meta.max) {
                    return const SizedBox();
                  }
                  return Text(
                    value.toInt().toString(),
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary, fontSize: 10),
                  );
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) =>
                const FlLine(color: Colors.white10, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
    final score = state.sessionScores.isEmpty
        ? const Text("Complete a session to see your focus scores.")
        : SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          'Session #${spot.x.toInt() + 1}: ${spot.y.toInt()} Score',
                          AppTextStyles.bodySmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      state.sessionScores.length,
                      (i) => FlSpot(i.toDouble(), state.sessionScores[i]),
                    ),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF34D399)],
                    ),
                    isCurved: true,
                    preventCurveOverShooting: true,
                    barWidth: 3.0,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 3.5,
                        color: const Color(0xFF10B981),
                        strokeColor: Colors.white,
                        strokeWidth: 1.5,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF10B981).withValues(alpha: 0.25),
                          const Color(0xFF34D399).withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 25,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const SizedBox();
                        return Text(
                          value.toInt().toString(),
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary, fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text(
                        '#${value.toInt() + 1}',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary, fontSize: 10),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      const FlLine(color: Colors.white10, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          );

    final total = appEntries.fold<int>(0, (sum, e) => sum + e.value);
    final slices = [...topApps];
    final other = total - slices.fold<int>(0, (sum, e) => sum + e.value);
    if (other > 0) slices.add(MapEntry('Other', other));
    final apps = slices.isEmpty
        ? const Text('No distractions recorded this week.')
        : LayoutBuilder(builder: (context, c) {
            final donut = SizedBox.square(
                dimension: 150,
                child: Stack(alignment: Alignment.center, children: [
                  PieChart(PieChartData(
                      centerSpaceRadius: 48,
                      sectionsSpace: 2,
                      startDegreeOffset: -90,
                      sections: [
                        for (var i = 0; i < slices.length; i++)
                          PieChartSectionData(
                              showTitle: false,
                              radius: 24,
                              color: _pieColors[i % _pieColors.length],
                              value: slices[i].value.toDouble())
                      ])),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$total', style: AppTextStyles.displayMedium),
                    const Text('Distractions', style: TextStyle(fontSize: 11))
                  ])
                ]));
            final legend = Column(children: [
              for (var i = 0; i < slices.length; i++)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(
                          width: 4,
                          height: 28,
                          color: _pieColors[i % _pieColors.length]),
                      const SizedBox(width: 8),
                      SessionAppLogo(slices[i].key),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(SessionAppLogo.label(slices[i].key),
                              overflow: TextOverflow.ellipsis)),
                      Text(
                          '${slices[i].value}  (${(100 * slices[i].value / total).toStringAsFixed(1)}%)')
                    ]))
            ]);
            return c.maxWidth >= 390
                ? Row(children: [
                    donut,
                    const SizedBox(width: 16),
                    Expanded(child: legend)
                  ])
                : Column(children: [donut, const SizedBox(height: 10), legend]);
          });
    Widget panel(String title, String subtitle, IconData icon, Widget chart) =>
        AnalyticsPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: const Color(0xffae99ff)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: AppTextStyles.displayMedium.copyWith(fontSize: 19)))
          ]),
          Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 16),
              child: Text(subtitle, style: AppTextStyles.bodySmall)),
          chart,
        ]));
    Widget group(List<Widget> cards, bool horizontal) => horizontal
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(child: cards[i])
            ],
          ])
        : Column(children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              cards[i]
            ]
          ]);
    return Scaffold(
        body: SafeArea(
            child: DecoratedBox(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                      Color(0xff211839),
                      Color(0xff080f21),
                      Color(0xff101832)
                    ])),
                child: RefreshIndicator(
                    onRefresh: vm.loadAnalytics,
                    child: LayoutBuilder(builder: (context, c) {
                      final width = c.maxWidth /
                          (MediaQuery.textScalerOf(context).scale(16) / 16);
                      return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.all(width >= 800 ? 22 : 12),
                          children: [
                            AnalyticsOverview(state: state),
                            if (taskTimes.isNotEmpty)
                              ExpansionTile(
                                  title: const Text('Planned task focus time'),
                                  subtitle: const Text(
                                      'Completed sessions on this device, less recorded distraction time'),
                                  children: [
                                    for (final e in taskTimes.entries)
                                      ListTile(
                                          title: Text(taskNames[e.key]!),
                                          trailing: Text(_duration(e.value))),
                                  ]),
                            if (state.errorMessage != null)
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(state.errorMessage!)),
                            const SizedBox(height: 16),
                            group([
                              panel(
                                  'Weekly Focus Time',
                                  'Session time across the last 7 days',
                                  Icons.calendar_today_outlined,
                                  focus),
                              panel(
                                  'Most Distracting Apps',
                                  'Distractions across the last 7 days',
                                  Icons.layers_outlined,
                                  apps)
                            ], width >= 900),
                            const SizedBox(height: 14),
                            group([
                              panel(
                                  'Daily Distractions',
                                  'Distraction count per day',
                                  Icons.alarm,
                                  daily),
                              panel(
                                  'Focus Score History',
                                  'Scores from your most recent sessions',
                                  Icons.show_chart,
                                  score),
                              AnalyticsPanel(
                                  child: state.remoteRiskTrend.isEmpty
                                      ? const Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                              Text('14-Day Risk Trend',
                                                  style: TextStyle(
                                                      fontSize: 19,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              SizedBox(height: 12),
                                              Text(
                                                  'No synced risk history available.')
                                            ])
                                      : _RiskTrendSection(
                                          trend: state.remoteRiskTrend))
                            ], width >= 1150),
                            const SizedBox(height: 14),
                            if (state.metrics case final m?) ...[
                              Card(
                                  child: ListTile(
                                      leading: const Icon(Icons.bar_chart),
                                      title: const Text(
                                          'Distraction time · Today vs yesterday'),
                                      subtitle: Text(m.hasDurations
                                          ? 'Today: ${_duration(m.today)} · Yesterday: ${_duration(m.yesterday)}\nYesterday by this time: ${_duration(m.previousAtThisTime)} · Change: ${m.today >= m.previousAtThisTime ? "+" : "−"}${_duration((m.today - m.previousAtThisTime).abs())}\nIncludes recorded distraction durations during focus sessions.'
                                          : 'No completed distraction durations recorded today or yesterday.'))),
                              FutureBuilder<bool>(
                                  future: _coachConsent,
                                  builder: (context, result) {
                                    if (result.data != true)
                                      return const SizedBox.shrink();
                                    final hour = m.hour;
                                    return Card(
                                        child: ListTile(
                                            leading: const Icon(
                                                Icons.lightbulb_outline),
                                            title: const Text('Study insight'),
                                            subtitle: Text(hour == null
                                                ? 'Keep logging sessions at different times to discover a pattern.'
                                                : 'Across ${m.samples} sessions starting at ${TimeOfDay(hour: hour, minute: 0).format(context)}, you recorded less distraction time per hour. Try scheduling a study slot.'),
                                            trailing: hour == null
                                                ? null
                                                : IconButton(
                                                    tooltip: 'Add to planner',
                                                    icon: const Icon(
                                                        Icons.calendar_month),
                                                    onPressed: () async {
                                                      final task = await Navigator.push<
                                                              PlannedFocus>(
                                                          context,
                                                          MaterialPageRoute(
                                                              builder: (_) =>
                                                                  StudyPlanner(
                                                                      suggestedHour:
                                                                          hour)));
                                                      if (task != null &&
                                                          context.mounted &&
                                                          ref
                                                              .read(
                                                                  focusSessionProvider
                                                                      .notifier)
                                                              .selectTask(
                                                                  task)) {
                                                        context.push(AppRoutes
                                                            .focusSession);
                                                      }
                                                    })));
                                  }),
                            ],
                            if (state.summarySessionCount != null) ...[
                              _RemoteSummaryCard(state: state),
                              const SizedBox(height: 16),
                            ],
                            if (state.remoteTopApps.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _RemoteTopAppsSection(apps: state.remoteTopApps),
                            ],
                          ]);
                    })))));
  }
}

// ── Remote backend widgets (MOB-3g) ──────────────────────────────────────────

class _RemoteSummaryCard extends StatelessWidget {
  const _RemoteSummaryCard({required this.state});
  final AnalyticsState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.glassmorphismCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_done_outlined,
                  size: 16, color: AppColors.accentGreen),
              const SizedBox(width: 6),
              Text(
                  state.isRemoteLoaded
                      ? 'Backend Summary'
                      : 'Available completed sessions',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.accentGreen)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryChip(
                label: 'Avg Focus Score',
                value: state.summaryAverageScore != null
                    ? state.summaryAverageScore!.toStringAsFixed(1)
                    : '—',
              ),
              _SummaryChip(
                label: state.isRemoteLoaded
                    ? 'Synced Sessions'
                    : 'Completed Sessions',
                value: state.summarySessionCount?.toString() ?? '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.displayMedium),
        Text(label,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _RemoteTopAppsSection extends StatelessWidget {
  const _RemoteTopAppsSection({required this.apps});
  final List<TopApp> apps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Top Distractions (Synced)',
                style: AppTextStyles.displayMedium),
            const SizedBox(width: 6),
            const Icon(Icons.cloud_outlined,
                size: 14, color: AppColors.accentBlue),
          ],
        ),
        const SizedBox(height: 8),
        ...apps.map(
          (app) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(app.label)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${app.count}×',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.accentRed)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RiskTrendSection extends StatelessWidget {
  const _RiskTrendSection({required this.trend});
  final List<RiskDayEntry> trend;

  @override
  Widget build(BuildContext context) {
    // Count HIGH/CRITICAL per day for a sleek curved area chart
    final riskByDay = trend.map((d) {
      final high =
          d.riskScores.where((r) => r == 'HIGH' || r == 'CRITICAL').length;
      return FlSpot(trend.indexOf(d).toDouble(), high.toDouble());
    }).toList();

    final totalHighRisk = trend.fold<int>(
      0,
      (s, d) =>
          s + d.riskScores.where((r) => r == 'HIGH' || r == 'CRITICAL').length,
    );
    final riskLabel = totalHighRisk == 0
        ? 'Low Risk'
        : totalHighRisk <= 3
            ? 'Moderate Risk'
            : 'Elevated Risk';
    final riskColor = totalHighRisk == 0
        ? const Color(0xFF10B981)
        : totalHighRisk <= 3
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text('14-Day Risk Trend', style: AppTextStyles.displayMedium),
                const SizedBox(width: 6),
                const Icon(Icons.cloud_outlined,
                    size: 14, color: AppColors.accentBlue),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: riskColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                riskLabel,
                style: AppTextStyles.bodySmall.copyWith(
                  color: riskColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: AppDecorations.glassmorphismCard(),
          child: SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          'Day ${spot.x.toInt() + 1}: ${spot.y.toInt()} high-risk events',
                          AppTextStyles.bodySmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: riskByDay,
                    gradient: const LinearGradient(
                      colors: [Color(0xff9873ff), Color(0xff76ccff)],
                    ),
                    isCurved: true,
                    preventCurveOverShooting: true,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: riskByDay.length <= 14,
                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 3,
                        color: const Color(0xFFF59E0B),
                        strokeColor: Colors.white,
                        strokeWidth: 1.5,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFFF59E0B).withValues(alpha: 0.22),
                          const Color(0xFFF59E0B).withValues(alpha: 0.01),
                        ],
                      ),
                    ),
                  ),
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      const FlLine(color: Colors.white10, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        if (value != value.roundToDouble() ||
                            value == meta.max) {
                          return const SizedBox();
                        }
                        return Text(
                          value.toInt().toString(),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 2,
                      getTitlesWidget: (value, meta) => Text(
                        'D${value.toInt() + 1}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
