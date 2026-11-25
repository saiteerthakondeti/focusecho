import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/distraction_event.dart';
import '../../core/providers/app_dependencies.dart';
import '../../core/widgets/workspace_ui.dart';
import '../../core/widgets/focusecho_brand.dart' show NeonPanel;
import '../focus_session/focus_session_viewmodel.dart';
import '../../services/workspace_history.dart';

class RecoveryLab extends ConsumerStatefulWidget {
  const RecoveryLab({super.key});
  @override
  ConsumerState<RecoveryLab> createState() => _RecoveryLabState();
}

class _RecoveryLabState extends ConsumerState<RecoveryLab> {
  String? trigger;
  int? breath;
  Timer? reset;
  void endReset() {
    reset?.cancel();
    setState(() => breath = null);
  }

  void startReset() {
    reset?.cancel();
    setState(() => breath = 0);
    reset = Timer.periodic(const Duration(seconds: 1), (_) {
      if (breath == 15) {
        endReset();
      } else {
        setState(() => breath = breath! + 1);
      }
    });
  }

  @override
  void dispose() {
    reset?.cancel();
    super.dispose();
  }

  static const strategies = {
    'Bored': 'Pick the smallest part of your next step and start there.',
    'Tired': 'Take an intentional break, then come back to the same task.',
    'Stuck': 'Ask EchoCoach to clarify the next action.',
    'Unrelated thought': 'Park the thought and return to your objective.',
    'Forgot my objective': 'Read your original objective and next step below.',
    'Repeated opening':
        'Return to your productive app. Your session shield remains active.',
  };
  String? pastStrategy;
  final sustained = <String, int>{};
  late Future<List<DistractionEvent>> history;
  @override
  void initState() {
    super.initState();
    history = load();
  }

