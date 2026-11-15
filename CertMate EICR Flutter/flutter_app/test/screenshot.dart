import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpScreenshotApp(WidgetTester tester, Widget home) async {
  const output = String.fromEnvironment('CERTMATE_SCREENSHOTS');
  const fonts = String.fromEnvironment('CERTMATE_SCREENSHOT_FONTS');
  if (output.isNotEmpty) {
    final loaded = await tester.runAsync(() async {
      final loader = FontLoader('ScreenshotRoboto');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        loader.addFont(File('$fonts/Roboto-$weight.ttf')
            .readAsBytes()
            .then(ByteData.sublistView));
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(File('$fonts/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then(ByteData.sublistView));
      await Future.wait([loader.load(), icons.load()]);
      return true;
    });
    expect(loaded, isTrue, reason: 'Screenshot fonts could not be loaded');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 892);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(RepaintBoundary(
    key: const ValueKey('test-screenshot'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff00695c),
        fontFamily: output.isEmpty ? null : 'ScreenshotRoboto',
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  const output = String.fromEnvironment('CERTMATE_SCREENSHOTS');
  if (output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('test-screenshot')),
  );
  final saved = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(png!.buffer.asUint8List());
      return true;
    } finally {
      image.dispose();
    }
  });
  expect(saved, isTrue, reason: 'Screenshot capture failed for $name');
}
