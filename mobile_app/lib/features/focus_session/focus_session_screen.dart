import '../workspaces/studio_ambience.dart';
import 'planned_focus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/workspace_ui.dart';
import '../../core/widgets/focusecho_brand.dart' show NeonPanel;
import '../../services/ai_coach_service.dart';
import '../ai_coach/widgets/coach_opt_in_dialog.dart';
import '../distraction_alert/distraction_alert_modal.dart';
import '../distraction_alert/intervention_overlay.dart';
import 'focus_session_state.dart';
import 'study_planner.dart';
import 'focus_session_viewmodel.dart';
import 'session_summary_screen.dart';
import 'widgets/live_distraction_feed.dart';

class FocusSessionScreen extends ConsumerWidget {
  const FocusSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(focusSessionProvider);
    final vm = ref.read(focusSessionProvider.notifier);

    // Feature 2 — level-1 relapses keep the existing heads-up modal.
    ref.listen(focusSessionProvider, (previous, next) {
      final wasAlerting = previous?.showAlert ?? false;
      if (!wasAlerting &&
          next.showAlert &&
          next.lastEventId != null &&
          next.escalationLevel <= 1) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => DistractionAlertModal(
            appName: next.lastDistractionLabel ??
                next.lastDistractionPackage ??
                'Unknown app',
            packageName: next.lastDistractionPackage ?? 'unknown',
            riskScore: next.currentRiskScore,
            taskContext: vm.activeTask?.objective,
            onRecovery: vm.returnToFocusFromIntervention,
            onEndSession: vm.stopSession,
            onSnooze: () => vm.snoozeApp(next.lastDistractionPackage!),
            onStreakPenalty: vm.dismissAlert,
          ),
        );
      }
    });

    // Feature 4 — lightweight cross-surface nudge (non-blocking).
    ref.listen(focusSessionProvider, (previous, next) {
      final nudge = next.crossSurfaceNudge;
      if (nudge != null && nudge != (previous?.crossSurfaceNudge)) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.devices_other,
                      size: 18, color: AppColors.accentYellow),
                  const SizedBox(width: 8),
                  Expanded(child: Text(nudge)),
                ],
              ),
              backgroundColor: AppColors.card,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        vm.clearCrossSurfaceNudge();
      }
    });

    // Feature 1 — session-complete summary view.
    if (!state.isActive && state.sessionSummary != null) {
      return SessionSummaryScreen(
        summary: state.sessionSummary!,
        stats: state.sessionSummaryStats,
        onDismiss: vm.dismissSummary,
        onSaveReflection: vm.saveSessionReflection,
      );
    }

    if (vm.onBreak)
      return Scaffold(
          appBar: const FocusWorkspaceAppBar(
              activePath: '/studio', pageTitle: 'Focus Studio'),
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(vm.phase),
            if (vm.phase == 'On break' && vm.breakEnds != null)
              Text(
                  'Scheduled return: ${TimeOfDay.fromDateTime(vm.breakEnds!).format(context)}'),
            Text(vm.activeTask?.objective ?? state.intent,
                textAlign: TextAlign.center),
            FilledButton(
                onPressed: vm.resumeBreak,
                child: const Text('Resume original session')),
            TextButton(
                onPressed: vm.stopSession, child: const Text('End session')),
          ])));
    if (!state.isActive) {
      return _SessionSetupView(state: state, vm: vm);
    }

    final elapsed = Duration(seconds: vm.remainingSeconds);
    final timer =
        '${elapsed.inHours.toString().padLeft(2, '0')}:${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    // Feature 2 — level 2+ renders as a full-screen intervention state.
    final showFullScreenIntervention =
        state.showAlert && state.escalationLevel >= 2;

    final focusSeconds = state.elapsedSeconds.clamp(0, vm.plannedSeconds);
    final progress =
        vm.plannedSeconds == 0 ? 0.0 : focusSeconds / vm.plannedSeconds;
    final currentTask = vm.activeTask;
    final timerPanel = NeonPanel(
      accent: const Color(0xff9f5cff),
      child: Column(children: [
        Wrap(spacing: 8, children: [
          WorkspaceChip(
              label: vm.mode,
              icon: Icons.bolt_rounded,
              accent: const Color(0xffc47aff)),
          WorkspaceChip(
              label: state.session?.productiveApp ?? 'Focus session',
              icon: Icons.apps_rounded,
              accent: const Color(0xff37d9f1)),
        ]),
        const SizedBox(height: 20),
        SizedBox.square(
          dimension: 260,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
                child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              color: const Color(0xff9e54ff),
              backgroundColor: const Color(0xff23314f),
            )),
            Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                    colors: [Color(0xff1c2350), Color(0xff0a1126)]),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xff8e4cff).withValues(alpha: .22),
                      blurRadius: 35)
                ],
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(timer,
                        style: const TextStyle(
                            fontSize: 45,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1)),
                    const SizedBox(height: 4),
                    Text(vm.phase,
                        style: const TextStyle(color: Color(0xffb5bfd8))),
                  ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(
            state.session?.intent.trim().isNotEmpty == true
                ? state.session!.intent
                : 'Stay with your next step',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xffd9def0),
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                  onPressed: vm.pauseStudio,
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('Pause')),
              OutlinedButton.icon(
                  onPressed: vm.restartInterval,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Restart')),
              OutlinedButton.icon(
                  onPressed: vm.takeBreakFromIntervention,
                  icon: const Icon(Icons.coffee_outlined),
                  label: const Text('Take a break')),
              OutlinedButton.icon(
                  onPressed: vm.stopSession,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('End session')),
            ]),
      ]),
    );
    final taskPanel = NeonPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.track_changes, color: Color(0xffc47aff)),
          SizedBox(width: 8),
          Text('Current task',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))
        ]),
        const SizedBox(height: 8),
        Text(currentTask?.subject ?? state.session?.intent ?? state.intent,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        if (currentTask != null) ...[
          const SizedBox(height: 6),
          Text(
              currentTask.nextStep.isEmpty
                  ? 'All planned steps reviewed'
                  : 'Next up · ${currentTask.nextStep}',
              style: const TextStyle(color: Color(0xffaeb9d3))),
          if (currentTask.remaining.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final step in currentTask.remaining.take(4))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.radio_button_unchecked,
                    color: Color(0xffb57aff), size: 20),
                title: Text(step, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap:
                    step == currentTask.nextStep ? vm.finishCurrentStep : null,
              ),
          ],
        ],
        const SizedBox(height: 6),
        OutlinedButton.icon(
            onPressed: () => context.push('/planner'),
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text('Open Focus Planner')),
      ]),
    );
    final statsPanel = NeonPanel(
      accent: const Color(0xff30cee9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.query_stats_rounded, color: Color(0xff35d8f2)),
          SizedBox(width: 8),
          Text('Session stats · live',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))
        ]),
        const SizedBox(height: 10),
        _StudioStatRow(
            label: 'Elapsed focus interval',
            value: '${focusSeconds ~/ 60}m ${focusSeconds % 60}s',
            icon: Icons.timer_outlined,
            accent: const Color(0xff35d8f2)),
        _StudioStatRow(
            label: 'Distractions recorded',
            value: '${state.distractionCount}',
            icon: Icons.warning_amber_rounded,
            accent: const Color(0xffff6b9e)),
        _StudioStatRow(
            label: 'XP earned',
            value: '${state.sessionXp}',
            icon: Icons.bolt_rounded,
            accent: const Color(0xffffce59)),
      ]),
    );
    final shieldPanel = NeonPanel(
      accent: const Color(0xff35d99f),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.shield_outlined, color: Color(0xff42e6bd)),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('Focus Shield',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          WorkspaceChip(
              label: kIsWeb
                  ? (state.extensionConnected
                      ? 'Connected'
                      : 'Extension offline')
                  : 'Monitoring active',
              icon: Icons.circle,
              accent: kIsWeb && !state.extensionConnected
                  ? const Color(0xffffbd58)
                  : const Color(0xff42e6bd)),
        ]),
        const SizedBox(height: 7),
        Text(kIsWeb
            ? (state.extensionConnected
                ? 'Browser distraction monitoring is connected for this session.'
                : 'Connect the FocusEcho extension for browser monitoring.')
            : 'App monitoring is active for this focus session.'),
      ]),
    );

    return Scaffold(
      appBar: const FocusWorkspaceAppBar(
          activePath: '/studio', pageTitle: 'Focus Studio'),
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              final left = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WorkspacePageHeader(
                        title: 'Focus Studio',
                        subtitle:
                            'A distraction-free space to do your best work.',
                        icon: Icons.timer_rounded,
                        trailing: const WorkspaceChip(
                            label: 'Session live',
                            icon: Icons.circle,
                            accent: Color(0xff42e6bd))),
                    taskPanel,
                    const SizedBox(height: 14),
                    timerPanel,
                    if (kIsWeb || state.liveDistractionFeed.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                          height: 230,
                          child: LiveDistractionFeed(
                              feed: state.liveDistractionFeed)),
                    ],
                    if (vm.remainingSeconds == 0)
                      const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                              'Interval complete. Take a break or finish your session.')),
                  ]);
              final right = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    statsPanel,
                    const SizedBox(height: 12),
                    shieldPanel,
                    const SizedBox(height: 12),
                    NeonPanel(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            const Icon(Icons.headphones_rounded,
                                color: Color(0xffbd77ff)),
                            const SizedBox(width: 8),
                            const Text('Ambient sounds',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 17))
                          ]),
                          const SizedBox(height: 8),
                          const StudioAmbience(),
                        ])),
                    const SizedBox(height: 12),
                    ParkingLotComposer(
                        items: state.parkedItems,
                        onAdd: vm.addParkedItem,
                        onRemove: vm.removeParkedItem),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                        onPressed: () => context.push('/recovery'),
                        icon: const Icon(Icons.favorite_border),
                        label: const Text('Open Recovery Lab')),
                    TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialog) => AlertDialog(
                                  title: const Text('Cancel this session?'),
                                  content: const Text(
                                      'This session will close without earning XP.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialog, false),
                                        child: const Text('Keep focusing')),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialog, true),
                                        child: const Text('Cancel session')),
                                  ],
                                ));
                        if (confirmed == true)
                          await vm.stopSession(cancel: true);
                      },
                      child: const Text('Cancel session'),
                    ),
                  ]);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1500),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Expanded(flex: 7, child: left),
                                const SizedBox(width: 16),
                                Expanded(flex: 3, child: right),
                              ])
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                left,
                                const SizedBox(height: 14),
                                right
                              ]),
                  ),
                ),
              );
            }),
          ),
          if (showFullScreenIntervention)
            InterventionOverlay(
              level: state.escalationLevel,
              distractionCount: state.distractionCount,
              appName: state.lastDistractionLabel ??
                  state.lastDistractionPackage ??
                  'Unknown app',
              sessionIntent: vm.activeTask?.objective ??
                  state.session?.intent ??
                  state.intent,
              onReturnToFocus: vm.returnToFocusFromIntervention,
              onTakeBreak: vm.takeBreakFromIntervention,
              onRecoveryLab: () => context.push('/recovery'),
              onPauseSession: vm.pauseSessionFromIntervention,
            ),
        ],
      ),
    );
  }
}

