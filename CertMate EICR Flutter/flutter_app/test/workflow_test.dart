import 'dart:io';

import 'package:certmate_eicr/main.dart';
import 'package:certmate_eicr/store.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

void main() {
  late Store store;
  late Record job;

  setUp(() async {
    final directory =
        await Directory.systemTemp.createTemp('certmate-workflow-');
    addTearDown(() => directory.delete(recursive: true));
    store = Store(File('${directory.path}/jobs.json'), Store.decode('''
      {"jobs":[{"id":"job","reportNumber":"EICR-TEST","clientName":"Sample Client",
      "installationAddress":"10 Sample Street"}]}
    '''));
    job = store.rows('jobs').single;
  });

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('jobs: search by address and open the matching job',
      (tester) async {
    store.rows('jobs').add({'id': 'other', 'reportNumber': 'EICR-OTHER'});
    await pumpScreenshotApp(tester, Workspace(store: store));
    await tester.enterText(find.byType(TextField), 'sample street');
    await tester.pumpAndSettle();
    expect(find.text('EICR-OTHER'), findsNothing);
    await tap(tester, 'EICR-TEST');
    expect(find.text('Job and installation details'), findsOneWidget);
    await capture(tester, 'job-overview');
  });

  testWidgets('checklist: create and confirm bulk marking', (tester) async {
    await pumpScreenshotApp(
        tester,
        Workspace(
          store: store,
          job: job,
          table: 'inspectionItems',
        ));
    await tap(tester, 'Create default checklist');
    final items = store.related('inspectionItems', job['id']);
    expect(items, isNotEmpty);
    expect(items.every((row) => row['result'] == ''), isTrue);
    await tap(tester, 'Mark all satisfactory');
    await tap(tester, 'Cancel');
    expect(items.every((row) => row['result'] == ''), isTrue);
    await tap(tester, 'Mark all satisfactory');
    await tap(tester, 'Mark all');
    expect(items.every((row) => row['result'] == '✓'), isTrue);
    expect(find.text('${items.length} of ${items.length} completed'),
        findsOneWidget);
    await capture(tester, 'checklist-completed');
  });

  testWidgets('circuits: add the standard set and blank tests', (tester) async {
    await pumpScreenshotApp(
        tester,
        Workspace(
          store: store,
          job: job,
          table: 'circuits',
        ));
    await tap(tester, 'Standard Job Builder');
    await capture(tester, 'standard-job-builder');
    await tap(tester, 'Add circuits');
    final circuits = store.related('circuits', job['id']);
    expect(circuits, hasLength(10));
    expect(circuits.map((row) => row['circuitNumber']).toSet(), hasLength(10));
    for (final circuit in circuits) {
      expect(store.related('testResults', circuit['id'], key: 'circuitId'),
          hasLength(1));
    }
  });

  testWidgets('locked report hides mutation controls', (tester) async {
    job['isLocked'] = true;
    await pumpScreenshotApp(tester, Workspace(store: store, job: job));
    expect(find.text('Signed'), findsOneWidget);
    expect(find.text('Sign and lock report'), findsNothing);
    expect(find.text('Standard Job Builder'), findsNothing);
    await tap(tester, 'Circuits and tests');
    expect(find.text('Add circuit'), findsNothing);
    expect(find.text('Add circuit preset'), findsNothing);
  });

  testWidgets('validation: apply an unsatisfactory assessment for a C2',
      (tester) async {
    store.rows('observations').add({
      'id': 'obs',
      'jobId': job['id'],
      'classification': 'C2',
    });
    await pumpScreenshotApp(tester, Workspace(store: store, job: job));
    await tap(tester, 'Validation');
    expect(find.textContaining('C1, C2 or FI findings'), findsOneWidget);
    await capture(tester, 'validation-critical');
    await tap(tester, 'Apply Unsatisfactory assessment');
    expect(job['overallAssessment'], 'Unsatisfactory');
  });
}
