import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import 'editor.dart';
import 'report.dart';
import 'presets.dart';
import 'schema.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CertMate());
}

class CertMate extends StatefulWidget {
  const CertMate({super.key});

  @override
  State<CertMate> createState() => _CertMateState();
}

class _CertMateState extends State<CertMate> {
  late final Future<Store> store = Store.open();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CertMate EICR',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xff00695c),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: FutureBuilder(
          future: store,
          builder: (context, snapshot) => switch (snapshot) {
            AsyncSnapshot(:final data?) => Workspace(store: data),
            AsyncSnapshot(:final error?) => Scaffold(
                body: Center(child: Text('Could not open jobs: $error')),
              ),
            _ =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          },
        ),
      );
}

const sections = {
  'supplyDetails': 'Supply details',
  'distributionBoards': 'Distribution boards',
  'circuits': 'Circuits and tests',
  'inspectionItems': 'Inspection checklist',
  'observations': 'Observations',
};

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.store,
    this.job,
    this.table,
    this.record,
  });

  final Store store;
  final Record? job;
  final String? table;
  final Record? record;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  Store get store => widget.store;
  Record? get job => widget.job;
  String? get table => widget.table;
  Record? get record => widget.record;
  bool get locked => job?['isLocked'] == true;
  int tab = 0;
  String search = '';

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> persist() async {
    if (mounted) setState(() {});
    await store.save();
  }

  Future<void> open({Record? job, String? table, Record? record}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            Workspace(store: store, job: job, table: table, record: record),
      ),
    );
    if (mounted) setState(() {});
  }

  String reportNumber() {
    final year = DateTime.now().year;
    var number = 1;
    final used =
        store.rows('jobs').map((row) => value(row, 'reportNumber')).toSet();
    while (used.contains('EICR-$year-${number.toString().padLeft(4, '0')}')) {
      number++;
    }
    return 'EICR-$year-${number.toString().padLeft(4, '0')}';
  }

  List<Record> related(String table) => store.related(table, job!['id']);

  Future<bool> confirm(String title, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action)),
            ],
          ),
        ) ??
        false;
  }

  Widget deleteButton(String name, Record row, String title,
      {bool close = false}) {
    return IconButton(
      icon: const Icon(Icons.delete_outline),
      tooltip: 'Delete $title',
      onPressed: () => run(() async {
        if (!await confirm('Delete $title?', 'Delete') || !mounted) return;
        store.remove(name, row);
        await persist();
        if (close && mounted) Navigator.pop(context);
      }),
    );
  }

  Future<void> duplicateJob(Record current) async {
    final options = {
      'Copy circuits': true,
      'Copy test results': true,
      'Clear test readings': true,
      'Copy observations': false,
      'Copy photos': false,
    };
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                title: const Text('Duplicate job'),
                content: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in options.entries)
                      CheckboxListTile(
                        title: Text(option.key),
                        value: option.value,
                        onChanged: switch (option.key) {
                          'Copy test results' when !options['Copy circuits']! =>
                            null,
                          'Clear test readings'
                              when !options['Copy circuits']! ||
                                  !options['Copy test results']! =>
                            null,
                          'Copy photos' when !options['Copy observations']! =>
                            null,
                          _ => (checked) =>
                              update(() => options[option.key] = checked!),
                        },
                      ),
                  ],
                )),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Continue')),
                ],
              )),
    );
    if (accepted != true || !mounted) return;
    final number = reportNumber();
    final details = await editRecord(
      context,
      'Duplicate job',
      'jobs',
      {...current, 'reportNumber': number},
      skip: fields['jobs']!.keys.toSet().difference({
        'clientName',
        'clientAddress',
        'clientPostcode',
        'installationAddress',
        'installationPostcode',
      }),
    );
    if (details == null || !mounted) return;
    final copy = store.duplicate(
      details,
      number,
      copyCircuits: options['Copy circuits']!,
      copyTests: options['Copy test results']!,
      clearReadings: options['Clear test readings']!,
      copyObservations: options['Copy observations']!,
      copyPhotos: options['Copy photos']!,
    );
    await persist();
    if (mounted) await open(job: copy);
  }

  Future<void> saveFile(String name, Uint8List bytes) async {
    final path =
        await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
    if (path != null &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      await File(path).writeAsBytes(bytes);
    }
  }

  Future<void> buildStandardJob() async {
    var preset = 'Standard Domestic';
    var tests = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                title: const Text('Standard Job Builder'),
                content: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: preset,
                      items: [
                        for (final name in presets.keys)
                          DropdownMenuItem(value: name, child: Text(name))
                      ],
                      onChanged: (name) => update(() => preset = name!),
                    ),
                    CheckboxListTile(
                      title: const Text('Create blank test result records'),
                      value: tests,
                      onChanged: (checked) => update(() => tests = checked!),
                    ),
                    for (final circuit in presets[preset]!)
                      ListTile(
                          title: Text(circuit['descriptionText']!),
                          subtitle: Text(
                            "${circuit['protectiveDeviceType']} ${circuit['protectiveDeviceRating']} A",
                          )),
                  ],
                )),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        related('circuits').isEmpty
                            ? 'Add circuits'
                            : 'Add to existing circuits',
                      )),
                ],
              )),
    );
    if (accepted != true || !mounted) return;
    final used =
        related('circuits').map((row) => value(row, 'circuitNumber')).toSet();
    final board = related('distributionBoards').firstOrNull;
    var number = 1;
    for (final presetCircuit in presets[preset]!) {
      while (used.contains('$number')) {
        number++;
      }
      final id = newId();
      store.rows('circuits').add({
        ...presetCircuit,
        'id': id,
        'jobId': job!['id'],
        'circuitNumber': '${number++}',
        'protectiveDeviceCurve': 'B',
        'distributionBoardReference':
            board == null ? 'DB1' : value(board, 'reference'),
      });
      if (tests) {
        store.rows('testResults').add({'id': newId(), 'circuitId': id});
      }
    }
    await persist();
  }

  Future<void> edit(String name, String title, {Record? existing}) async {
    final initial = existing ??
        <String, dynamic>{
          'id': newId(),
          if (name != 'jobs' && name != 'testResults') 'jobId': job!['id'],
          if (name == 'testResults') 'circuitId': record!['id'],
          if (name == 'jobs') ...{
            ...store.company,
            'id': newId(),
            'reportNumber': reportNumber(),
            'status': 'Draft',
            'premisesType': 'Domestic',
            'overallAssessment': 'Satisfactory',
            if (store.company['logoData'] != null)
              'companyLogoData': store.company['logoData'],
          },
          if (name == 'observations')
            'observationNumber': related(name).fold<int>(0, (max, row) {
                  final number =
                      int.tryParse(value(row, 'observationNumber')) ?? 0;
                  return number > max ? number : max;
                }) +
                1,
          if (name == 'testResults') 'maxZs': referenceZs(record!),
        };
    final result = await editRecord(
      context,
      title,
      name,
      initial,
      locked: locked,
      skip: name == 'inspectionItems'
          ? {'section', 'itemNumber', 'itemText'}
          : {},
      options: {
        if (name == 'circuits' && related('distributionBoards').isNotEmpty)
          'distributionBoardReference': related('distributionBoards')
              .map((row) => value(row, 'reference'))
              .toList(),
      },
    );
    if (result == null || !mounted) return;
    if (existing == null) {
      store.rows(name).add(result);
    } else {
      existing.addAll(result);
    }
    await persist();
    if (name == 'jobs' && existing == null && mounted) await open(job: result);
  }

  Widget tile(
    String title,
    VoidCallback onTap, {
    String? subtitle,
    Widget? trailing,
    IconData? icon,
  }) =>
      ListTile(
        leading: icon == null ? null : Icon(icon),
        title: Text(title),
        subtitle: subtitle == null || subtitle.isEmpty ? null : Text(subtitle),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final title = table == null
        ? (job == null ? 'CertMate EICR' : value(job!, 'reportNumber'))
        : sections[table]!;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: job == null
                ? home()
                : table == null
                    ? overview()
                    : section(),
          ),
        ),
      ),
      floatingActionButton: job == null && tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => run(() => edit('jobs', 'New job')),
              icon: const Icon(Icons.add),
              label: const Text('New job'),
            )
          : null,
      bottomNavigationBar: job == null
          ? NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (index) => setState(() => tab = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.work_outline),
                  label: 'Jobs',
                ),
                NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  label: 'Reports',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Settings',
                ),
              ],
            )
          : null,
    );
  }

  List<Widget> home() {
    if (tab == 2) {
      return [
        tile(
          'Company profile',
          () => run(() async {
            final result = await editRecord(
              context,
              'Company profile',
              'company',
              store.company,
            );
            if (result != null) {
              store.company.addAll(result);
              await persist();
            }
          }),
          icon: Icons.business_outlined,
        ),
        tile(
          'Company logo',
          () => run(() async {
            final image = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1000,
            );
            if (image == null) return;
            store.company['logoData'] = base64Encode(await image.readAsBytes());
            await persist();
          }),
          icon: Icons.image_outlined,
        ),
        tile(
          'Export backup',
          () => run(() async {
            final bytes = Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  ...store.data,
                  'createdAt':
                      DateTime.now().millisecondsSinceEpoch / 1000 - 978307200,
                }),
              ),
            );
            await saveFile('CertMate-backup.json', bytes);
          }),
          icon: Icons.upload_file,
        ),
        tile(
          'Import backup',
          () => run(() async {
            final selection = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['json'],
              withData: true,
            );
            if (selection == null) return;
            final backup = Store.decodeBackup(
              utf8.decode(selection.files.single.bytes!),
            );
            if (!mounted) return;
            final mode = await showDialog<String>(
              context: context,
              builder: (context) =>
                  SimpleDialog(title: const Text('Import backup'), children: [
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'merge'),
                    child: const Text('Merge with existing data')),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'replace'),
                    child: const Text('Replace all existing data')),
              ]),
            );
            if (mode == null || !mounted) return;
            if (mode == 'replace') {
              if (!await confirm(
                      'Replace all local jobs and settings?', 'Replace') ||
                  !mounted) {
                return;
              }
              store.data
                ..clear()
                ..addAll(backup);
            } else {
              store.merge(backup);
            }
            await persist();
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Backup imported')));
            }
          }),
          icon: Icons.download,
        ),
      ];
    }
    final jobs = store
        .rows('jobs')
        .reversed
        .where((row) => tab == 0 || row['savedPdfData'] is String)
        .where((row) =>
            ['clientName', 'reportNumber', 'installationAddress'].any(
              (key) =>
                  value(row, key).toLowerCase().contains(search.toLowerCase()),
            ))
        .toList();
    return [
      TextField(
        decoration: const InputDecoration(
            labelText: 'Search client, report or address',
            prefixIcon: Icon(Icons.search)),
        onChanged: (text) => setState(() => search = text.trim()),
      ),
      if (jobs.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            search.isNotEmpty
                ? 'No matching jobs.'
                : tab == 0
                    ? 'Create a job to start an inspection.'
                    : 'Generated PDFs appear here.',
          ),
        ),
      for (final row in jobs)
        tile(
          value(row, 'reportNumber'),
          () => run(() => tab == 0 ? open(job: row) : openReport(row)),
          subtitle: [
            value(row, 'clientName'),
            value(row, 'installationAddress'),
          ].where((text) => text.isNotEmpty).join(' · '),
          trailing: tab == 0
              ? deleteButton('jobs', row, 'job and associated records')
              : null,
          icon: row['isLocked'] == true
              ? Icons.lock_outline
              : Icons.description_outlined,
        ),
    ];
  }

  Future<void> openReport(Record current, {bool generate = false}) async {
    final existing = current['savedPdfData'] as String?;
    final bytes = generate || existing == null
        ? Uint8List.fromList(await makeReport(store, current))
        : base64Decode(existing);
    if (generate) {
      current['savedPdfData'] = base64Encode(bytes);
      await persist();
    }
    if (!mounted) return;
    final filename = '${value(current, 'reportNumber')}.pdf';
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Report preview'), actions: [
          IconButton(
            tooltip: 'Save PDF',
            icon: const Icon(Icons.save_alt),
            onPressed: () => run(() => saveFile(filename, bytes)),
          ),
        ]),
        body: PdfPreview(
          build: (_) async => bytes,
          pdfFileName: filename,
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
        ),
      ),
    ));
  }

  List<Widget> overview() {
    final current = job!;
    final issues = validate(store, current);
    final critical =
        issues.where((issue) => issue.severity == 'Critical').length;
    return [
      ListTile(
        title: Text(value(current, 'clientName')),
        subtitle: Text(value(current, 'installationAddress')),
        trailing: Chip(label: Text(locked ? 'Signed' : 'Draft')),
      ),
      tile(
        'Job and installation details',
        () => run(() => edit('jobs', 'Job details', existing: current)),
      ),
      if (!locked) ...[
        tile(
            'EICR Wizard',
            () => run(() async {
                  final result = await editRecord(
                    context,
                    'EICR Wizard',
                    'jobs',
                    current,
                    skip: fields['jobs']!.keys.toSet().difference({
                      'reasonForReport',
                      'extentCovered',
                      'limitations',
                      'overallAssessment',
                    }),
                  );
                  if (result == null) return;
                  current.addAll(result);
                  await persist();
                })),
        tile('Standard Job Builder', () => run(buildStandardJob)),
        if (store.company.isNotEmpty)
          tile(
              'Apply saved company profile',
              () => run(() async {
                    for (final key in fields['company']!.keys) {
                      current[key] = value(store.company, key);
                    }
                    current['companyLogoData'] = store.company['logoData'];
                    await persist();
                  })),
      ],
      for (final name in sections.keys)
        tile(
          sections[name]!,
          () => run(() => open(job: current, table: name)),
          subtitle: name == 'supplyDetails'
              ? null
              : '${related(name).length} records',
        ),
      tile(
        'Validation',
        () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Validation'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (issues.isEmpty) const Text('No issues found.'),
                  for (final issue in issues)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('${issue.severity} · ${issue.message}'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              if (!locked &&
                  [
                    ...related('observations')
                        .map((row) => row['classification']),
                    ...related('inspectionItems').map((row) => row['result']),
                  ].any({'C1', 'C2', 'FI'}.contains) &&
                  current['overallAssessment'] != 'Unsatisfactory')
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    run(() async {
                      current['overallAssessment'] = 'Unsatisfactory';
                      await persist();
                    });
                  },
                  child: const Text('Apply Unsatisfactory assessment'),
                ),
            ],
          ),
        ),
        subtitle: '$critical critical issues',
      ),
      tile('Generate and preview PDF',
          () => run(() => openReport(current, generate: true))),
      if (!locked)
        ListTile(
          title: const Text('Sign and lock report'),
          subtitle: const Text(
            'Requires an engineer name and no critical issues',
          ),
          onTap: critical > 0 || value(current, 'engineerName').trim().isEmpty
              ? null
              : () => run(() async {
                    final signature = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (context) => const SignaturePage(),
                      ),
                    );
                    if (signature == null) return;
                    current.addAll({
                      'signatureData': signature,
                      'isLocked': true,
                      'status': 'Completed',
                      'signedAt': DateTime.now().millisecondsSinceEpoch / 1000 -
                          978307200,
                    });
                    await persist();
                  }),
        ),
      tile(
        'Duplicate as draft',
        () => run(() => duplicateJob(current)),
      ),
    ];
  }

  List<Widget> section() {
    final name = table!;
    final title = sections[name]!;
    final rows = related(name);
    if (name == 'supplyDetails') {
      return [
        tile(
          title,
          () => run(() => edit(name, title, existing: rows.firstOrNull)),
        ),
      ];
    }
    if (record != null) return recordDetails(name, record!);
    final isChecklist = name == 'inspectionItems';
    return [
      if (!locked && name == 'circuits')
        tile('Standard Job Builder', () => run(buildStandardJob)),
      if (!locked && name == 'circuits')
        tile(
            'Add circuit preset',
            () => run(() async {
                  final domestic = presets['Standard Domestic']!;
                  final options = {
                    'Lighting': domestic[0],
                    'Ring final sockets': domestic[2],
                    'Cooker': domestic[5],
                    'Shower': domestic[6],
                  };
                  final selected = await showDialog<String>(
                    context: context,
                    builder: (context) => SimpleDialog(
                        title: const Text('Circuit preset'),
                        children: [
                          for (final name in options.keys)
                            SimpleDialogOption(
                                onPressed: () => Navigator.pop(context, name),
                                child: Text(name)),
                        ]),
                  );
                  if (selected == null || !mounted) return;
                  final used =
                      rows.map((row) => value(row, 'circuitNumber')).toSet();
                  var number = 1;
                  while (used.contains('$number')) {
                    number++;
                  }
                  final result = await editRecord(
                      context, 'Add circuit preset', 'circuits', {
                    ...options[selected]!,
                    'id': newId(),
                    'jobId': job!['id'],
                    'descriptionText': selected,
                    'protectiveDeviceCurve': 'B',
                    'circuitNumber': '$number',
                    'distributionBoardReference': 'DB1',
                  });
                  if (result == null) return;
                  store.rows('circuits').add(result);
                  await persist();
                })),
      if (isChecklist && rows.isNotEmpty)
        ListTile(
          title: const Text('Checklist progress'),
          subtitle: Text(
              "${rows.where((row) => value(row, 'result').trim().isNotEmpty).length} of ${rows.length} completed"),
        ),
      if (isChecklist && rows.isNotEmpty && !locked)
        tile(
            'Mark all satisfactory',
            () => run(() async {
                  if (!await confirm(
                          'Set every checklist result to satisfactory?',
                          'Mark all') ||
                      !mounted) {
                    return;
                  }
                  for (final row in rows) {
                    row['result'] = '✓';
                  }
                  await persist();
                })),
      if (!locked && (!isChecklist || rows.isEmpty))
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(
            isChecklist
                ? 'Create default checklist'
                : 'Add ${switch (name) {
                    'circuits' => 'circuit',
                    'distributionBoards' => 'board',
                    _ => 'observation',
                  }}',
          ),
          onTap: () => run(() async {
            if (!isChecklist) {
              await edit(name, title);
              return;
            }
            if (related(name).isNotEmpty) return;
            store.rows(name).addAll(
                  checklist.map(
                    (item) => {
                      'id': newId(),
                      'jobId': job!['id'],
                      'section': item[0],
                      'itemNumber': item[1],
                      'itemText': item[2],
                      'result': '',
                    },
                  ),
                );
            await persist();
          }),
        ),
      for (final row in rows)
        tile(
          switch (name) {
            'circuits' => "Circuit ${value(row, 'circuitNumber')}",
            'distributionBoards' => value(row, 'reference'),
            'inspectionItems' =>
              "${value(row, 'itemNumber')} ${value(row, 'itemText')}",
            _ => "Observation ${value(row, 'observationNumber')}",
          },
          () => run(
            () => name == 'circuits' || name == 'observations'
                ? open(job: job, table: name, record: row)
                : edit(name, title, existing: row),
          ),
          trailing: locked || isChecklist
              ? null
              : deleteButton(
                  name,
                  row,
                  switch (name) {
                    'circuits' => 'circuit and test results',
                    'observations' => 'observation and photos',
                    _ => 'distribution board',
                  }),
          subtitle: value(
              row,
              switch (name) {
                'inspectionItems' => 'result',
                'distributionBoards' => 'location',
                _ => 'descriptionText',
              }),
        ),
    ];
  }

  List<Widget> recordDetails(String name, Record row) => [
        tile(
          'Details',
          () => run(() => edit(name, sections[name]!, existing: row)),
          subtitle: value(row, 'descriptionText'),
        ),
        if (name == 'circuits' && !locked)
          tile(
              'Duplicate circuit',
              () => run(() async {
                    final copy = {...row, 'id': newId(), 'circuitNumber': ''};
                    final result = await editRecord(
                        context, 'Duplicate circuit', name, copy);
                    if (result == null) return;
                    store.rows(name).add(result);
                    await persist();
                    if (mounted) Navigator.pop(context);
                  })),
        if (name == 'circuits')
          tile(
            'Test results',
            () => run(
              () => edit(
                'testResults',
                'Test results',
                existing: store
                    .related('testResults', row['id'], key: 'circuitId')
                    .firstOrNull,
              ),
            ),
            subtitle: referenceZs(row) == null
                ? null
                : 'Reference Zs ${referenceZs(row)} Ω',
          ),
        if (name == 'observations') ...[
          if (!locked) ...[
            tile(
                'Choose photo', () => run(() => addPhoto(ImageSource.gallery))),
            if (Platform.isIOS || Platform.isAndroid)
              tile('Take photo', () => run(() => addPhoto(ImageSource.camera))),
          ],
          for (final photo in related(
            'photos',
          ).where((photo) => photo['observationId'] == row['id']))
            Card(
              child: Column(
                children: [
                  Image.memory(
                    base64Decode(value(photo, 'imageData')),
                    height: 200,
                    errorBuilder: (context, error, stackTrace) =>
                        const Text('Image could not be displayed'),
                  ),
                  if (value(photo, 'caption').isNotEmpty)
                    Text(value(photo, 'caption')),
                  if (!locked)
                    Wrap(children: [
                      TextButton(
                          onPressed: () => run(() =>
                              addPhoto(ImageSource.gallery, existing: photo)),
                          child: const Text('Replace photo')),
                      deleteButton('photos', photo, 'photo'),
                    ]),
                ],
              ),
            ),
        ],
      ];

  Future<void> addPhoto(ImageSource source, {Record? existing}) async {
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    if (existing != null) {
      existing['imageData'] = base64Encode(await image.readAsBytes());
      await persist();
      return;
    }
    var caption = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add observation photo'),
        content: TextField(
          decoration: const InputDecoration(labelText: 'Caption'),
          onChanged: (text) => caption = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    store.rows('photos').add({
      'id': newId(),
      'jobId': job!['id'],
      'observationId': record!['id'],
      'caption': caption.trim(),
      'imageData': base64Encode(await image.readAsBytes()),
    });
    await persist();
  }
}
