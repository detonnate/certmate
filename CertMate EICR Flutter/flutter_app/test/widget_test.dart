import 'dart:io';

import 'package:certmate_eicr/main.dart';
import 'package:certmate_eicr/report.dart';
import 'package:certmate_eicr/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

void main() {
  test('generates a PDF from an offline job', () async {
    final store = Store(File('unused'), Store.decode('{}'));
    final bytes = await makeReport(
        store, {'id': 'job', 'reportNumber': 'EICR-2026-0001'});
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  testWidgets('shows the jobs and settings tabs', (tester) async {
    final store = Store(File('unused'), Store.decode('{}'));
    await pumpScreenshotApp(tester, Workspace(store: store));
    expect(find.text('New job'), findsOneWidget);
    await capture(tester, 'jobs');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Import backup'), findsOneWidget);
    await capture(tester, 'settings');
  });

  test(
      'loads legacy installation addresses and keeps circuit tests on duplication',
      () {
    final store = Store(File('unused'), Store.decode('''
      {"jobs":[{"id":"job","siteAddress":"10 High Street"}],
       "circuits":[{"id":"circuit","jobId":"job"}],
       "testResults":[{"id":"test","circuitId":"circuit","measuredZs":"0.50"}]}
    '''));
    final original = store.rows('jobs').single;
    expect(original['installationAddress'], '10 High Street');
    final copy = store.duplicate(original, 'EICR-2026-0002');
    final circuit = store.related('circuits', copy['id']).single;
    expect(circuit['id'], isNot('circuit'));
    expect(
      store
          .related('testResults', circuit['id'], key: 'circuitId')
          .single['measuredZs'],
      '0.50',
    );
  });
}
