import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/models/subsession.dart';

void main() {
  group('Subsession.fromJson', () {
    test('parses a full snapshot', () {
      final sub = Subsession.fromJson({
        'subsession_id': 'sub-1',
        'kind': 'periodic',
        'owner_session_id': 'sess-1',
        'parent_id': null,
        'depth': 1,
        'title': 'Monitor: deploy',
        'prompt': 'watch the deploy',
        'model_level': 1,
        'status': 'sleeping',
        'created_at': 1.5,
        'last_activity_at': 2.5,
        'interval_seconds': 3600.0,
        'anchor_time': null,
        'next_run_at': 3.5,
        'runs': 7,
        'max_runs': 100,
        'last_result': 'no change',
        'summary': 'done',
        'close_reason': null,
        'error': null,
      });

      expect(sub.subsessionId, 'sub-1');
      expect(sub.kind, 'periodic');
      expect(sub.ownerSessionId, 'sess-1');
      expect(sub.parentId, isNull);
      expect(sub.depth, 1);
      expect(sub.title, 'Monitor: deploy');
      expect(sub.prompt, 'watch the deploy');
      expect(sub.modelLevel, 1);
      expect(sub.status, 'sleeping');
      expect(sub.createdAt, 1.5);
      expect(sub.lastActivityAt, 2.5);
      expect(sub.intervalSeconds, 3600.0);
      expect(sub.nextRunAt, 3.5);
      expect(sub.runs, 7);
      expect(sub.maxRuns, 100);
      expect(sub.lastResult, 'no change');
      expect(sub.summary, 'done');
      expect(sub.closeReason, isNull);
      expect(sub.error, isNull);
    });

    test('defaults missing optional fields', () {
      final sub = Subsession.fromJson({'subsession_id': 'sub-2'});

      expect(sub.subsessionId, 'sub-2');
      expect(sub.kind, 'task');
      expect(sub.ownerSessionId, '');
      expect(sub.title, '');
      expect(sub.status, 'unknown');
      expect(sub.isActive, isFalse);
      expect(sub.isMonitor, isFalse);
    });

    test('isActive is true only for live statuses', () {
      for (final status in ['running', 'waiting', 'sleeping', 'paused']) {
        final sub = Subsession.fromJson({
          'subsession_id': 's',
          'status': status,
        });
        expect(sub.isActive, isTrue, reason: status);
      }
      for (final status in ['closed', 'failed', 'interrupted']) {
        final sub = Subsession.fromJson({
          'subsession_id': 's',
          'status': status,
        });
        expect(sub.isActive, isFalse, reason: status);
      }
    });

    test('isMonitor is true for periodic and wait_for_event kinds', () {
      expect(
        Subsession.fromJson({'subsession_id': 's', 'kind': 'periodic'})
            .isMonitor,
        isTrue,
      );
      expect(
        Subsession.fromJson({'subsession_id': 's', 'kind': 'wait_for_event'})
            .isMonitor,
        isTrue,
      );
      expect(
        Subsession.fromJson({'subsession_id': 's', 'kind': 'task'}).isMonitor,
        isFalse,
      );
    });
  });
}
