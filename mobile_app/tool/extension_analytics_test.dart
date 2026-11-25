import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:focus_echo_ai/core/models/distraction_event.dart';
import 'package:focus_echo_ai/core/models/focus_session.dart';
import 'package:focus_echo_ai/core/providers/app_dependencies.dart';
import 'package:focus_echo_ai/features/analytics/analytics_screen.dart';
import 'package:focus_echo_ai/features/analytics/analytics_viewmodel.dart';
import 'package:focus_echo_ai/features/focus_session/focus_session_state.dart';
import 'package:focus_echo_ai/features/focus_session/focus_session_viewmodel.dart';
import 'package:focus_echo_ai/local_db/distraction_event_dao.dart';
import 'package:focus_echo_ai/local_db/focus_session_dao.dart';
import 'package:focus_echo_ai/services/backend_analytics_service.dart';
import 'package:focus_echo_ai/services/supabase_service.dart';

class _Sessions extends Fake implements FocusSessionDao {
  @override
  Future<List<FocusSession>> getSessionHistory(int limit) async => [];
}

class _Events extends Fake implements DistractionEventDao {
  @override
  Future<List<DistractionEvent>> getRecentEvents(int minutes,
          {String? eventType}) async =>
      [];
}

class _LoopbackHttp extends HttpOverrides {}

class _IdleSession extends StateNotifier<FocusSessionState>
    implements FocusSessionViewModel {
  _IdleSession() : super(const FocusSessionState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AnalyticsViewModel analytics;
  late SupabaseClient client;
  setUpAll(() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = 'http://127.0.0.1:${server.port}';
    final tables = {
      'focus_sessions': <String, dynamic>{},
      'distraction_events': <String, dynamic>{},
    };
    server.listen((request) async {
      final response = request.response;
      try {
        final table = tables[request.uri.pathSegments.last];
        response.headers.contentType = ContentType.json;
        if (table == null) {
          response.statusCode =
              request.uri.path.endsWith('/rpc/broadcast_intervention')
                  ? 204
                  : 404;
        } else if (request.method == 'GET') {
          response.write(jsonEncode(table.values.toList()));
        } else if (request.method == 'POST' &&
            request.headers.value('authorization') == 'Bearer fixture-token') {
          final data = jsonDecode(await utf8.decoder.bind(request).join());
          for (final row in data is List ? data : [data]) {
            if (row.containsKey('session_id') &&
                !tables['focus_sessions']!.containsKey(row['session_id'])) {
              response.statusCode = 409;
              return;
            }
            if (request.headers.value('prefer') ==
                'resolution=ignore-duplicates') {
              table.putIfAbsent(row['id'], () => row);
            } else {
              table[row['id']] = row;
            }
          }
          response.statusCode = 201;
        } else {
          response.statusCode = 403;
        }
      } finally {
        await response.close();
      }
    });
    addTearDown(() => server.close(force: true));
    final upload = await Process.run('node',
        ['../automation/integration/upload_distraction_fixture.mjs', url]);
    expect(upload.exitCode, 0, reason: '${upload.stdout}\n${upload.stderr}');
    expect(tables['distraction_events']!.length, 1);
    final state = await HttpOverrides.runWithHttpOverrides(() {
      client = SupabaseClient(url, 'fixture');
      AppDependencies.supabaseService = SupabaseService(client: client);
      analytics = AnalyticsViewModel(
          _Sessions(), _Events(), BackendAnalyticsService(),
          cloudClient: client);
      return analytics.stream
          .firstWhere((s) => !s.isLoading)
          .timeout(const Duration(seconds: 10));
    }, _LoopbackHttp());
    expect(state.errorMessage, isNull);
    expect(state.dailyDistractions.reduce((a, b) => a + b), 1);
    expect(state.appDistribution, {'Instagram': 1});
    expect(state.medianRecoverySeconds, 20);
  });
  testWidgets(
      'Analytics displays an extension distraction read through PostgREST',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      analyticsProvider.overrideWith((ref) => analytics),
      focusSessionProvider.overrideWith((ref) => _IdleSession()),
    ], child: const MaterialApp(home: AnalyticsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Available completed sessions'), findsOneWidget);
    expect(find.text('Distraction time · Today vs yesterday'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('Daily Distractions'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
