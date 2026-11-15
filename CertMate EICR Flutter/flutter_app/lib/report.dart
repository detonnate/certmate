import 'dart:convert';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'labels.dart';
import 'schema.dart';
import 'store.dart';

Future<List<int>> makeReport(Store store, Record job) async {
  final document = pw.Document(title: value(job, 'reportNumber'));
  List<Record> related(String table) => store.related(table, job['id']);
  pw.Widget heading(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      );
  List<pw.Widget> details(
    String table,
    Record row, {
    Set<String> skip = const {},
  }) {
    return [
      for (final key in fields[table]!.keys)
        if (!skip.contains(key) && value(row, key).isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(
              '${label(key)}: ${pdfText(row[key])}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
    ];
  }

  final reportNumber = value(job, 'reportNumber');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 500,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '$reportNumber  |  ${context.pageNumber} / ${context.pagesCount}',
        ),
      ),
      build: (context) => [
        if (job['companyLogoData'] is String)
          pw.Image(
            pw.MemoryImage(base64Decode(job['companyLogoData'] as String)),
            height: 50,
          ),
        heading('Electrical Installation Condition Report'),
        ...details('jobs', job),
        heading('Supply details'),
        for (final row in related('supplyDetails'))
          ...details('supplyDetails', row),
        heading('Distribution boards'),
        for (final row in related('distributionBoards')) ...[
          heading('Board ${value(row, 'reference')}'),
          ...details('distributionBoards', row, skip: {'reference'}),
        ],
        heading('Inspection schedule'),
        for (final row in related('inspectionItems')) ...[
          pw.Text('${value(row, 'itemNumber')}  ${pdfText(row['itemText'])}'),
          ...details(
            'inspectionItems',
            row,
            skip: {'section', 'itemNumber', 'itemText'},
          ),
        ],
        heading('Circuit schedules and test results'),
        for (final row in related('circuits')) ...[
          heading('Circuit ${value(row, 'circuitNumber')}'),
          ...details('circuits', row, skip: {'circuitNumber'}),
          for (final result in store.related(
            'testResults',
            row['id'],
            key: 'circuitId',
          ))
            ...details('testResults', result),
        ],
        heading('Observations'),
        for (final row in related('observations')) ...[
          heading('Observation ${value(row, 'observationNumber')}'),
          ...details('observations', row, skip: {'observationNumber'}),
          for (final photo in related(
            'photos',
          ).where((photo) => photo['observationId'] == row['id'])) ...[
            pw.Image(
              pw.MemoryImage(base64Decode(photo['imageData'] as String)),
              height: 160,
            ),
            pw.Text(pdfText(photo['caption'])),
          ],
        ],
        heading('Declaration'),
        if (job['signatureData'] is String) ...[
          pw.Image(
            pw.MemoryImage(base64Decode(job['signatureData'] as String)),
            height: 60,
          ),
          pw.Text('Signed by ${value(job, 'engineerName')}'),
          if (job['signedAt'] is num)
            pw.Text(
              'Signed on ${DateTime.fromMillisecondsSinceEpoch((((job['signedAt'] as num) + 978307200) * 1000).round(), isUtc: true).toLocal().toIso8601String().split('T').first}',
            ),
        ] else
          pw.Text('Unsigned'),
      ],
    ),
  );
  return document.save();
}

String pdfText(Object? value) => switch (value) {
      true => 'Yes',
      false => 'No',
      '✓' => 'Satisfactory',
      null => '',
      _ => value
          .toString()
          .replaceAll('Δ', 'delta ')
          .replaceAll('Ω', 'ohm')
          .replaceAll('–', '-')
          .replaceAll('’', "'"),
    };