class _StudioStatRow extends StatelessWidget {
  const _StudioStatRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Color(0xffb6c1d9)))),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
      );
}

class ParkingLotComposer extends StatefulWidget {
  const ParkingLotComposer({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> items;
  final Future<void> Function(String value) onAdd;
  final Future<void> Function(String value) onRemove;

  @override
  State<ParkingLotComposer> createState() => _ParkingLotComposerState();
}

class _ParkingLotComposerState extends State<ParkingLotComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final value = _controller.text.trim();
    if (value.isEmpty || value.length > 120 || widget.items.length >= 20)
      return;
    await widget.onAdd(value);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppDecorations.glassmorphismCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Things to check later', style: AppTextStyles.bodyLarge),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    hintText: 'Park an urge or task',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              IconButton(onPressed: _add, icon: const Icon(Icons.add)),
            ],
          ),
          for (final item in widget.items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => widget.onRemove(item),
              ),
            ),
          if (widget.items.length >= 20)
            Text('Parking lot is full (20 items).',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                )),
        ],
      ),
    );
  }
}

/// Feature 1 — Enhanced setup view with rich category chips, custom app creation,
/// quick intent suggestions, and responsive layout.
class _SessionSetupView extends StatefulWidget {
  const _SessionSetupView({required this.state, required this.vm});

