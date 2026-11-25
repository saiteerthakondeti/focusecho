import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/focus_session.dart';
import '../../core/providers/app_dependencies.dart';
import '../../core/widgets/workspace_ui.dart';
import '../../core/widgets/focusecho_brand.dart' show NeonPanel;
import '../../services/ai_coach_service.dart';
import '../../services/workspace_history.dart';
import '../focus_session/focus_session_viewmodel.dart';
import '../focus_session/study_planner.dart';
import '../analytics/study_metrics.dart';

class EchoCoachPage extends ConsumerStatefulWidget {
  const EchoCoachPage({super.key, this.objective});
  final String? objective;
  @override
  ConsumerState<EchoCoachPage> createState() => _EchoCoachPageState();
}

class _EchoCoachPageState extends ConsumerState<EchoCoachPage> {
  final service = AiCoachService(), input = TextEditingController();
  final messages = <({
    String question,
    String answer,
    String source,
    String? draft,
    List<String> steps
  })>[];
  bool busy = false;
  String? previousAdviceQuestion;
  String topic = '';
  late final String ownerAtOpen;
  late Future<WorkspaceHistory> metricsFuture;
  String get owner =>
      AppDependencies.prefs.getString(AppKeys.userId) ?? 'local-user';
  String get memoryKey => 'coach_preference_$owner';
  String? get preference => AppDependencies.prefs.getString(memoryKey);
  Future<void> editPreference() async {
    var value = preference ?? '';
    final approved = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('Coaching preference on this device'),
                content: TextFormField(
                    initialValue: value,
                    maxLength: 120,
                    onChanged: (v) => value = v,
                    decoration: const InputDecoration(
                        hintText:
                            'How do you want to approach your next session?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, ''),
                      child: const Text('Forget')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, value.trim()),
                      child: const Text('Save preference'))
                ]));
    if (approved == null || !mounted || owner != ownerAtOpen) return;
    if (approved.isEmpty) {
      await AppDependencies.prefs.remove(memoryKey);
    } else {
      await AppDependencies.prefs.setString(memoryKey, approved);
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ownerAtOpen = owner;
    metricsFuture = WorkspaceHistory.read(ownerAtOpen);
    input.text = widget.objective ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || owner != ownerAtOpen || !onlineAllowed) return;
      try {
        await AppDependencies.supabaseService
            .syncPlanner(AppDependencies.prefs);
        await AppDependencies.supabaseService.syncStudio(AppDependencies.prefs);
      } catch (_) {
        // Coach insights remain usable from the local cache while offline.
      }
    });
  }

  bool get onlineAllowed =>
      AppDependencies.prefs.getBool(AppKeys.localOnlyMode) != true &&
      AppDependencies.prefs.getBool(AppKeys.syncEnabled) != false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> ask(String question,
      {bool ai = false, bool advice = false}) async {
    final q = question.trim();
    if (q.isEmpty || busy) return;
    setState(() => busy = true);
    input.clear();
    String answer = '', source = 'On-device records';
    String? draft;
    List<String> steps = const [];
    final owner =
        AppDependencies.prefs.getString(AppKeys.userId) ?? 'local-user';
    try {
      final history = await WorkspaceHistory.read(owner, includeEvents: !ai);
      final rows = history.sessions.values
          .where((s) => s.status == SessionStatus.completed)
          .toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
      if (history.cloudRead) source = 'Synced account records';
      final now = DateTime.now();
      final vm = ref.read(focusSessionProvider.notifier);
      var lower = q.toLowerCase();
      if (['tell me more', 'why', 'why?', 'what about that?'].contains(lower) &&
          topic.isNotEmpty) {
        lower = topic;
        if (lower.contains('week') || lower.contains('today'))
          lower = 'recovery outcomes';
        else if (lower.contains('duration')) lower = 'productive hours';
      }
      topic = lower;

      if (ai) {
        if (!onlineAllowed || !await service.getOptInStatus()) {
          answer =
              'Cloud coaching needs sync and coach consent. You can still review your local sessions here.';
          source = 'Coach availability';
        } else if (!onlineAllowed) {
          answer = 'Local-only preferences are enabled.';
        } else if (advice) {
          final result = await service.advice(q, previousAdviceQuestion);
          previousAdviceQuestion = q;
          answer = result.advice;
          source =
              '${result.fallback ? "Rule-based advice" : "AI advice"} · ${result.samples} synced sessions';
        } else if (q == 'Review my last session') {
          final result = rows.isEmpty
              ? null
              : await service.fetchSessionDebrief(rows.first.id);
          if (result == null) {
            answer = 'No synced session debrief is available.';
          } else {
            answer =
                '${result.headline}\n${result.body}\n${result.actionableTip}';
            source = result.isFallback
                ? 'Rule-based debrief'
                : 'AI debrief · synced session';
          }
        } else {
          final result = await service.draftTask(q);
          draft = q;
          steps = result.steps;
          answer = steps
              .asMap()
              .entries
              .map((e) => '${e.key + 1}. ${e.value}')
              .join('\n');
          source = result.fallback ? 'Rule-based draft' : 'AI draft';
        }
      } else if (lower.contains('upcoming') || lower.contains('reschedule')) {
        if (onlineAllowed)
          await AppDependencies.supabaseService
              .syncPlanner(AppDependencies.prefs);
        final scope = service.currentOwner ?? 'guest';
        final slots = (jsonDecode(
                AppDependencies.prefs.getString('study_slots_$scope') ??
                    '[]') as List)
            .whereType<Map>()
            .where((row) =>
                row['deleted'] != true && row['details']?['complete'] != true)
            .where((row) {
          final at = DateTime.tryParse(row['starts_at'] ?? '');
          return at != null &&
              (lower.contains('reschedule')
                  ? at.isBefore(now)
                  : !at.isBefore(now));
        }).toList()
          ..sort((a, b) => a['starts_at'].compareTo(b['starts_at']));
        answer = slots.isEmpty
            ? 'No matching open tasks in your local planner.'
            : slots
                .take(3)
                .map((r) =>
                    '${r["subject"]} · ${DateTime.parse(r["starts_at"]).toLocal().toString().substring(0, 16)}')
                .join('\n');
        if (lower.contains('reschedule') && slots.isNotEmpty)
          answer += '\nOpen Planner to choose and confirm a new time.';
      } else if (lower.contains('shield')) {
        final task = vm.activeTask ?? vm.selectedTask;
        answer = task == null
            ? 'Pick a task in Planner and allow the apps and sites you need for that task.'
            : 'Current task: ${task.subject}. Allowed apps: ${task.apps.join(", ")}. Allowed sites: ${task.sites.join(", ")}. Review the shield before starting Studio.';
      } else if (lower.contains('productive hour') ||
          lower.contains('best time')) {
        final ids = rows.map((s) => s.id).toSet();
        final events = history.events.values;
        final stats = StudyMetrics.calculate(
            events.where((e) => ids.contains(e.sessionId)).toList(), rows, now);
        answer = stats.hour == null
            ? 'There is no clear best hour yet. Compare two different start hours with at least three recorded sessions each this week.'
            : 'Of your recent start hours, ${stats.hour}:00 had the lowest share of recorded distraction time across ${stats.samples} sessions.';
      } else if (lower.contains('duration') || lower.contains('how long')) {
        if (onlineAllowed)
          await AppDependencies.supabaseService
              .syncStudio(AppDependencies.prefs);
        final saved = vm.plannerSessions.records.values
            .whereType<Map>()
            .where((r) => r['id'] != null && r['cancelled'] != true)
            .map((r) => r['focus_seconds'])
            .whereType<int>()
            .where((s) => s >= 60)
            .toList()
          ..sort();
        answer = saved.length < 3
            ? 'Complete three planned sessions with recorded focus time to get a duration suggestion.'
            : 'Try a ${(saved[saved.length ~/ 2] ~/ 60).clamp(1, 240)}-minute block. That is the median focused duration of your ${saved.length} recorded planned sessions.';
      } else if (lower.contains('task') || lower.contains('next step')) {
        answer = vm.activeTask?.objective ??
            vm.selectedTask?.objective ??
            'Choose a planned task to bring its next step into Studio.';
      } else if (lower.contains('recover') || lower.contains('distract')) {
        final events = history.events.values
            .where((e) => rows.any((s) => s.id == e.sessionId))
            .toList();
        answer = events.isEmpty
            ? 'There are no recorded distraction outcomes for your recent completed sessions.'
            : '${events.where((e) => e.isRecovered).length} of ${events.length} recorded distractions have a recorded return. Open Recovery Lab to review them.';
      } else if (lower.contains('week') ||
          lower.contains('today') ||
          lower.contains('daily') ||
          lower.contains('focus time')) {
        final cutoff = DateTime(
            now.year, now.month, now.day - (lower.contains('week') ? 6 : 0));
        final period = rows
            .where((s) =>
                !s.startTime.isBefore(cutoff) && !s.startTime.isAfter(now))
            .toList();
        answer = period.isEmpty
            ? 'No completed sessions recorded for this period.'
            : '${period.length} completed sessions · ${period.fold<int>(0, (n, s) => n + s.totalDistractions)} distractions · ${(period.fold<double>(0, (n, s) => n + s.focusScore) / period.length).toStringAsFixed(1)} average score.';
      } else {
        answer =
            'I can review today, the last seven days, recorded recovery outcomes, or your current task. To clarify a task with AI, enter its objective and choose “Draft next step”.';
      }
    } catch (_) {
      answer =
          'The requested records are unavailable. Try again after your session has saved.';
      source = 'Unavailable';
    }
    if (!mounted) return;
    if ((AppDependencies.prefs.getString(AppKeys.userId) ?? 'local-user') !=
        owner) {
      setState(() {
        messages.clear();
        busy = false;
      });
      return;
    }
    setState(() {
      messages.insert(0, (
        question: q,
        answer: answer,
        source: source,
        draft: draft,
        steps: steps
      ));
      if (messages.length > 8) messages.removeLast();
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = NeonPanel(
      accent: const Color(0xffa75cff),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Color(0xffd27cff)),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('Talk through your next focus move',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            if (messages.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  messages.clear();
                  previousAdviceQuestion = null;
                  topic = '';
                }),
                child: const Text('Clear'),
              ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 7, runSpacing: 7, children: [
            for (final q in [
              'Today',
              'Weekly review',
              'Recovery outcomes',
              'Current task',
              'Productive hours',
              'Suggested duration',
              'Upcoming tasks',
              'Reschedule overdue tasks',
              'Focus Shield'
            ])
              ActionChip(
                avatar: const Icon(Icons.bolt_outlined, size: 16),
                label: Text(q),
                onPressed: busy ? null : () => ask(q),
              ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: const Color(0xff0a1022),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xff9164e8)),
            ),
            child: Row(children: [
              const Icon(Icons.psychology_outlined, color: Color(0xffb875ff)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: input,
                  maxLength: 120,
                  onSubmitted: busy ? null : ask,
                  decoration: const InputDecoration(
                    hintText: 'Ask EchoCoach about your focus…',
                    counterText: '',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: 'Ask EchoCoach',
                onPressed: busy ? null : () => ask(input.text),
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: busy || !onlineAllowed
                  ? null
                  : () => ask(input.text, ai: true),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Break down task'),
            ),
            OutlinedButton.icon(
              onPressed: busy || !onlineAllowed
                  ? null
                  : () => ask(input.text, ai: true, advice: true),
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('AI advice'),
            ),
            TextButton.icon(
              onPressed: busy || !onlineAllowed
                  ? null
                  : () => ask('Review my last session', ai: true),
              icon: const Icon(Icons.history_rounded),
              label: const Text('Last session debrief'),
            ),
          ]),
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          for (final m in messages) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 620),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xff5126a9).withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xff9e63f2)),
                ),
                child: Text(m.question),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xff17213a),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xff3c4770)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.smart_toy_outlined,
                          color: Color(0xff35d8f2), size: 19),
                      const SizedBox(width: 7),
                      const Text('EchoCoach',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Flexible(
                          child: WorkspaceChip(
                              label: m.source,
                              accent: const Color(0xff43dfbd))),
                    ]),
                    const SizedBox(height: 8),
                    SelectableText(m.answer),
                    if (m.draft != null)
                      TextButton.icon(
                        onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => StudyPlanner(
                                    initialSteps: m.steps,
                                    initialSubject: m.draft))),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Review task draft in Planner'),
                      ),
                  ]),
            ),
          ],
        ],
      ),
    );

    final support =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NeonPanel(
        accent: const Color(0xff8b4fe7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_awesome, color: Color(0xffd27cff)),
            SizedBox(width: 8),
            Text('Suggested for you',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))
          ]),
          const SizedBox(height: 10),
          _CoachAction(
              label: 'Plan a focused day',
              detail: 'Review tasks already in Planner.',
              icon: Icons.calendar_month_outlined,
              onTap: () => context.push('/planner')),
          _CoachAction(
              label: 'Restore your focus',
              detail: 'Review recorded recovery events.',
              icon: Icons.favorite_border,
              onTap: () => context.push('/recovery')),
          _CoachAction(
              label: 'Start a focus block',
              detail: 'Use a planned task or start independently.',
              icon: Icons.timer_outlined,
              onTap: () => context.push('/studio')),
        ]),
      ),
      const SizedBox(height: 12),
      if (owner == ownerAtOpen)
        NeonPanel(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
                backgroundColor: Color(0xff282451),
                child: Icon(Icons.tune, color: Color(0xffbd77ff))),
            title: const Text('Coaching preference'),
            subtitle:
                Text(preference ?? 'Optional, stored on this device only'),
            trailing: IconButton(
                tooltip: 'Edit or forget preference',
                icon: const Icon(Icons.edit_outlined),
                onPressed: editPreference),
          ),
        ),
      const SizedBox(height: 12),
      NeonPanel(
        accent: const Color(0xff3cdbcf),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Privacy & data',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(onlineAllowed
              ? 'AI actions require coach consent. Session debriefs use recorded metrics and reflection tags; parked note text is never sent.'
              : 'Local-only mode is active. Your focus history stays on this device.'),
        ]),
      ),
    ]);

    return Scaffold(
      appBar: const FocusWorkspaceAppBar(
          activePath: '/echo-coach', pageTitle: 'EchoCoach AI'),
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final contentWidth = wide ? 1500.0 : 900.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WorkspacePageHeader(
                      title: 'EchoCoach AI',
                      subtitle:
                          'Personalized guidance grounded in your recorded focus data.',
                      icon: Icons.psychology_alt_rounded,
                      trailing: WorkspaceChip(
                          label: onlineAllowed ? 'Synced data' : 'Local-only',
                          icon: onlineAllowed
                              ? Icons.cloud_done_outlined
                              : Icons.lock_outline,
                          accent: const Color(0xff42e6bd)),
                    ),
                    FutureBuilder<WorkspaceHistory>(
                      future: metricsFuture,
                      builder: (context, snapshot) {
                        final history = snapshot.data;
                        final sessions = history?.sessions.values
                                .where(
                                    (s) => s.status == SessionStatus.completed)
                                .toList() ??
                            const <FocusSession>[];
                        final events =
                            history?.events.values.toList() ?? const [];
                        final recovered =
                            events.where((e) => e.isRecovered).length;
                        final recoveryRate = events.isEmpty
                            ? '—'
                            : '${(recovered * 100 / events.length).round()}%';
                        final avgScore = sessions.isEmpty
                            ? '—'
                            : (sessions.fold<double>(
                                        0, (sum, s) => sum + s.focusScore) /
                                    sessions.length)
                                .toStringAsFixed(1);
                        final columns = constraints.maxWidth >= 1100
                            ? 4
                            : constraints.maxWidth >= 600
                                ? 2
                                : 1;
                        final cards = <Widget>[
                          WorkspaceStatCard(
                              icon: Icons.track_changes,
                              value: avgScore,
                              label: 'Average focus score',
                              accent: const Color(0xffc16eff)),
                          WorkspaceStatCard(
                              icon: Icons.favorite_border,
                              value: recoveryRate,
                              label: 'Recorded recovery rate',
                              accent: const Color(0xffff69bd)),
                          WorkspaceStatCard(
                              icon: Icons.history_rounded,
                              value: '${sessions.length}',
                              label: 'Completed sessions',
                              accent: const Color(0xff35d8f2)),
                          WorkspaceStatCard(
                              icon: Icons.cloud_done_outlined,
                              value: history?.cloudRead == true
                                  ? 'Connected'
                                  : 'Available',
                              label: history?.cloudRead == true
                                  ? 'Synced account data'
                                  : 'Local records',
                              accent: const Color(0xff42e6bd)),
                        ];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Wrap(spacing: 10, runSpacing: 10, children: [
                            for (final card in cards)
                              SizedBox(
                                  width: (constraints.maxWidth -
                                          (columns - 1) * 10) /
                                      columns,
                                  child: card),
                          ]),
                        );
                      },
                    ),
                    if (wide)
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: chat),
                            const SizedBox(width: 16),
                            Expanded(flex: 3, child: support),
                          ])
                    else ...[
                      chat,
                      const SizedBox(height: 14),
                      support,
                    ],
                  ]),
            ),
          ),
        );
      }),
    );
  }
}

class _CoachAction extends StatelessWidget {
  const _CoachAction(
      {required this.label,
      required this.detail,
      required this.icon,
      required this.onTap});
  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xff141b32),
        child: ListTile(
          leading: CircleAvatar(
              backgroundColor: const Color(0xff7139bd).withValues(alpha: .3),
              child: Icon(icon, color: const Color(0xffce8cff))),
          title:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(detail),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
