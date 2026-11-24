import 'dart:io';
import 'dart:typed_data';

import 'package:atleta/core/m5.dart';
import 'package:atleta/core/metrics.dart';
import 'package:atleta/core/models.dart';
import 'package:atleta/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;

Workout _workout(DateTime now, String id, {Origin origin = Origin.manual}) =>
    Workout(
      id: id,
      activity: 'Walking',
      start: now,
      seconds: 90,
      effort: 4,
      origin: origin,
      created: now,
      updated: now,
    );

void main() {
  test(
    'clearing workout history is profile scoped and old imports stay cleared',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('clear-history');
      addTearDown(db.close);
      final profiles = LocalProfilesRepository(db);
      final first = await profiles.trainingFor(
        await profiles.create(const AthleteProfile(name: 'First')),
      );
      final second = await profiles.trainingFor(
        await profiles.create(const AthleteProfile(name: 'Second')),
      );
      final day = DateTime(2026, 11, 16, 12);
      final old = _workout(day, 'old', origin: Origin.healthConnect);
      await first.setSyncEnabled(true);
      await first.saveImport(HealthImport([old]), day);
      await first.putWorkout(_workout(day, 'local'));
      await second.putWorkout(_workout(day, 'other-profile'));
      await first.putReadiness(ReadinessEntry(day, 75, day));

      final cleared = day.add(const Duration(days: 1));
      await first.clearWorkoutHistory(cleared);
      expect((await first.read()).workouts, isEmpty);
      expect((await first.read()).readiness, hasLength(1));
      expect((await second.read()).workouts.single.id, 'other-profile');

      await first.setSyncEnabled(false);
      await first.setSyncEnabled(true);
      final later = cleared.add(const Duration(minutes: 1));
      final fresh = _workout(later, 'fresh', origin: Origin.healthConnect);
      await first.saveImport(HealthImport([old, fresh]), later);
      expect((await first.read()).workouts.single.id, 'fresh');
    },
  );

  test(
    'legacy profile migrates in place and new profiles stay separate after restart',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'atleta-profiles-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final path = '${temporary.path}/profiles.db';
      final now = DateTime(2026, 11, 16, 19);
      var db = await databaseFactoryIo.openDatabase(path);
      final old = AtletaRepository(db);
      await old.putProfile(const AthleteProfile(name: 'Ana'));
      await old.putWorkout(_workout(now, 'legacy-walk'));
      await old.putReadiness(ReadinessEntry(now, 76, now));
      await old.beginSession(
        Session(
          id: 'ongoing',
          started: now,
          activity: 'Running',
          activeSince: now,
        ),
      );
      await old.setSyncEnabled(true);
      await db.close();

      db = await databaseFactoryIo.openDatabase(path);
      var directory = LocalProfilesRepository(db);
      await directory.initialize();
      final migrated = (await directory.list()).single;
      expect(migrated.profile.name, 'Ana');
      final alice = await directory.trainingFor(migrated.id);
      expect((await alice.read()).session!.id, 'ongoing');
      expect((await alice.read()).workouts.single.id, 'legacy-walk');
      expect((await alice.read()).readiness.single.score, 76);
      await alice.putProfile(
        const AthleteProfile(
          name: 'Ana',
          heightCm: 172.5,
          weightKg: 68.4,
          birthYear: 1997,
        ),
      );

      final secondId = await directory.create(
        const AthleteProfile(name: 'Beatriz', stepLengthCm: 67),
      );
      final beatriz = await directory.trainingFor(secondId);
      expect((await beatriz.read()).workouts, isEmpty);
      expect((await beatriz.read()).readiness, isEmpty);
      expect((await beatriz.read()).session, isNull);
      await expectLater(
        beatriz.setSyncEnabled(true),
        throwsA(isA<HealthAlreadyLinked>()),
      );
      await expectLater(
        directory.create(const AthleteProfile(name: ' ana ')),
        throwsA(isA<ProfileNameInUse>()),
      );
      await beatriz.putWorkout(_workout(now, 'beatriz-walk'));
      await db.close();

      db = await databaseFactoryIo.openDatabase(path);
      directory = LocalProfilesRepository(db);
      await directory.initialize();
      final profiles = await directory.list();
      expect(profiles.map((e) => e.profile.name), ['Ana', 'Beatriz']);
      expect(profiles.first.profile.heightCm, 172.5);
      expect(profiles.first.profile.weightKg, 68.4);
      expect(profiles.last.profile.stepLengthCm, 67);
      final reopened = await directory.trainingFor(secondId);
      expect((await reopened.read()).workouts.single.id, 'beatriz-walk');
      await db.close();
    },
  );

  test(
    'M5 binary protocol handles legacy packets, v2 commands and missing sensors',
    () {
      final old = ByteData(16)
        ..setUint8(0, 1)
        ..setUint8(1, 2)
        ..setUint32(2, 1234, Endian.little)
        ..setUint32(6, 95, Endian.little)
        ..setUint16(10, 3950, Endian.little)
        ..setUint8(12, 77);
      final first = WatchReading.decode(old.buffer.asUint8List())!;
      expect(first.steps, 1234);
      expect(first.activeSeconds, 95);
      expect(first.batteryPercent, 77);
      expect(first.token, 0);
      expect(first.running, isFalse);
      expect(
        first.totals(const AthleteProfile(stepLengthCm: 70)).distanceKm,
        closeTo(.8638, .0001),
      );
      expect(first.totals(const AthleteProfile()).distanceKm, isNull);
      expect(WatchReading.decode(Uint8List(2)), isNull);

      const token = 0x91B2C3D4;
      final next = ByteData(18)
        ..setUint8(0, 2)
        ..setUint8(1, 16)
        ..setUint8(12, 255)
        ..setUint16(10, 65535, Endian.little)
        ..setUint32(13, token, Endian.little);
      final result = WatchReading.decode(next.buffer.asUint8List())!;
      expect(result.steps, isNull);
      expect(result.batteryPercent, isNull);
      expect(WatchAction.finish.confirmedBy(result, token), isTrue);
      expect(WatchAction.pause.confirmedBy(result, token), isFalse);
      expect(WatchAction.finish.confirmedBy(result, token - 1), isFalse);
      expect(WatchAction.start.encode(token), [1, 0xD4, 0xC3, 0xB2, 0x91]);
    },
  );

  test(
    'linked watch and draft are profile scoped, and completed workouts feed load once',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('watch');
      addTearDown(db.close);
      final directory = LocalProfilesRepository(db);
      await directory.initialize();
      final first = await directory.trainingFor(
        await directory.create(
          const AthleteProfile(name: 'A', stepLengthCm: 68),
        ),
      );
      final second = await directory.trainingFor(
        await directory.create(const AthleteProfile(name: 'B')),
      );
      const watch = WatchLink('watch-one', 'Atleta-M5');
      await first.putWatchLink(watch);
      await expectLater(
        second.putWatchLink(watch),
        throwsA(isA<WatchAlreadyLinked>()),
      );
      final day = DateTime(2026, 11, 16, 19);
      final draft = WatchDraft(
        id: 'm5-workout',
        token: 65,
        deviceId: watch.deviceId,
        activity: 'Walking',
        started: day,
      );
      await first.beginWatchDraft(draft);
      await first.markWatchStart(draft.id, day.add(const Duration(minutes: 2)));
      await first.markWatchStart(draft.id, day.add(const Duration(minutes: 3)));
      expect(
        (await first.read()).watchDraft!.started.toLocal(),
        day.add(const Duration(minutes: 2)),
      );
      await expectLater(
        first.putWatchLink(null),
        throwsA(isA<WorkoutInProgress>()),
      );
      expect((await second.read()).watchDraft, isNull);
      const result = WatchReading(
        activeSeconds: 130,
        steps: 144,
        token: 65,
        running: false,
        finished: true,
      );
      await first.finishWatchDraft(draft.id, result);

      final saved = Workout(
        id: draft.id,
        activity: draft.activity,
        start: day,
        seconds: result.activeSeconds,
        effort: 4,
        origin: Origin.m5,
        source: watch.name,
        created: day,
        updated: day,
        watchStats: result.totals((await first.read()).profile),
      );
      await Future.wait([
        first.saveWatchWorkout(saved, draftId: draft.id),
        first.saveWatchWorkout(saved, draftId: draft.id),
      ]);
      final firstData = await first.read();
      expect(firstData.workouts.single.watchStats!.steps, 144);
      expect(firstData.watchDraft, isNull);
      expect((await second.read()).workouts, isEmpty);
      final rest = {for (var i = 1; i < 28; i++) dayKey(offsetDay(day, -i))};
      expect(LoadHistory(firstData.workouts, rest).ratios[dayOf(day)], 4);
    },
  );
}