  final FocusSessionState state;
  final FocusSessionViewModel vm;

  @override
  State<_SessionSetupView> createState() => _SessionSetupViewState();
}

class _SessionSetupViewState extends State<_SessionSetupView> {
  late final TextEditingController _intentCtrl;
  final _coachService = AiCoachService();
  bool _strict = false;
  final _allowed = <String>{};
  Map<String, String> _installed = {};
  Future<void> _start(String app, String intent) async {
    if (_strict && !kIsWeb) {
      const permissions = MethodChannel('focus_echo/permissions');
      if (await permissions.invokeMethod<bool>('checkUsageAccess') != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Grant Usage Access, then start strict focus.')));
        await permissions.invokeMethod<bool>('openUsageSettings');
        return;
      }
      const channel = MethodChannel('focus_echo/session');
      if (await channel.invokeMethod<bool>('overlayPermission') != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Enable the pause screen over other apps before starting strict focus.')));
        return;
      }
    }
    if (!mounted) return;
    if (_strict && kIsWeb && !widget.state.extensionConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Connect the FocusEcho extension before starting strict focus.')));
      return;
    }
    await widget.vm.startSession(app,
        intent: intent, strict: _strict, allowed: _allowed.toList());
  }

  Future<void> _changeMode(bool strict) async {
    setState(() => _strict = strict);
    if (!strict || kIsWeb || _installed.isNotEmpty) return;
    const channel = MethodChannel('focus_echo/session');
    final apps =
        await channel.invokeMapMethod<String, String>('listLaunchableApps');
    if (mounted && apps != null) setState(() => _installed = apps);
  }

