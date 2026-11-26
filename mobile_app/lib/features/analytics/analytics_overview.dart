import '../../core/models/focus_session.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'analytics_viewmodel.dart';
import 'study_metrics.dart';

class AnalyticsOverview extends StatefulWidget {
  const AnalyticsOverview({super.key, required this.state});
  final AnalyticsState state;
  @override
  State<AnalyticsOverview> createState() => _AnalyticsOverviewState();
}

class _AnalyticsOverviewState extends State<AnalyticsOverview> {
  int? days = 1;
  DateTimeRange? custom;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = days == null
        ? custom!.start
        : DateTime(now.year, now.month, now.day - days! + 1);
    final last = days == null ? custom!.end : now;
    final next = DateTime(last.year, last.month, last.day + 1);
    final until = next.isAfter(now) ? now : next;
    bool includes(DateTime time) =>
        !time.isBefore(start) && time.isBefore(until);
    final sessions = widget.state.sessions
        .where((s) =>
            includes(s.startTime) &&
            s.status == SessionStatus.completed &&
            s.endTime != null &&
            !s.endTime!.isBefore(s.startTime) &&
            !s.endTime!.isAfter(now))
        .toList();
    final recovery =
        StudyMetrics.recoveryStats(widget.state.events, start, until);
    final seconds =
        StudyMetrics.recordedFocus(widget.state.sessions)(start, until);
    final drift = StudyMetrics.recordedDuration(
        widget.state.events, widget.state.sessions)(start, until);
    String duration(int s) =>
        s >= 3600 ? '${s ~/ 3600}h ${s ~/ 60 % 60}m' : '${s ~/ 60}m ${s % 60}s';
    final metrics = [
      (
        'Focus Score',
        sessions.isEmpty
            ? '—'
            : '${(sessions.fold<double>(0, (v, s) => v + s.focusScore) / sessions.length).toStringAsFixed(1)} / 100',
        Icons.track_changes,
        const Color(0xffa482ff)
      ),
      (
        'Focus Time',
        duration(seconds),
        Icons.schedule,
        const Color(0xff39d9ff)
      ),
      (
        'Distraction Time',
        duration(drift),
        Icons.block,
        const Color(0xffff83bb)
      ),
      (
        'Recovery Rate',
        recovery.total == 0 ? '—' : '${recovery.rate.round()}%',
        Icons.bolt,
        const Color(0xff40e9bd)
      ),
    ];
    final filters = Wrap(spacing: 6, runSpacing: 4, children: [
      for (final n in [1, 7, 30])
        ChoiceChip(
            label: Text(n == 1 ? 'Today' : '$n Days'),
            selected: days == n,
            onSelected: (_) => setState(() => days = n)),
      ChoiceChip(
          label: Text(days == null
              ? '${MaterialLocalizations.of(context).formatShortDate(start)} – ${MaterialLocalizations.of(context).formatShortDate(last)}'
              : 'Custom'),
          selected: days == null,
          onSelected: (_) async {
            final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year, now.month, now.day - 29),
                lastDate: now);
            if (mounted && range != null)
              setState(() {
                custom = range;
                days = null;
              });
          }),
    ]);
    return LayoutBuilder(builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final columns = c.maxWidth / scale >= 900
          ? 4
          : c.maxWidth / scale >= 320
              ? 2
              : 1;
      final header = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.equalizer, color: Color(0xffbb94ff), size: 34),
        const SizedBox(width: 12),
        Text('Analytics', style: AppTextStyles.displayLarge),
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c.maxWidth / scale >= 840)
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [header, filters])
        else ...[header, const SizedBox(height: 6), filters],
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final m in metrics)
            SizedBox(
                width: (c.maxWidth - 12 * (columns - 1)) / columns,
                child: AnalyticsPanel(
                    accent: m.$4,
                    child: Row(children: [
                      Icon(m.$3, color: m.$4),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(m.$1),
                            Text(m.$2,
                                style: AppTextStyles.displayMedium
                                    .copyWith(fontSize: 22)),
                          ]))
                    ]))),
        ]),
      ]);
    });
  }
}

class AnalyticsPanel extends StatelessWidget {
  const AnalyticsPanel(
      {super.key, required this.child, this.accent = const Color(0xff9186d9)});
  final Widget child;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: .40)),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                    accent.withValues(alpha: .15), const Color(0xff111831)),
                const Color(0xff0b1427)
              ])),
      child: child);
}
