import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Returns the subject selected for the next focus session.
class StudyPlanner extends StatefulWidget {
  const StudyPlanner({super.key, this.suggestedHour});
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
  }

  Future<void> persist() async {
    await prefs.setString(key, jsonEncode(slots));
  }

  Future<void> sync() async {
    notice = null;
    try {
      await persist();
      if (owner != null) {
        final db = Supabase.instance.client;
        if (db.auth.currentUser?.id != owner) {
          throw StateError('Account changed');
        }
        for (final row in slots.where((r) => r['dirty'] == true).toList()) {
          if (row['deleted'] == true) {
            await db
                .from('study_slots')
                .delete()
                .eq('id', row['id'])
                .eq('user_id', owner!);
          } else {
            await db.from('study_slots').upsert(Map.of(row)..remove('dirty'));
          }
          row.remove('dirty');
          await persist();
        }
        final rows = await db
            .from('study_slots')
            .select()
            .eq('user_id', owner!)
            .order('starts_at');
        slots = List<Map<String, dynamic>>.from(rows);
        await persist();
      }
    } catch (_) {
      notice = 'Cloud sync unavailable. Pull to retry.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> edit([Map<String, dynamic>? slot]) async {
    final now = DateTime.now();
    final initial = slot == null
        ? DateTime(
            now.year, now.month, now.day, widget.suggestedHour ?? now.hour)
        : DateTime.parse(slot['starts_at']).toLocal();
    String subject = slot?['subject'] ?? '';
    final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Study subject'),
                content: TextFormField(
                    initialValue: subject,
                    maxLength: 120,
                    autofocus: true,
                    onChanged: (v) => subject = v),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, subject.trim()),
                      child: const Text('Choose time'))
                ]));
    if (!mounted || name == null || name.isEmpty) return;
    final day = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
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
    slots.remove(slot);
    slots.add({
      'id': slot?['id'] ?? const Uuid().v4(),
      'user_id': owner,
      'subject': name,
      'starts_at': from.toUtc().toIso8601String(),
      'ends_at': to.toUtc().toIso8601String(),
      'dirty': true
    });
    await sync();
  }

  @override
  Widget build(BuildContext context) {
    final visible = slots.where((r) => r['deleted'] != true).toList()
      ..sort((a, b) => a['starts_at'].compareTo(b['starts_at']) as int);
    return Scaffold(
        appBar: AppBar(title: const Text('Study planner')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: busy ? null : () => edit(),
            icon: const Icon(Icons.calendar_month),
            label: const Text('Schedule study')),
        body: busy
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  setState(() => busy = true);
                  await sync();
                },
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      if (notice != null)
                        ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: Text(notice!)),
                      if (visible.isEmpty)
                        const ListTile(
                            title: Text('Your study schedule is empty')),
                      for (final r in visible)
                        Card(
                            child: Column(children: [
                          ListTile(
                              title: Text(r['subject']),
                              subtitle: Text(
                                  "${MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(r['starts_at']).toLocal())} · ${TimeOfDay.fromDateTime(DateTime.parse(r['starts_at']).toLocal()).format(context)} – ${TimeOfDay.fromDateTime(DateTime.parse(r['ends_at']).toLocal()).format(context)}")),
                          Wrap(children: [
                            TextButton.icon(
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Study this subject'),
                                onPressed: () =>
                                    Navigator.pop(context, r['subject'])),
                            IconButton(
                                tooltip: 'Edit slot',
                                icon: const Icon(Icons.edit),
                                onPressed: () => edit(r)),
                            IconButton(
                                tooltip: 'Remove slot',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  setState(() => busy = true);
                                  r['dirty'] = true;
                                  r['deleted'] = true;
                                  await sync();
                                })
                          ])
                        ]))
                    ])));
  }
}
