import 'package:focus_echo_ai/core/widgets/workspace_ui.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'planned_focus.dart';
import '../../services/supabase_service.dart';

/// Returns the subject selected for the next focus session.
class StudyPlanner extends StatefulWidget {
  const StudyPlanner(
      {super.key,
      this.suggestedHour,
      this.initialSubject,
      this.initialSteps = const [],
      this.onStart});
  final String? initialSubject;
  final List<String> initialSteps;
  final ValueChanged<PlannedFocus>? onStart;
  final int? suggestedHour;
  @override
  State<StudyPlanner> createState() => _StudyPlannerState();
}

class _StudyPlannerState extends State<StudyPlanner> {
  late SharedPreferences prefs;
  String? owner;
  List<Map<String, dynamic>> slots = [];
  bool busy = true;
  String? notice;
  String _viewMode = 'Board';
  String get key => 'study_slots_${owner ?? "guest"}';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    try {
      owner = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}
    slots = (jsonDecode(prefs.getString(key) ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    await sync();
    if (mounted && widget.initialSubject != null) {
      await edit();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> persistRow(Map<String, dynamic> row) async {
    final latest = (jsonDecode(prefs.getString(key) ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    latest.removeWhere((r) => r['id'] == row['id']);
    latest.add(row);
    await prefs.setString(key, jsonEncode(latest));
  }

  Future<void> sync() async {
    notice = null;
    try {
      if (owner != null) await SupabaseService().syncPlanner(prefs);
    } catch (_) {
      notice = 'Cloud sync unavailable. Pull to retry.';
    }
    slots = (jsonDecode(prefs.getString(key) ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    if (mounted) setState(() => busy = false);
  }

  Future<void> edit([Map<String, dynamic>? slot]) async {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final selected = calendarDay;
    final target =
        selected != null && selected.isAfter(today) ? selected : today;
    final initial = slot == null
        ? DateTime(
            target.year,
            target.month,
            target.day,
            widget.suggestedHour ?? now.hour,
            widget.suggestedHour == null ? now.minute : 0)
        : DateTime.parse(slot['starts_at']).toLocal();
    String subject = slot?['subject'] ?? widget.initialSubject ?? '';
    final details = Map<String, dynamic>.from(slot?['details'] ?? {});
    String priority = details['priority'] ?? 'Normal';
    String steps = (slot == null
            ? widget.initialSteps
            : PlannedFocus.strings(details['steps']))
        .join('\n');
    String apps = PlannedFocus.strings(details['apps']).join(', ');
    String sites = PlannedFocus.strings(details['sites']).join(', ');
    List<String> split(String v, Pattern pattern) => v
        .split(pattern)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    final form = GlobalKey<FormState>();
    final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(slot == null ? 'New task' : 'Edit task'),
                content: Form(
                    key: form,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          decoration:
                              const InputDecoration(labelText: 'Objective'),
                          initialValue: subject,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter a task objective'
                              : null,
                          maxLength: 120,
                          autofocus: true,
                          onChanged: (v) => subject = v),
                      DropdownButtonFormField<String>(
                          initialValue: priority,
                          decoration:
                              const InputDecoration(labelText: 'Priority'),
                          items: [
                            for (final p in ['Low', 'Normal', 'High'])
                              DropdownMenuItem(value: p, child: Text(p))
                          ],
                          onChanged: (v) => priority = v ?? priority),
                      TextFormField(
                          initialValue: steps,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 1400,
                          decoration: const InputDecoration(
                              labelText: 'Subtasks, one per line'),
                          onChanged: (v) => steps = v),
                      TextFormField(
                          initialValue: apps,
                          maxLength: 500,
                          decoration: const InputDecoration(
                              labelText:
                                  'Allowed Android packages, comma separated'),
                          onChanged: (v) => apps = v),
                      TextFormField(
                          initialValue: sites,
                          maxLength: 500,
                          decoration: const InputDecoration(
                              labelText:
                                  'Allowed website hosts, comma separated'),
                          onChanged: (v) => sites = v),
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate())
                          Navigator.pop(ctx, subject.trim());
                      },
                      child: const Text('Choose time'))
                ]));
    if (!mounted || name == null || name.isEmpty) return;
    final day = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: slot == null ? today : DateTime(2000),
        lastDate: DateTime(2100));
    if (!mounted || day == null) return;
    final start = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (!mounted || start == null) return;
    final from =
        DateTime(day.year, day.month, day.day, start.hour, start.minute);
    final end = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(slot == null
            ? from.add(const Duration(minutes: 45))
            : DateTime.parse(slot['ends_at']).toLocal()));
    if (!mounted || end == null) return;
    final to = DateTime(day.year, day.month, day.day, end.hour, end.minute);
    if (!to.isAfter(from)) {
      setState(() => notice = 'End time must be after start time.');
      return;
    }
    setState(() => busy = true);
    details.addAll({
      'steps': split(steps, '\n'),
      'priority': priority,
      'apps': split(apps, ','),
      'sites': split(sites.toLowerCase(), ',')
    });
    details['done'] = PlannedFocus.strings(details['done'])
        .where(PlannedFocus.strings(details['steps']).contains)
        .toList();
    slots.remove(slot);
    slots.add({
      'id': slot?['id'] ?? const Uuid().v4(),
      'user_id': owner,
      'subject': name,
      'details': details,
      'starts_at': from.toUtc().toIso8601String(),
      'ends_at': to.toUtc().toIso8601String(),
      'dirty': true
    });
    await persistRow(slots.last);
    await sync();
  }

  DateTime? calendarDay;
  DateTime dayOf(Map r) =>
      DateUtils.dateOnly(DateTime.parse(r['starts_at']).toLocal());
  Future<void> update(
      Map<String, dynamic> row, Map<String, dynamic> changes) async {
    if (busy) return;
    setState(() {
      busy = true;
      row.addAll(changes);
      row['dirty'] = true;
    });
    await persistRow(row);
    await sync();
  }

  Future<void> move(Map<String, dynamic> row, DateTime date) async {
    final old = DateTime.parse(row['starts_at']).toLocal();
    final length = DateTime.parse(row['ends_at']).difference(old);
    final start =
        DateTime(date.year, date.month, date.day, old.hour, old.minute);
    await update(row, {
      'starts_at': start.toUtc().toIso8601String(),
      'ends_at': start.add(length).toUtc().toIso8601String()
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = slots.where((r) => r['deleted'] != true).toList()
      ..sort((a, b) => a['starts_at'].compareTo(b['starts_at']) as int);
    final today = DateUtils.dateOnly(DateTime.now()),
        tomorrow = DateTime(today.year, today.month, today.day + 1);
    String boardFor(Map row) {
      final day = dayOf(row);
      if (day.isBefore(today)) {
        return row['details']?['complete'] == true ? 'Completed' : 'Overdue';
      }
      if (day == today) return 'Today';
      if (day == tomorrow) return 'Tomorrow';
      return 'Upcoming';
    }

    Widget task(Map<String, dynamic> r) {
      final t = PlannedFocus.fromSlot(r),
          details = Map<String, dynamic>.from(r['details'] ?? {});
      final steps = PlannedFocus.strings(details['steps']),
          done = PlannedFocus.strings(details['done']);
      final complete = details['complete'] == true;
      final card = Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                  color: (complete
                          ? const Color(0xff35d6a0)
                          : const Color(0xff6776bb))
                      .withValues(alpha: .42))),
          child: Column(children: [
            ListTile(
                title: Text(t.subject),
                subtitle: Text(
                    'Scheduled ${MaterialLocalizations.of(context).formatShortDate(dayOf(r))} · ${TimeOfDay.fromDateTime(DateTime.parse(r["starts_at"]).toLocal()).format(context)} · ${t.minutes} min · ${details["priority"] ?? "Normal"} priority')),
            for (final step in steps)
              CheckboxListTile(
                  dense: true,
                  title: Text(step),
                  value: done.contains(step),
                  onChanged: (v) => update(r, {
                        'details': {
                          ...details,
                          'done': v == true
                              ? [...done, step]
                              : done.where((s) => s != step).toList()
                        }
                      })),
            Wrap(children: [
              TextButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Focus'),
                  onPressed: complete
                      ? null
                      : () {
                          if (widget.onStart != null) {
                            widget.onStart!(t);
                          } else {
                            Navigator.pop(context, t);
                          }
                        }),
              TextButton(
                  onPressed: () => update(r, {
                        'details': {...details, 'complete': !complete}
                      }),
                  child: Text(complete ? 'Reopen' : 'Mark complete')),
              if (!complete && dayOf(r).isBefore(today))
                TextButton(
                    onPressed: () => move(r, today),
                    child: const Text('Move to today')),
              IconButton(
                  tooltip: 'Edit slot',
                  icon: const Icon(Icons.edit),
                  onPressed: () => edit(r)),
              IconButton(
                  tooltip: 'Remove slot',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => update(r, {'deleted': true}))
            ])
          ]));
      return LongPressDraggable<Map<String, dynamic>>(
          data: r,
          feedback: Material(
              child: Padding(
                  padding: const EdgeInsets.all(12), child: Text(t.subject))),
          child: card);
    }

    return Scaffold(
        appBar: FocusWorkspaceAppBar(
            activePath: '/planner',
            pageTitle: 'Focus Planner',
            actions: [
              IconButton(
                  tooltip: 'Calendar view',
                  icon: const Icon(Icons.calendar_month),
                  onPressed: () async {
                    final date = await showDatePicker(
                        context: context,
                        initialDate: calendarDay ?? today,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100));
                    if (date != null && mounted) {
                      setState(() {
                        calendarDay = date;
                        _viewMode = 'Calendar';
                      });
                    }
                  })
            ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: busy ? null : () => edit(),
            label: const Text('New task'),
            icon: const Icon(Icons.add)),
        body: busy
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  setState(() => busy = true);
                  await sync();
                },
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                    children: [
                      WorkspacePageHeader(
                        title: 'Focus Planner',
                        subtitle:
                            'Plan your work, stay focused and recover faster.',
                        icon: Icons.calendar_month_rounded,
                        trailing: WorkspaceChip(
                          label: '${visible.length} planned',
                          icon: Icons.checklist_rounded,
                          accent: const Color(0xff34d8f2),
                        ),
                      ),
                      LayoutBuilder(builder: (context, constraints) {
                        final count = constraints.maxWidth >= 1000
                            ? 4
                            : constraints.maxWidth >= 600
                                ? 2
                                : 1;
                        final todayRows =
                            visible.where((r) => dayOf(r) == today).toList();
                        final plannedMinutes = todayRows.fold<int>(0,
                            (sum, r) => sum + PlannedFocus.fromSlot(r).minutes);
                        final completed = todayRows
                            .where((r) =>
                                (r['details'] as Map?)?['complete'] == true)
                            .length;
                        final cards = <Widget>[
                          WorkspaceStatCard(
                              icon: Icons.task_alt,
                              value: '${todayRows.length}',
                              label: 'Tasks today',
                              accent: const Color(0xff42e6bd)),
                          WorkspaceStatCard(
                              icon: Icons.timer_outlined,
                              value: '${plannedMinutes}m',
                              label: 'Planned focus',
                              accent: const Color(0xff35d9f2)),
                          WorkspaceStatCard(
                              icon: Icons.done_all_rounded,
                              value: '$completed',
                              label: 'Completed today',
                              accent: const Color(0xffb579ff)),
                          WorkspaceStatCard(
                              icon: Icons.event_available,
                              value: '${visible.length - todayRows.length}',
                              label: 'Other planned tasks',
                              accent: const Color(0xffffbd58)),
                        ];
                        return Wrap(spacing: 10, runSpacing: 10, children: [
                          for (final card in cards)
                            SizedBox(
                                width:
                                    (constraints.maxWidth - (count - 1) * 10) /
                                        count,
                                child: card),
                        ]);
                      }),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                    value: 'Board',
                                    label: Text('Board'),
                                    icon: Icon(Icons.dashboard_outlined)),
                                ButtonSegment(
                                    value: 'Calendar',
                                    label: Text('Calendar'),
                                    icon: Icon(Icons.calendar_month_outlined)),
                                ButtonSegment(
                                    value: 'List',
                                    label: Text('List'),
                                    icon: Icon(Icons.view_list_outlined)),
                              ],
                              selected: {_viewMode},
                              onSelectionChanged: (selection) => setState(() {
                                _viewMode = selection.first;
                                if (_viewMode == 'Calendar')
                                  calendarDay ??= today;
                                if (_viewMode != 'Calendar') calendarDay = null;
                              }),
                            )),
                      ),
                      const SizedBox(height: 10),
                      if (notice != null) Text(notice!),
                      if (visible.isEmpty)
                        const ListTile(
                            title: Text('Your study schedule is empty')),
                      if (_viewMode == 'Calendar') ...[
                        TextButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                                context: context,
                                initialDate: calendarDay ?? today,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100));
                            if (date != null && mounted)
                              setState(() => calendarDay = date);
                          },
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: Text(MaterialLocalizations.of(context)
                              .formatMediumDate(calendarDay ?? today)),
                        ),
                        for (final r in visible
                            .where((r) => dayOf(r) == (calendarDay ?? today)))
                          task(r),
                      ] else if (_viewMode == 'List') ...[
                        for (final r in visible) task(r),
                      ] else
                        LayoutBuilder(builder: (ctx, c) {
                          final boards = <Widget>[
                            for (final board in [
                              'Overdue',
                              'Today',
                              'Tomorrow',
                              'Upcoming',
                              'Completed'
                            ])
                              if (!['Overdue', 'Completed'].contains(board) ||
                                  visible.any((r) => boardFor(r) == board))
                                DragTarget<Map<String, dynamic>>(
                                    onAcceptWithDetails: (drag) async {
                                      if (board == 'Overdue' ||
                                          board == 'Completed') return;
                                      final date = board == 'Upcoming'
                                          ? await showDatePicker(
                                              context: context,
                                              initialDate: tomorrow
                                                  .add(const Duration(days: 1)),
                                              firstDate: tomorrow
                                                  .add(const Duration(days: 1)),
                                              lastDate: DateTime(2100))
                                          : board == 'Tomorrow'
                                              ? tomorrow
                                              : today;
                                      if (date != null && mounted)
                                        await move(drag.data, date);
                                    },
                                    builder: (ctx, hover, _) => Card(
                                        color: hover.isEmpty
                                            ? null
                                            : Theme.of(ctx)
                                                .colorScheme
                                                .primaryContainer,
                                        child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Text(board,
                                                      style: Theme.of(ctx)
                                                          .textTheme
                                                          .titleMedium),
                                                  for (final r in visible.where(
                                                      (r) =>
                                                          boardFor(r) == board))
                                                    task(r)
                                                ]))))
                          ];
                          final columns = (c.maxWidth /
                                  (MediaQuery.textScalerOf(ctx).scale(16) /
                                      16) /
                                  350)
                              .floor()
                              .clamp(1, boards.length);
                          return Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final board in boards)
                              SizedBox(
                                  width: (c.maxWidth - (columns - 1) * 8) /
                                      columns,
                                  child: board)
                          ]);
                        }),
                      const ExpansionTile(
                          title: Text('Upcoming connections'),
                          children: [
                            ListTile(
                                title: Text(
                                    'Google Calendar · Notion · GitHub Issues · Todoist · Trello · Asana · Jira'),
                                subtitle: Text('Planned integrations'))
                          ])
                    ])));
  }
}
