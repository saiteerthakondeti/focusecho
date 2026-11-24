import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_echo_ai/features/focus_session/study_planner.dart';

void main() {
  testWidgets('Offline planner reloads a saved subject and persists its removal', (tester) async {
    const key='study_slots_guest';
    SharedPreferences.setMockInitialValues({key:jsonEncode([{'id':'1','subject':'Algebra','starts_at':'2026-11-24T07:00:00Z','ends_at':'2026-11-24T08:00:00Z'}])});
    await tester.pumpWidget(const MaterialApp(home:StudyPlanner()));
    await tester.pumpAndSettle();
    expect(find.text('Algebra'),findsOneWidget);
    await tester.tap(find.byTooltip('Remove slot'));
    await tester.pumpAndSettle();
    expect(find.text('Your study schedule is empty'),findsOneWidget);
    final rows=jsonDecode((await SharedPreferences.getInstance()).getString(key)!) as List;
    expect(rows.where((r)=>r['deleted']!=true),isEmpty);
  });
}