  bool _isRefining = false;
  DateTime? _lastRefineTap;
  String? _refineFeedback;

  static const List<String> _quickPicks = [
    'VS Code',
    'Figma',
    'GitHub',
    'Notion',
    'Google Docs',
    'ChatGPT / Claude',
    'Slack',
    'Cursor',
  ];

  static const List<String> _quickIntents = [
    'Deep coding session',
    'Feature implementation',
    'Bug fixes & tests',
    'UI & design review',
    'Documentation & writing',
    'Research & study',
  ];

  @override
  void initState() {
    super.initState();
    _intentCtrl = TextEditingController(text: widget.state.intent);
    final task = widget.vm.selectedTask;
    if (task != null) {
      widget.vm.configureStudio('Custom', task.minutes, 5);
      _allowed.addAll(kIsWeb ? task.sites : task.apps);
      _strict = _allowed.isNotEmpty;
    }
  }

  Future<void> _onRefineTapped() async {
    final now = DateTime.now();
    if (_lastRefineTap != null &&
        now.difference(_lastRefineTap!) < const Duration(milliseconds: 1500)) {
      return; // Debounce taps to prevent duplicate calls
    }
    _lastRefineTap = now;

    final currentText = _intentCtrl.text.trim();
    if (currentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Type a draft intention first, then tap to refine with EchoCoach.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isRefining = true);
    try {
      final res = await _coachService.refineIntention(currentText);
      if (mounted) {
        setState(() {
          _isRefining = false;
          _intentCtrl.text = res.refinedIntention;
          _refineFeedback =
              '${res.coachFeedback} (Clarity: ${res.clarityScore}/100)';
        });
        widget.vm.setIntent(res.refinedIntention);
      }
    } catch (_) {
      if (mounted) setState(() => _isRefining = false);
    }
  }

