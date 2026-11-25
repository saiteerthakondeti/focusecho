import 'dart:convert';
import 'package:focus_echo_ai/features/focus_session/planned_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_echo_ai/features/focus_session/study_planner.dart';
import 'package:focus_echo_ai/services/workspace_data_migration.dart';

void main() {
  test('Guest Planner and Studio cache migrates to linked account', () async {
    SharedPreferences.setMockInitialValues({
      'study_slots_guest': jsonEncode([
        {'id': 'guest-task', 'user_id': 'guest', 'subject': 'Read'},
        {'id': 'shared-id', 'user_id': 'guest', 'subject': 'Guest copy'},
      ]),
      'study_slots_account': jsonEncode([
        {'id': 'shared-id', 'user_id': 'account', 'subject': 'Account copy'},
      ]),
      'planner_sessions_guest': jsonEncode({
        'guest-session': {'id': 'guest-task'}
      }),
      'planner_sessions_account': jsonEncode({
        'account-session': {'id': 'other'}
      }),
      'studio_clock_guest':
          jsonEncode({'session': 'guest-session', 'minutes': 25}),
    });
    final prefs = await SharedPreferences.getInstance();

    await migrateWorkspacePreferences(prefs, 'guest', 'account');

    final slots = jsonDecode(prefs.getString('study_slots_account')!) as List;
    final migrated = slots.singleWhere((row) => row['id'] == 'guest-task');
    expect(migrated['user_id'], 'account');
    expect(migrated['dirty'], true);
    expect(slots.singleWhere((row) => row['id'] == 'shared-id')['subject'],
        'Account copy');
    expect(prefs.getString('study_slots_guest'), isNull);
    final sessions = jsonDecode(prefs.getString('planner_sessions_account')!);
    expect(sessions.keys, containsAll(['guest-session', 'account-session']));
    expect(prefs.getString('planner_sessions_guest'), isNull);
    expect(jsonDecode(prefs.getString('studio_clock_account')!)['session'],
        'guest-session');
  });

  Future<void> verifySessionSync() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final writer = PlannerSessions(prefs, 'owner');
    await writer.link(
        'session', const PlannedFocus('task', 'Read', 'Chapter 1', 25, [], []));
    await writer.finish('session', {'focus_seconds': 120}, 'Deep Work', false);
    var available = false;
    final cloud = <String, dynamic>{};
    Future<bool> upload(String id, Map<String, dynamic> row) async {
      if (available) cloud[id] = row;
      return available;
    }

    await writer.synchronize(
        upload: upload, download: () async => cloud, allowed: () => true);
    expect(writer.records['session']['pending'], true);
    available = true;
    await writer.synchronize(
        upload: upload, download: () async => cloud, allowed: () => true);
    expect(writer.records['session']['pending'], false);
    expect(cloud['session']['subject'], 'Read');
    expect(cloud['session'].containsKey('pending'), false);
    await prefs.remove(writer.key);
    await writer.synchronize(
        upload: upload, download: () async => cloud, allowed: () => false);
    expect(writer.records, isEmpty);
    await writer.synchronize(
        upload: upload, download: () async => cloud, allowed: () => true);
    expect(writer.records['session']['focus_seconds'], 120);
    expect(PlannerSessions(prefs, 'other').records, isEmpty);
  }

  testWidgets(
      'Offline planner reloads a saved subject and persists its removal',
      (tester) async {
    await verifySessionSync();
    const key = 'study_slots_guest';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode([
        {
          'id': '1',
          'subject': 'Algebra',
          'starts_at': '2026-11-24T07:00:00Z',
          'ends_at': '2026-11-24T08:00:00Z'
        }
      ])
    });
    PlannedFocus? picked;
    await tester.pumpWidget(
        MaterialApp(home: StudyPlanner(onStart: (value) => picked = value)));
    await tester.pumpAndSettle();
    expect(find.text('Algebra'), findsOneWidget);
    await tester.tap(find.text('Start Focus'));
    expect(picked?.id, '1');
    expect(picked?.minutes, 60);
    expect(picked?.subject, 'Algebra');
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark complete'));
    await tester.pumpAndSettle();
    expect(find.text('Reopen'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove slot'));
    await tester.pumpAndSettle();
    expect(find.text('Your study schedule is empty'), findsOneWidget);
    final rows =
        jsonDecode((await SharedPreferences.getInstance()).getString(key)!)
            as List;
    expect(rows.where((r) => r['deleted'] != true), isEmpty);
  });
}
