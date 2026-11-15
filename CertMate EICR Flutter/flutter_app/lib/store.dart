import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

typedef Record = Map<String, dynamic>;

const tables = [
  'jobs',
  'supplyDetails',
  'distributionBoards',
  'circuits',
  'testResults',
  'observations',
  'photos',
  'inspectionItems',
];

String newId() => const Uuid().v4();
String value(Record row, String key) => row[key]?.toString() ?? '';

class Store {
  Store(this.file, this.data);

  final File file;
  final Record data;
  Future<void> _pending = Future.value();

  static Future<Store> open() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/certmate.json');
    final data =
        await file.exists() ? decode(await file.readAsString()) : decode('{}');
    return Store(file, data);
  }

  static Record decodeBackup(String source) {
    final document = jsonDecode(source);
    if (document is! Map ||
        document['jobs'] is! List ||
        document['circuits'] is! List ||
        document['testResults'] is! List) {
      throw const FormatException('Select a CertMate JSON backup.');
    }
    return decode(source);
  }

  static Record decode(String source) {
    final data = Map<String, dynamic>.from(jsonDecode(source) as Map);
    for (final table in tables) {
      final records = data[table] as List? ?? [];
      data[table] = records.map((record) {
        final row = Map<String, dynamic>.from(record as Map);
        if (row['id'] is! String) {
          throw FormatException('Missing identifier in $table');
        }
        return row;
      }).toList();
    }
    data['company'] = Map<String, dynamic>.from(data['company'] as Map? ?? {});
    for (final job in (data['jobs'] as List<Record>)) {
      for (final (current, legacy) in [
        ('installationAddress', 'siteAddress'),
        ('installationPostcode', 'postcode'),
      ]) {
        if (value(job, current).isEmpty) job[current] = value(job, legacy);
      }
    }
    return data;
  }

  List<Record> rows(String table) => data[table] as List<Record>;
  List<Record> related(String table, Object? id, {String key = 'jobId'}) =>
      rows(table).where((row) => row[key] == id).toList();
  Record get company => data['company'] as Record;

  Future<void> save() {
    final snapshot = jsonEncode(data);
    final write = _pending.then((_) async {
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(file.path);
    });
    _pending = write.catchError((Object _) {});
    return write;
  }

  void remove(String table, Record row) {
    final id = row['id'];
    if (table == 'jobs') {
      for (final child
          in tables.skip(1).where((name) => name != 'testResults')) {
        for (final relatedRow in related(child, id)) {
          remove(child, relatedRow);
        }
      }
    }
    if (table == 'circuits') {
      rows('testResults').removeWhere((test) => test['circuitId'] == id);
    }
    if (table == 'observations') {
      rows('photos').removeWhere((photo) => photo['observationId'] == id);
    }
    rows(table).remove(row);
  }

  void merge(Record backup) {
    for (final table in tables) {
      final byId = {
        for (final row in rows(table)) value(row, 'id').toLowerCase(): row,
      };
      for (final row in backup[table] as List<Record>) {
        byId.putIfAbsent(value(row, 'id').toLowerCase(), () => row);
      }
      data[table] = byId.values.toList();
    }
    if (company.isEmpty) company.addAll(backup['company'] as Record);
  }

  Record duplicate(
    Record job,
    String reportNumber, {
    bool copyCircuits = true,
    bool copyTests = true,
    bool clearReadings = false,
    bool copyObservations = true,
    bool copyPhotos = true,
  }) {
    final copy = {
      ...job,
      'id': newId(),
      'reportNumber': reportNumber,
      'isLocked': false,
      'status': 'Draft',
    }
      ..remove('signatureData')
      ..remove('signedAt')
      ..remove('savedPDFPath')
      ..remove('savedPdfData');
    rows('jobs').add(copy);
    final references = <Object?, String>{};
    for (final table
        in tables.skip(1).where((table) => table != 'testResults')) {
      if (table == 'circuits' && !copyCircuits ||
          table == 'observations' && !copyObservations ||
          table == 'photos' && (!copyObservations || !copyPhotos)) {
        continue;
      }
      for (final row in related(table, job['id'])) {
        final id = newId();
        references[row['id']] = id;
        final child = {...row, 'id': id, 'jobId': copy['id']};
        if (table == 'photos') {
          child['observationId'] = references[row['observationId']];
        }
        rows(table).add(child);
      }
    }
    for (final row in [...rows('testResults')]) {
      final circuitId = references[row['circuitId']];
      if (circuitId != null && copyTests) {
        rows('testResults').add({
          if (!clearReadings) ...row,
          'id': newId(),
          'circuitId': circuitId
        });
      }
    }
    return copy;
  }
}

