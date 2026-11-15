import 'dart:convert';
import 'dart:ui' as ui;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'labels.dart';
import 'schema.dart';
import 'store.dart';

Future<Record?> editRecord(
  BuildContext context,
  String title,
  String table,
  Record initial, {
  Set<String> skip = const {},
  Map<String, List<String>> options = const {},
  bool locked = false,
}) =>
    Navigator.of(context).push<Record>(
      MaterialPageRoute(
        builder: (context) => RecordEditor(
          title: title,
          table: table,
          initial: initial,
          skip: skip,
          options: options,
          locked: locked,
        ),
      ),
    );

class RecordEditor extends StatefulWidget {
  const RecordEditor({
    super.key,
    required this.title,
    required this.table,
    required this.initial,
    required this.skip,
    required this.options,
    required this.locked,
  });

  final String title;
  final String table;
  final Record initial;
  final Set<String> skip;
  final Map<String, List<String>> options;
  final bool locked;

  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  late final Record draft = {...widget.initial};
  final form = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (!widget.locked)
            TextButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                form.currentState!.save();
                Navigator.pop(context, draft);
              },
              child: const Text('Save'),
            ),
        ],
      ),
      body: Form(
        key: form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final entry in fields[widget.table]!.entries)
                if (!widget.skip.contains(entry.key))
                  field(entry.key, entry.value),
            ],
          ),
        ),
      ),
    );
  }

  Widget field(String key, String type) {
    final options = widget.options[key] ?? choices[key];
    final current = value(draft, key);
    if (type == 'Bool') {
      return SwitchListTile(
        title: Text(label(key)),
        value: draft[key] == true,
        onChanged: widget.locked
            ? null
            : (checked) => setState(() => draft[key] = checked),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: options != null
          ? DropdownButtonFormField<String>(
              initialValue: current,
              isExpanded: true,
              decoration: InputDecoration(labelText: label(key)),
              items: [
                for (final option in {'', ...options, current})
                  DropdownMenuItem(
                    value: option,
                    child: Text(option.isEmpty ? 'Select' : option),
                  ),
              ],
              onChanged: widget.locked ? null : (_) {},
              onSaved: (option) => draft[key] = option ?? '',
            )
          : TextFormField(
              initialValue: current,
              readOnly: widget.locked,
              decoration: InputDecoration(labelText: label(key)),
              minLines: 1,
              maxLines: 4,
              keyboardType: type == 'Int'
                  ? TextInputType.number
                  : TextInputType.multiline,
              validator: (input) =>
                  type == 'Int' && int.tryParse(input ?? '') == null
                      ? 'Enter a whole number'
                      : null,
              onSaved: (input) => draft[key] =
                  type == 'Int' ? int.parse(input!) : input!.trim(),
            ),
    );
  }
}

class SignaturePage extends StatefulWidget {
  const SignaturePage({super.key});

  @override
  State<SignaturePage> createState() => _SignaturePageState();
}

class _SignaturePageState extends State<SignaturePage> {
  final strokes = <List<Offset>>[];
  Size size = Size.zero;

  Future<void> save() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    SignaturePainter(strokes).paint(canvas, size);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (mounted && bytes != null) {
          Navigator.pop(context, base64Encode(bytes.buffer.asUint8List()));
        }
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Engineer signature'),
          actions: [
            TextButton(
              onPressed: () => setState(strokes.clear),
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: strokes.isEmpty ? null : save,
              child: const Text('Sign'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              size = Size(
                constraints.maxWidth,
                constraints.maxHeight.clamp(0, 300).toDouble(),
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (event) =>
                    setState(() => strokes.add([event.localPosition])),
                onPanUpdate: (event) =>
                    setState(() => strokes.last.add(event.localPosition)),
                child:
                    CustomPaint(size: size, painter: SignaturePainter(strokes)),
              );
            },
          ),
        ),
      );
}

class SignaturePainter extends CustomPainter {
  SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(Colors.white, BlendMode.src);
    final pen = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final stroke in strokes) {
      canvas.drawCircle(stroke.first, 1.5, pen);
      for (var i = 1; i < stroke.length; i++) {
        canvas.drawLine(stroke[i - 1], stroke[i], pen);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}
