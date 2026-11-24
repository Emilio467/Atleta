import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sembast/sembast_memory.dart';

import 'app.dart';
import 'core/controller.dart';
import 'data/open_database.dart';
import 'data/repository.dart';

const _demo = bool.fromEnvironment('ATLETA_DEMO');
const _scene = String.fromEnvironment('ATLETA_SCREEN');
const _capture = bool.fromEnvironment('ATLETA_CAPTURE');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  if (!_demo) {
    runApp(const AtletaApp.local(openDatabase: openAtletaDatabase));
    return;
  }
  final params = Uri.base.queryParameters;
  final scene = kIsWeb ? params['screen'] ?? _scene : _scene;
  final capture = _capture || (kIsWeb && params['capture'] == '1');
  runApp(
    AtletaApp(
      load: () async {
        final db = await newDatabaseFactoryMemory().openDatabase('demo');
        final store = AtletaController(AtletaRepository(db), demo: true);
        try {
          await store.initialize();
          return store;
        } catch (_) {
          await db.close();
          store.dispose();
          rethrow;
        }
      },
      scene: scene,
      capture: capture,
    ),
  );
}