String? referenceZs(Record circuit) {
  final device = value(circuit, 'protectiveDeviceType').toUpperCase();
  final multiplier = {
    'B': 5,
    'C': 10,
    'D': 20,
  }[value(circuit, 'protectiveDeviceCurve').toUpperCase()];
  final rating = double.tryParse(value(circuit, 'protectiveDeviceRating'));
  if (!['MCB', 'RCBO'].contains(device) ||
      multiplier == null ||
      rating == null ||
      !rating.isFinite ||
      rating <= 0) {
    return null;
  }
  return (0.95 * 230 / (multiplier * rating)).toStringAsFixed(2);
}

List<({String severity, String message})> validate(Store store, Record job) {
  final issues = <({String severity, String message})>[];
  void add(String severity, String message) =>
      issues.add((severity: severity, message: message));
  bool blank(Record row, String key) => value(row, key).trim().isEmpty;
  List<Record> records(String table) => store.related(table, job['id']);
  for (final (key, label) in [
    ('clientName', 'Client name'),
    ('clientAddress', 'Client address'),
    ('reasonForReport', 'Reason for report'),
    ('extentCovered', 'Extent covered'),
  ]) {
    if (blank(job, key)) add('Warning', '$label is missing.');
  }
  if (blank(job, 'installationAddress')) {
    add('Critical', 'Installation address is missing.');
  }
  if (blank(job, 'limitations')) {
    add('Info', 'Limitations are blank. Use N/A if none.');
  }
  final supply = records('supplyDetails').firstOrNull;
  if (supply == null) {
    add('Critical', 'Supply details have not been completed.');
  } else {
    for (final (key, label) in [
      ('ze', 'Ze'),
      ('pfc', 'PFC / PSCC'),
      ('earthingConductorSize', 'Earthing conductor size'),
      ('mainBondingConductorSize', 'Main bonding conductor size'),
    ]) {
      if (blank(supply, key)) {
        add('Warning', '$label is missing from supply details.');
      }
    }
  }
  final boards = records('distributionBoards');
  if (boards.isEmpty) add('Critical', 'No distribution board has been added.');
  for (final board in boards) {
    final reference = value(board, 'reference');
    if (blank(board, 'reference')) {
      add('Warning', 'A board is missing its reference.');
    }
    if (blank(board, 'location')) {
      add('Warning', 'Board $reference has no location.');
    }
    if (blank(board, 'incomerRating')) {
      add('Warning', 'Board $reference has no incomer rating.');
    }
  }
  final circuits = records('circuits');
  if (circuits.isEmpty) add('Critical', 'No circuits have been added.');
  for (final circuit in circuits) {
    final name = "Circuit ${value(circuit, 'circuitNumber')}";
    if (blank(circuit, 'descriptionText')) {
      add('Warning', '$name has no description.');
    }
    final test = store
        .related('testResults', circuit['id'], key: 'circuitId')
        .firstOrNull;
    if (test == null) {
      add('Critical', '$name has no test result record.');
      continue;
    }
    if (blank(test, 'r1r2') && blank(test, 'r2')) {
      add('Warning', '$name has no continuity result.');
    }
    if (blank(test, 'insulationLE')) {
      add('Warning', '$name has no insulation resistance L–E.');
    }
    if (blank(test, 'measuredZs')) add('Warning', '$name has no measured Zs.');
    final measured = double.tryParse(value(test, 'measuredZs'));
    final maximum = double.tryParse(value(test, 'maxZs'));
    if (measured != null && maximum != null && measured > maximum) {
      add('Critical', '$name measured Zs exceeds max Zs.');
    }
    if (test['polarity'] == 'Fail') add('Critical', '$name polarity failed.');
    if (test['functionalTest'] == 'Fail') {
      add('Critical', '$name functional test failed.');
    }
  }
  final items = records('inspectionItems');
  if (items.isEmpty) {
    add('Critical', 'Inspection checklist has not been created.');
  }
  final incomplete = items.where((row) => blank(row, 'result')).length;
  if (incomplete > 0) {
    add('Warning', '$incomplete checklist items have no result.');
  }
  const serious = {'C1', 'C2', 'FI'};
  if (job['overallAssessment'] != 'Unsatisfactory' &&
      (items.any((row) => serious.contains(row['result'])) ||
          records('observations')
              .any((row) => serious.contains(row['classification'])))) {
    add(
      'Critical',
      'C1, C2 or FI findings require an Unsatisfactory assessment.',
    );
  }
  if (job['signatureData'] == null) add('Info', 'Report has not been signed.');
  return issues;
}
