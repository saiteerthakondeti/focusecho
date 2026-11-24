import 'package:flutter_test/flutter_test.dart';
import 'package:focus_echo_ai/features/analytics/study_metrics.dart';
import 'package:focus_echo_ai/core/models/distraction_event.dart';

void main() {
  for (final hour in [0, 1, 7, 12, 23]) {
    for (final offset in [-86401,-86400,-86399,-1,0,1,86399]) {
      for (final duration in [1,2,10,59,60,61,300,1800,3600,86400]) {
        test('Distraction window at hour $hour, offset ${offset}s, duration ${duration}s', () {
          final midnight = DateTime(2026, 6, 15);
          final start = midnight.add(Duration(seconds:offset));
          final event = DistractionEvent(id:'e',sessionId:'s',packageName:'video',
              appLabel:'Video',riskScore:'low',triggeredAt:start,timeAwaySeconds:duration);
          final result=StudyMetrics.calculate([event],[],midnight.add(Duration(hours:hour)));
          int overlap(int lo,int hi) =>
            ((offset+duration).clamp(lo,hi) - offset.clamp(lo,hi)).toInt();
          expect(result.today,overlap(0,hour*3600));
          expect(result.yesterday,overlap(-86400,0));
          expect(result.previousAtThisTime,overlap(-86400,hour*3600-86400));
        });
      }
    }
  }
}
