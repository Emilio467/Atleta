import 'dart:io';

import 'package:atleta/core/controller.dart';
import 'package:atleta/core/models.dart';
import 'package:atleta/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

import 'metrics_test.dart' show workout;

void main() {
  test(
    'reopen local database, preserve records, profile, readiness and exercise timer',
    () async {
      final directory = await Directory.systemTemp.createTemp('atleta-test-');
      addTearDown(() async => directory.delete(recursive: true));
      final path = '${directory.path}/test.db';
      final day = DateTime(2025, 12, 19, 12);
      var db = await databaseFactoryIo.openDatabase(path);
      var repo = AtletaRepository(db);
      await repo.putWorkout(workout(day));
      await expectLater(
        repo.putWorkout(workout(day, id: 'duplicate')),
        throwsA(isA<DuplicateRecord>()),
      );
      await repo.putReadiness(ReadinessEntry(day, 72, day));
      await repo.putProfile(const AthleteProfile(name: 'Ana'));
      await repo.putRest(DateTime(2025, 12, 18), true);
      final session = Session(
        id: 's',
        started: day,
        activity: 'Walking',
        activeSince: day,
      );
      await repo.beginSession(session);
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      repo = AtletaRepository(db);
      final saved = await repo.read();
      expect(saved.workouts.single.start.toLocal(), day);
      expect(saved.readiness.single.score, 72);
      expect(saved.profile.name, 'Ana');
      expect(saved.rest, {'2025-12-18'});
      expect(
        saved.session!.elapsed(day.add(const Duration(hours: 1))).inHours,
        1,
      );
      final finalWorkout = workout(day, id: 's');
      await Future.wait([
        repo.finishSession(finalWorkout),
        repo.finishSession(finalWorkout),
      ]);
      expect((await repo.read()).session, isNull);
      expect(
        (await repo.read()).workouts.where((w) => w.id == 's'),
        hasLength(1),
      );
      await db.close();
    },
  );

  test(
    'imports are disabled by default, idempotent and preserve local effort',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test-import');
      addTearDown(db.close);
      final repo = AtletaRepository(db);
      final day = DateTime(2025, 12, 19);
      final imported = Workout(
        id: 'hk:one',
        activity: 'Running',
        start: day,
        seconds: 2400,
        origin: Origin.healthKit,
        source: 'Watch',
        created: day,
        updated: day,
      );
      final batch = HealthImport([imported]);
      await repo.saveImport(batch, day);
      expect((await repo.read()).workouts, isEmpty);
      await repo.setSyncEnabled(true);
      await repo.saveImport(batch, day);
      await repo.setImportedEffort(imported.id, 7, day);
      await repo.saveImport(batch, day.add(const Duration(hours: 1)));
      final data = await repo.read();
      expect(data.workouts.single.effort, 7);
      expect(data.lastSync!.toLocal(), day.add(const Duration(hours: 1)));
    },
  );

  test('reference records stay in the demo database', () async {
    final factory = newDatabaseFactoryMemory();
    final real = AtletaController(
      AtletaRepository(await factory.openDatabase('real')),
    );
    final sample = AtletaController(
      AtletaRepository(await factory.openDatabase('demo')),
      demo: true,
    );
    await real.initialize();
    await sample.initialize();
    expect(real.data.workouts, isEmpty);
    expect(real.data.readiness, isEmpty);
    expect(real.ratios, isEmpty);
    expect(sample.data.workouts.single.origin, Origin.demo);
    expect(sample.readinessOn(sample.today)?.score, 73);
    for (final controller in [real, sample]) {
      controller.dispose();
      await controller.repository.db.close();
    }
  });
}