  Future<List<DistractionEvent>> load() async {
    final user =
        AppDependencies.prefs.getString(AppKeys.userId) ?? 'local-user';
    final history = await WorkspaceHistory.read(user, includeActions: true);
    final rows = history.events.values.toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    sustained.clear();
    final trials = <String, int>{}, returns = <String, int>{};
    for (final id in rows.map((e) => e.sessionId).toSet().take(12)) {
      final actions =
          history.interventions.values.where((a) => a.sessionId == id);
      for (final action in actions) {
        final parts = action.actionTaken.split(':');
        if (parts.length == 3 && parts.first == 'sustained') {
          final seconds = int.tryParse(parts.last);
          if (seconds != null) sustained[parts[1]] = seconds;
        }
      }
      final events = rows.where((e) => e.sessionId == id).toList()
        ..sort((a, b) => a.triggeredAt.compareTo(b.triggeredAt));
      for (var i = 0; i < events.length; i++) {
        final event = events[i];
        final end = event.recoveredAt ??
            (i + 1 < events.length
                ? events[i + 1].triggeredAt
                : DateTime.now());
        final choices = actions
            .where((a) =>
                a.actionTaken.startsWith('lab:') &&
                !a.timestamp.isBefore(event.triggeredAt) &&
                a.timestamp.isBefore(end))
            .toList();
        if (choices.isEmpty) continue;
        choices.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final choice = choices.last.actionTaken.substring(4);
        if (!strategies.containsKey(choice)) continue;
        trials.update(choice, (n) => n + 1, ifAbsent: () => 1);
        if (event.isRecovered)
          returns.update(choice, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final ranked = trials.keys
        .where((k) => trials[k]! >= 3 && (returns[k] ?? 0) > 0)
        .toList()
      ..sort((a, b) => ((returns[b] ?? 0) / trials[b]!)
          .compareTo((returns[a] ?? 0) / trials[a]!));
    pastStrategy = ranked.isEmpty
        ? null
        : '${strategies[ranked.first]} A return was recorded in ${returns[ranked.first]} of ${trials[ranked.first]} earlier episodes with this strategy.';
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(focusSessionProvider);
    final vm = ref.read(focusSessionProvider.notifier);
    ref.listen(focusSessionProvider, (prev, next) {
      if (prev?.distractionCount != next.distractionCount ||
          prev?.sessionXp != next.sessionXp) setState(() => history = load());
    });
    final active = state.isActive || vm.onBreak;
    final currentStep = vm.activeTask?.nextStep ?? '';
    return Scaffold(
        appBar: const FocusWorkspaceAppBar(
            activePath: '/recovery', pageTitle: 'Recovery Lab'),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          WorkspacePageHeader(
            title: 'Recovery Lab',
            subtitle: 'Regain focus, restore your context, and return to work.',
            icon: Icons.favorite_rounded,
            accent: const Color(0xffff70c6),
            trailing: WorkspaceChip(
              label: active
                  ? 'From Focus Studio · ${vm.phase}'
                  : 'Ready when you need it',
              icon: active ? Icons.shield_outlined : Icons.self_improvement,
              accent:
                  active ? const Color(0xff4de6c0) : const Color(0xffbd77ff),
            ),
          ),
          NeonPanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  const Icon(Icons.flag_rounded, color: Color(0xffbd77ff)),
                  const SizedBox(width: 9),
                  Text('Your original task',
                      style: Theme.of(context).textTheme.titleMedium),
                ]),
                const SizedBox(height: 8),
                Text(
                    active
                        ? (vm.activeTask?.objective ?? state.intent)
                        : 'No active focus session',
                    style: Theme.of(context).textTheme.titleLarge),
                if (active && currentStep.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.subdirectory_arrow_right,
                        color: Color(0xff38d9f2)),
                    title: const Text('Current subtask'),
                    subtitle: Text(currentStep),
                    trailing: IconButton(
                      tooltip: 'Complete current subtask',
                      onPressed: vm.finishCurrentStep,
                      icon: const Icon(Icons.check_circle_outline),
                    ),
                  ),
                if (active && state.lastDistractionLabel != null)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xffe94b89).withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xffff65a8).withValues(alpha: .6)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Color(0xffff75ad)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              '${state.lastDistractionLabel} interrupted this session')),
                    ]),
                  ),
                if (active) ...[
                  Text(
                      '${vm.phase} · ${vm.remainingSeconds ~/ 60}m ${vm.remainingSeconds % 60}s remaining'),
                  if (state.lastDistractionLabel != null)
                    Text('Last distraction: ${state.lastDistractionLabel}'),
                  FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume original task'),
                      onPressed: () async {
                        if (vm.onBreak) {
                          await vm.resumeBreak();
                        } else if (state.showAlert) {
                          vm.returnToFocusFromIntervention();
                        }
                        if (context.mounted) context.go(AppRoutes.focusSession);
                        await vm.reopenTask();
                      }),
                  if (!vm.onBreak)
                    TextButton(
                        onPressed: vm.takeBreakFromIntervention,
                        child: const Text('Take an intentional break'))
                ] else
                  TextButton(
                      onPressed: () => context.go(AppRoutes.focusSession),
                      child: const Text('Open Focus Studio')),
              ])),
          const SizedBox(height: 12),
          FutureBuilder<List<DistractionEvent>>(
            future: history,
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <DistractionEvent>[];
              final recovered = rows.where((e) => e.isRecovered).length;
              final times = rows
                  .where((e) => e.isRecovered && e.recoveryTimeSeconds != null)
                  .map((e) => e.recoveryTimeSeconds!)
                  .toList();
              final average = times.isEmpty
                  ? null
                  : (times.reduce((a, b) => a + b) / times.length).round();
              final rate = rows.isEmpty
                  ? '—'
                  : '${(recovered * 100 / rows.length).round()}%';
              return LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth >= 780
                    ? 3
                    : constraints.maxWidth >= 480
                        ? 2
                        : 1;
                final cards = <Widget>[
                  WorkspaceStatCard(
                      icon: Icons.restart_alt_rounded,
                      value: rate,
                      label: 'Recorded recovery rate',
                      accent: const Color(0xff40e6bd)),
                  WorkspaceStatCard(
                      icon: Icons.timer_outlined,
                      value: average == null ? '—' : '${average}s',
                      label: 'Average return time',
                      accent: const Color(0xff32d8f2)),
                  WorkspaceStatCard(
                      icon: Icons.history_rounded,
                      value: '${rows.length}',
                      label: 'Recorded distractions',
                      accent: const Color(0xffbd77ff)),
                ];
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final card in cards)
                    SizedBox(
                        width: (constraints.maxWidth - (columns - 1) * 10) /
                            columns,
                        child: card),
                ]);
              });
            },
          ),
          const SizedBox(height: 12),
          NeonPanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('What pulled you away?',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                    'Name the trigger. Then use a short reset to reconnect with your next step.'),
                Wrap(spacing: 8, children: [
                  for (final t in strategies.keys)
                    ChoiceChip(
                        label: Text(t),
                        selected: t == trigger,
                        onSelected: (selected) {
                          setState(() => trigger = selected ? t : null);
                          if (active && selected) vm.recordStrategy(t);
                        })
                ]),
                if (trigger == null &&
                    state.isActive &&
                    state.distractionCount >= 2)
                  const Text(
                      'You have left the task more than once. Review your next step or try a short reset.'),
                Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color:
                              const Color(0xff9e64ff).withValues(alpha: .55)),
                      gradient: const LinearGradient(
                          colors: [Color(0xff102b42), Color(0xff201740)]),
                    ),
                    child: Row(children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xff44e5d4), width: 4),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xff8d4cff)
                                    .withValues(alpha: .3),
                                blurRadius: 18)
                          ],
                        ),
                        child: Center(
                            child: Text(
                                breath == null
                                    ? '16s'
                                    : '${(16 - breath!).clamp(0, 16)}s',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('Mental reset',
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            const Text(
                                'Take a brief breath, then return to the same task.'),
                            TextButton.icon(
                                onPressed:
                                    breath == null ? startReset : endReset,
                                icon: const Icon(Icons.air_rounded),
                                label: Text(breath == null
                                    ? 'Start breathing reset'
                                    : '${breath! % 8 < 4 ? "Breathe in" : "Breathe out"} · Skip')),
                          ])),
                    ])),
                if (trigger != null) Text(strategies[trigger]!),
                if (trigger == 'Stuck')
                  TextButton(
                      onPressed: () => context.push('/echo-coach',
                          extra: vm.activeTask?.nextStep.isNotEmpty == true
                              ? vm.activeTask!.nextStep
                              : state.intent),
                      child: const Text('Open EchoCoach')),
                if (trigger == 'Unrelated thought' && active)
                  TextFormField(
                      maxLength: 120,
                      decoration: const InputDecoration(
                          labelText: 'Parking lot',
                          hintText: 'Press Enter to save'),
                      onFieldSubmitted: (v) async {
                        await vm.addParkedItem(v);
                        if (mounted) setState(() => trigger = null);
                      }),
              ])),
          const SizedBox(height: 12),
          NeonPanel(
              child: FutureBuilder<List<DistractionEvent>>(
                  future: history,
                  builder: (context, s) {
                    if (s.hasError)
                      return TextButton(
                          onPressed: () => setState(() => history = load()),
                          child: const Text('Retry recovery history'));
                    if (!s.hasData) return const LinearProgressIndicator();
                    final rows = s.data!;
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recent recovery history',
                              style: Theme.of(context).textTheme.titleLarge),
                          if (pastStrategy != null) Text(pastStrategy!),
                          if (rows.isEmpty)
                            const Text(
                                'No distraction events available for this account.'),
                          for (final e in rows.take(8))
                            ListTile(
                                title: Text(e.appLabel.isEmpty
                                    ? e.packageName
                                    : e.appLabel),
                                subtitle: Text(MaterialLocalizations.of(context)
                                    .formatShortDate(e.triggeredAt.toLocal())),
                                trailing: Text(sustained.containsKey(e.id)
                                    ? 'Sustained · ${sustained[e.id]}s'
                                    : e.isRecovered
                                        ? 'Recovered · ${e.recoveryTimeSeconds ?? 0}s'
                                        : 'No recorded return')),
                        ]);
                  })),
        ]));
  }
}