  @override
  void didUpdateWidget(covariant _SessionSetupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.intent != oldWidget.state.intent &&
        widget.state.intent != _intentCtrl.text) {
      _intentCtrl.text = widget.state.intent;
    }
  }

  @override
  void dispose() {
    _intentCtrl.dispose();
    super.dispose();
  }

  IconData _iconForApp(String app) {
    final l = app.toLowerCase();
    if (l.contains('code') ||
        l.contains('cursor') ||
        l.contains('intellij') ||
        l.contains('terminal')) {
      return Icons.code_rounded;
    }
    if (l.contains('git') || l.contains('github') || l.contains('gitlab')) {
      return Icons.commit_rounded;
    }
    if (l.contains('figma') ||
        l.contains('design') ||
        l.contains('canva') ||
        l.contains('photoshop') ||
        l.contains('blender')) {
      return Icons.palette_outlined;
    }
    if (l.contains('doc') ||
        l.contains('word') ||
        l.contains('overleaf') ||
        l.contains('latex')) {
      return Icons.description_outlined;
    }
    if (l.contains('sheet') || l.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (l.contains('notion') || l.contains('obsidian') || l.contains('note')) {
      return Icons.auto_stories_outlined;
    }
    if (l.contains('slack') ||
        l.contains('teams') ||
        l.contains('meet') ||
        l.contains('zoom')) {
      return Icons.chat_bubble_outline_rounded;
    }
    if (l.contains('chatgpt') ||
        l.contains('claude') ||
        l.contains('perplexity') ||
        l.contains('ai')) {
      return Icons.psychology_outlined;
    }
    if (l.contains('coursera') ||
        l.contains('khan') ||
        l.contains('duolingo') ||
        l.contains('study')) {
      return Icons.school_outlined;
    }
    return Icons.apps_rounded;
  }

  void _showAddCustomAppDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Row(
          children: [
            const Icon(Icons.add_circle_outline, color: AppColors.accentBlue),
            const SizedBox(width: 8),
            Text('Add Productive App',
                style: AppTextStyles.displayMedium.copyWith(fontSize: 20)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the name of the app or website you work with:',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Linear, Jupyter, Blender, Company Portal',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  widget.vm.addProductiveApp(val.trim());
                  Navigator.of(dialogCtx).pop();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentBlue,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                widget.vm.addProductiveApp(controller.text.trim());
                Navigator.of(dialogCtx).pop();
              }
            },
            child: const Text('Add & Select',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final vm = widget.vm;
    final intent = _intentCtrl.text;
    final canStart =
        state.selectedProductiveApp != null && intent.trim().isNotEmpty;

    final allApps = state.availableProductiveApps;
    final selectedApp = state.selectedProductiveApp;

    return Scaffold(
      appBar: const FocusWorkspaceAppBar(
          activePath: '/studio', pageTitle: 'Focus Studio'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: AppDecorations.glassmorphismCard(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const WorkspacePageHeader(
                    title: 'Focus Studio',
                    subtitle:
                        'Choose a task and a focus mode. Your session shield stays with you.',
                    icon: Icons.timer_rounded,
                  ),
                  OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Study planner'),
                      onPressed: () async {
                        final task = await Navigator.push<PlannedFocus>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const StudyPlanner()));
                        if (!mounted || task == null || !vm.selectTask(task))
                          return;
                        setState(() {
                          _intentCtrl.text = task.objective;
                          _allowed.clear();
                          _allowed.addAll(kIsWeb ? task.sites : task.apps);
                          _strict = _allowed.isNotEmpty;
                        });
                      }),
                  Wrap(spacing: 8, children: [
                    for (final name in ['Pomodoro', 'Deep Work', 'Custom'])
                      ChoiceChip(
                          label: Text(name),
                          selected: vm.mode == name,
                          onSelected: (_) => setState(() => vm.configureStudio(
                              name,
                              name == 'Deep Work'
                                  ? 50
                                  : name == 'Pomodoro'
                                      ? 25
                                      : vm.selectedTask?.minutes ??
                                          vm.focusMinutes,
                              name == 'Deep Work' ? 10 : 5)))
                  ]),
                  if (vm.mode == 'Custom')
                    TextFormField(
                        key: ValueKey(vm.mode),
                        initialValue: vm.focusMinutes.toString(),
                        decoration: const InputDecoration(
                            labelText: 'Focus duration (1–240 min)'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null)
                            vm.configureStudio('Custom', n, vm.breakMinutes);
                        }),
                  ListTile(
                      title: Text('${vm.focusMinutes} min focus'),
                      trailing: DropdownButton<int>(
                          value: vm.breakMinutes,
                          items: [
                            for (final n in [1, 3, 5, 10, 15, 30])
                              DropdownMenuItem(
                                  value: n, child: Text('$n min break'))
                          ],
                          onChanged: (v) => setState(() => vm.configureStudio(
                              vm.mode, vm.focusMinutes, v ?? 5)))),
                  if (vm.selectedTask case final task?)
                    ListTile(
                        title: Text(task.subject),
                        subtitle: Text('Planned · ${task.minutes} min'),
                        trailing: IconButton(
                            tooltip: 'Use independent session',
                            icon: const Icon(Icons.link_off),
                            onPressed: () {
                              vm.detachTask();
                              setState(() {
                                _allowed.clear();
                                _strict = false;
                                _intentCtrl.clear();
                              });
                            })),
                  SwitchListTile(
                      secondary: const Icon(Icons.shield_outlined),
                      title: const Text('Strict focus'),
                      subtitle: Text(kIsWeb
                          ? 'Allow only selected websites'
                          : 'Choose the apps you need. Essential phone services stay available.'),
                      value: _strict,
                      onChanged: _changeMode),
                  if (!kIsWeb)
                    TextButton.icon(
                        icon: const Icon(Icons.hourglass_top),
                        label:
                            const Text('Enable pause screen over other apps'),
                        onPressed: () async {
                          const channel = MethodChannel('focus_echo/session');
                          if (await channel
                                  .invokeMethod<bool>('overlayPermission') !=
                              true) {
                            await channel
                                .invokeMethod<void>('openOverlayPermission');
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Pause screen permission is enabled.')));
                          }
                        }),
                  if (_strict && kIsWeb)
                    TextFormField(
                        initialValue: _allowed.join(", "),
                        decoration: const InputDecoration(
                            labelText: 'Allowed domains (comma separated)',
                            prefixIcon: Icon(Icons.language)),
                        onChanged: (v) {
                          _allowed
                            ..clear()
                            ..addAll(v
                                .split(',')
                                .map((s) => s.trim().toLowerCase())
                                .where((s) => s.isNotEmpty));
                        }),
                  if (_strict && !kIsWeb)
                    Wrap(children: [
                      for (final app in _installed.keys)
                        FilterChip(
                            label: Text(_installed[app] ?? app),
                            selected: _allowed.contains(app),
                            onSelected: (on) => setState(() {
                                  if (on) {
                                    _allowed.add(app);
                                  } else {
                                    _allowed.remove(app);
                                  }
                                }))
                    ]),
                  // ── Header Badge & Title ─────────────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color:
                                  AppColors.accentBlue.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded,
                                size: 14, color: AppColors.accentBlue),
                            const SizedBox(width: 4),
                            Text(
                              'DEEP WORK SETUP',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.accentBlue,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Ready to Focus?',
                      style: AppTextStyles.displayLarge.copyWith(fontSize: 30)),
                  const SizedBox(height: 6),
                  Text(
                    'Pick what you are working in and state your intention for this session.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  // ── Section 1: Quick Picks ────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Top Productive Tools',
                          style: AppTextStyles.bodyLarge
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        '${allApps.length} tools available',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._quickPicks.map((app) {
                        final isSelected = selectedApp == app;
                        return ChoiceChip(
                          selected: isSelected,
                          onSelected: (_) => vm.selectProductiveApp(app),
                          avatar: Icon(
                            _iconForApp(app),
                            size: 16,
                            color: isSelected
                                ? Colors.black
                                : AppColors.accentBlue,
                          ),
                          label: Text(app),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                          selectedColor: AppColors.accentBlue,
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.accentBlue
                                  : AppColors.border,
                            ),
                          ),
                        );
                      }),
                      ActionChip(
                        onPressed: _showAddCustomAppDialog,
                        avatar: const Icon(Icons.add,
                            size: 16, color: AppColors.accentGreen),
                        label: const Text('+ Custom app'),
                        labelStyle: const TextStyle(
                          color: AppColors.accentGreen,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        backgroundColor: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                              color:
                                  AppColors.accentGreen.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Section 2: All Apps Dropdown Selector ─────────────────
                  Text('Or select from all apps:',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surface,
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.accentBlue),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.accentBlue),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: allApps.contains(selectedApp)
                            ? selectedApp
                            : (allApps.isNotEmpty ? allApps.first : null),
                        menuMaxHeight: 320,
                        isExpanded: true,
                        dropdownColor: AppColors.surface,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        items: allApps.map((app) {
                          return DropdownMenuItem<String>(
                            value: app,
                            child: Row(
                              children: [
                                Icon(_iconForApp(app),
                                    size: 18, color: AppColors.accentBlue),
                                const SizedBox(width: 10),
                                Text(app,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14)),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) vm.selectProductiveApp(v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Section 3: Focus Intent ──────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text('What is your focus intent?',
                              style: AppTextStyles.bodyLarge
                                  .copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => CoachOptInDialog.show(context),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.info_outline_rounded,
                                      size: 14, color: AppColors.accentBlue),
                                  const SizedBox(width: 4),
                                  Text(
                                    'EchoCoach Info',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.accentBlue,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${intent.trim().length}/80',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: intent.trim().isNotEmpty
                              ? AppColors.accentGreen
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _intentCtrl,
                    maxLength: 80,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. Finish the analytics dashboard charts',
                      hintStyle: const TextStyle(color: Colors.white38),
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.surface,
                      prefixIcon: const Icon(Icons.track_changes_rounded,
                          color: AppColors.accentBlue),
                      suffixIcon: _isRefining
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accentBlue,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                color: AppColors.accentBlue,
                              ),
                              tooltip: 'Refine intent with EchoCoach',
                              onPressed: _onRefineTapped,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.accentBlue),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {});
                      vm.setIntent(val);
                    },
                  ),
                  if (_refineFeedback != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.accentBlue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            size: 14,
                            color: AppColors.accentBlue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _refineFeedback!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _refineFeedback = null),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),

                  // Quick Intent Suggestion Chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _quickIntents.map((qi) {
                      return ActionChip(
                        backgroundColor:
                            AppColors.surface.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        label: Text(
                          qi,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        onPressed: () {
                          _intentCtrl.text = qi;
                          setState(() {});
                          vm.setIntent(qi);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),

                  // ── Section 4: Start Action Button ─────────────────────────
                  InkWell(
                    onTap: canStart ? () => _start(selectedApp!, intent) : null,
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: canStart
                            ? const LinearGradient(
                                colors: [Color(0xFF00C2FF), Color(0xFF0072FF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: canStart ? null : AppColors.surface,
                        border: Border.all(
                          color: canStart
                              ? AppColors.accentBlue
                              : AppColors.border,
                        ),
                        boxShadow: canStart
                            ? [
                                BoxShadow(
                                  color: AppColors.accentBlue
                                      .withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : const [],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 24,
                            color: canStart
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'START FOCUS SESSION',
                            style: AppTextStyles.displayMedium.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              color: canStart
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!canStart)
                    Text(
                      selectedApp == null
                          ? 'Select a productive tool above to continue.'
                          : 'Enter your focus intent above to unlock the session.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.accentYellow,
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline,
                            size: 14, color: AppColors.accentGreen),
                        const SizedBox(width: 6),
                        Text(
                          'Ready to work in $selectedApp: "${intent.trim()}"',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.accentGreen),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
