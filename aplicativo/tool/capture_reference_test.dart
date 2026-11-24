import 'dart:io';
import 'dart:ui' as ui;

import 'package:atleta/app.dart';
import 'package:atleta/core/controller.dart';
import 'package:atleta/data/repository.dart';
import 'package:atleta/ui/reference_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (scene, file) in [
    ('today', 'today.png'),
    ('load', 'training-load-ratio.png'),
  ]) {
    testWidgets('capture $scene at 390 × 844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 53);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      late AtletaController store;
      await tester.runAsync(() async {
        for (final (family, path) in [
          ('Inter', 'assets/fonts/Inter.ttf'),
          ('IBM Plex Mono', 'assets/fonts/IBMPlexMono-SemiBold.ttf'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
          (
            'packages/cupertino_icons/CupertinoIcons',
            'packages/cupertino_icons/assets/CupertinoIcons.ttf',
          ),
        ]) {
          await (FontLoader(family)..addFont(rootBundle.load(path))).load();
        }
        final db = await newDatabaseFactoryMemory().openDatabase('capture');
        store = AtletaController(AtletaRepository(db), demo: true);
        await store.initialize();
      });

      const key = ValueKey('capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: AtletaApp(
            load: () async => store,
            scene: scene,
            capture: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold));
      await tester.runAsync(() async {
        final assets = [
          if (scene == 'today') 'assets/demo-avatar.png',
          for (final symbol in ReferenceSymbol.values) symbol.assetName,
        ];
        final loaded = Future.wait([
          for (final path in assets) precacheImage(AssetImage(path), context),
        ]);
        await tester.pump();
        await loaded;
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = Directory('docs/screenshots');
          await output.create(recursive: true);
          await File(
            '${output.path}/$file',
          ).writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    });
  }
}
