import 'dart:io';

import 'package:certmate_eicr/editor.dart';
import 'package:certmate_eicr/presets.dart';
import 'package:certmate_eicr/store.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

const fixture = '''
{
  "jobs":[{"id":"job","overallAssessment":"Satisfactory"}],
  "circuits":[{"id":"circuit","jobId":"job","circuitNumber":"1"}],
  "testResults":[{"id":"test","circuitId":"circuit","maxZs":"0.50",
                  "measuredZs":"0.60","polarity":"Fail"}],
  "observations":[{"id":"observation","jobId":"job","classification":"C2"}],
  "photos":[{"id":"photo","jobId":"job","observationId":"observation"}]
}
''';

void main() {
  late Store store;
  late Record job;

  setUp(() {
    store = Store(File('unused'), Store.decode(fixture));
    job = store.rows('jobs').single;
  });

  test('flags high Zs, failed polarity and serious findings independently', () {
    final critical = validate(store, job)
        .where((issue) => issue.severity == 'Critical')
        .map((issue) => issue.message);
    expect(
        critical,
        containsAll([
          'Circuit 1 measured Zs exceeds max Zs.',
          'Circuit 1 polarity failed.',
          'C1, C2 or FI findings require an Unsatisfactory assessment.',
        ]));
    job['overallAssessment'] = 'Unsatisfactory';
    expect(
        validate(store, job).map((issue) => issue.message),
        isNot(contains(
            'C1, C2 or FI findings require an Unsatisfactory assessment.')));
  });

  test('calculates reference Zs for supported curves and rejects invalid data',
      () {
    final circuit = {
      'protectiveDeviceType': 'MCB',
      'protectiveDeviceRating': '32',
    };
    for (final (curve, expected) in [
      ('B', '1.37'),
      ('C', '0.68'),
      ('D', '0.34')
    ]) {
      expect(
          referenceZs({...circuit, 'protectiveDeviceCurve': curve}), expected);
    }
    expect(referenceZs({...circuit, 'protectiveDeviceCurve': 'A'}), isNull);
    expect(
        referenceZs({
          ...circuit,
          'protectiveDeviceCurve': 'B',
          'protectiveDeviceRating': '0'
        }),
        isNull);
  });

  test('deleting a job removes its dependent records', () {
    store.rows('jobs').add({'id': 'other'});
    store.rows('circuits').add({'id': 'other-circuit', 'jobId': 'other'});
    store.remove('jobs', job);
    expect(store.rows('jobs').single['id'], 'other');
    expect(store.rows('circuits').single['id'], 'other-circuit');
    for (final table in ['testResults', 'observations', 'photos']) {
      expect(store.rows(table), isEmpty, reason: table);
    }
  });

  test('duplicate can clear readings and omit observations and photos', () {
    job['isLocked'] = true;
    job['savedPdfData'] = 'original PDF';
    final copy = store.duplicate(job, 'NEW',
        clearReadings: true, copyObservations: false);
    final circuit = store.related('circuits', copy['id']).single;
    final test =
        store.related('testResults', circuit['id'], key: 'circuitId').single;
    expect(test['measuredZs'], isNull);
    expect(store.rows('testResults').first['measuredZs'], '0.60');
    expect(store.related('observations', copy['id']), isEmpty);
    expect(store.related('photos', copy['id']), isEmpty);
    expect(copy['isLocked'], false);
    expect(copy['savedPdfData'], isNull);
  });

  test('backup merge keeps existing records and adds new ones', () {
    store.merge(Store.decode('{"jobs":[{"id":"job","clientName":"Backup"},'
        '{"id":"new","siteAddress":"2 High Street"}]}'));
    expect(store.rows('jobs'), hasLength(2));
    expect(store.rows('jobs').first['clientName'], isNull);
    expect(store.rows('jobs').last['installationAddress'], '2 High Street');
  });

  test('queued saves persist the latest complete snapshot', () async {
    final directory = await Directory.systemTemp.createTemp('certmate-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/store.json');
    final local = Store(file, Store.decode(fixture));
    final first = local.save();
    local.rows('jobs').single['clientName'] = 'Updated';
    await Future.wait([first, local.save()]);
    final restored = Store(file, Store.decode(await file.readAsString()));
    expect(restored.rows('jobs').single['clientName'], 'Updated');
    expect(restored.rows('testResults').single['measuredZs'], '0.60');
  });

  test('includes all three Swift standard circuit sets', () {
    expect(presets.map((name, rows) => MapEntry(name, rows.length)), {
      'Standard Domestic': 10,
      'Small Flat': 5,
      'Larger House': 10,
    });
  });

  test('backup import rejects unrelated JSON before offering replacement', () {
    for (final source in ['{}', '[]', '{"jobs":[]}', 'invalid JSON']) {
      expect(() => Store.decodeBackup(source), throwsFormatException);
    }
    expect(Store.decodeBackup(fixture)['jobs'], hasLength(1));
    expect(
        Store.decodeBackup(
            '{"jobs":[],"circuits":[],"testResults":[]}')['jobs'],
        isEmpty);
  });

  testWidgets('premises dropdown saves the selected value', (tester) async {
    Record? saved;
    await pumpScreenshotApp(tester, Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
        onPressed: () async {
          saved = await editRecord(context, 'Edit job', 'jobs', {
            'premisesType': 'Domestic'
          }, skip: {
            'reportNumber',
            'clientName',
            'reasonForReport',
            'extentCovered',
            'limitations',
            'overallAssessment',
            'engineerName',
            'companyName',
            'companyAddress',
            'companyPhone',
            'companyEmail',
            'clientAddress',
            'installationAddress',
            'installationPostcode',
            'clientPostcode',
          });
        },
        child: const Text('Edit'),
      ));
    }));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Domestic'));
    await tester.pumpAndSettle();
    await capture(tester, 'premises-type-options');
    await tester.tap(find.text('Commercial').last);
    await tester.pumpAndSettle();
    await capture(tester, 'premises-type-selected');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?['premisesType'], 'Commercial');
  });
}
