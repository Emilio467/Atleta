import 'package:sembast/sembast.dart';

import '../core/m5.dart';
import '../core/models.dart';

final _profiles = stringMapStoreFactory.store('athlete-profiles');
final _directory = stringMapStoreFactory.store('profile-directory');
final _healthOwner = _directory.record('health-owner');
final _watchOwners = stringMapStoreFactory.store('watch-owners');
const _legacyProfileId = 'legacy';

typedef LocalProfile = ({String id, AthleteProfile profile});

Future<void> _saveProfile(
  Transaction txn,
  String id,
  AthleteProfile profile,
) async {
  final name = profile.name.trim().toLowerCase();
  final others = await _profiles.find(
    txn,
    finder: Finder(filter: Filter.notEquals(Field.key, id)),
  );
  if (others.any(
    (p) => (p.value['name'] as String?)?.trim().toLowerCase() == name,
  )) {
    throw const ProfileNameInUse();
  }
  await _profiles.record(id).put(txn, profile.toRow());
}

class LocalProfilesRepository {
  LocalProfilesRepository(this.db);
  final Database db;

  Future<void> initialize() => db.transaction((txn) async {
    final migration = _directory.record('legacy-profile-v1');
    if (await migration.get(txn) != null) return;

    final old = AtletaRepository(db);
    final profile = await old._profile.get(txn);
    final sync = await old._sync.get(txn);
    final hasHistory =
        profile != null ||
        sync != null ||
        await old._session.get(txn) != null ||
        await old._workouts.count(txn) > 0 ||
        await old._store('heart').count(txn) > 0 ||
        await old._store('sleep').count(txn) > 0 ||
        await old._readiness.count(txn) > 0 ||
        await old._rest.count(txn) > 0;

    if (hasHistory) {
      // Preserve the original data stores. Only the profile card moves.
      await _profiles
          .record(_legacyProfileId)
          .put(txn, profile ?? const AthleteProfile().toRow());
      if (sync?['enabled'] == true) {
        await _healthOwner.put(txn, {'id': _legacyProfileId});
      }
    }
    await migration.put(txn, {});
  });

  Future<List<LocalProfile>> list() async => [
    for (final record in await _profiles.find(
      db,
      finder: Finder(sortOrders: [SortOrder('name'), SortOrder(Field.key)]),
    ))
      (id: record.key, profile: AthleteProfile.fromRow(record.value)),
  ];

  Future<String> create(AthleteProfile profile) async {
    final id = newId();
    await db.transaction((txn) => _saveProfile(txn, id, profile));
    return id;
  }

  Future<AtletaRepository> trainingFor(String id) async {
    if (await _profiles.record(id).get(db) == null) {
      throw const MissingProfile();
    }
    return AtletaRepository(db, profileId: id);
  }
}

class TrainingData {
  const TrainingData({
    this.workouts = const [],
    this.readiness = const [],
    this.rest = const {},
    this.profile = const AthleteProfile(),
    this.session,
    this.syncEnabled = false,
    this.lastSync,
    this.watchLink,
    this.watchDraft,
  });
  final List<Workout> workouts;
  final List<ReadinessEntry> readiness;
  final Set<String> rest;
  final AthleteProfile profile;
  final Session? session;
  final bool syncEnabled;
  final DateTime? lastSync;
  final WatchLink? watchLink;
  final WatchDraft? watchDraft;
}

class HealthImport {
  const HealthImport(this.workouts);
  final List<Workout> workouts;
  int get count => workouts.length;
}

class AtletaRepository {
  AtletaRepository(this.db, {this.profileId});
  final Database db;
  final String? profileId;

  StoreRef<String, RowData> _store(String name) => stringMapStoreFactory.store(
    profileId == null || profileId == _legacyProfileId
        ? name
        : 'profile/$profileId/$name',
  );

  late final _workouts = _store('workouts');
  late final _readiness = _store('readiness');
  late final _rest = _store('rest');
  late final _settings = _store('settings');
  late final _session = _settings.record('session');
  late final _sync = _settings.record('native-sync');
  late final _workoutHistoryCleared = _settings.record(
    'workout-history-cleared',
  );
  late final _watchLink = _settings.record('watch-link');
  late final _watchDraft = _settings.record('watch-draft');
  late final _profile = profileId == null
      ? _settings.record('profile')
      : _profiles.record(profileId!);

  Future<TrainingData> read() => db.transaction((txn) async {
    final profile = await _profile.get(txn);
    final active = await _session.get(txn);
    final sync = await _sync.get(txn);
    final watchLink = await _watchLink.get(txn);
    final watchDraft = await _watchDraft.get(txn);
    return TrainingData(
      workouts: [
        for (final x in await _workouts.find(
          txn,
          finder: Finder(sortOrders: [SortOrder('start', false)]),
        ))
          Workout.fromRow(x.key, x.value),
      ],
      readiness: [
        for (final x in await _readiness.find(
          txn,
          finder: Finder(sortOrders: [SortOrder(Field.key, false)]),
        ))
          ReadinessEntry.fromRow(x.key, x.value),
      ],
      rest: (await _rest.findKeys(txn)).toSet(),
      profile: profile == null
          ? const AthleteProfile()
          : AthleteProfile.fromRow(profile),
      session: active == null
          ? null
          : Session.fromRow(active['id'] as String, active),
      syncEnabled: sync?['enabled'] as bool? ?? false,
      lastSync: sync?['lastSync'] == null ? null : stamp(sync!, 'lastSync'),
      watchLink: watchLink == null ? null : WatchLink.fromRow(watchLink),
      watchDraft: watchDraft == null ? null : WatchDraft.fromRow(watchDraft),
    );
  });

  Future<void> putWorkout(Workout workout) => db.transaction((txn) async {
    final duplicate = await _workouts.findFirst(
      txn,
      finder: Finder(
        filter: Filter.and([
          Filter.notEquals(Field.key, workout.id),
          Filter.equals('start', clockStamp(workout.start)),
          Filter.equals('seconds', workout.seconds),
          Filter.equals('activity', workout.activity),
          Filter.equals('origin', workout.origin.name),
        ]),
      ),
    );
    if (duplicate != null) throw const DuplicateRecord();
    await _workouts.record(workout.id).put(txn, workout.toRow());
    await _rest.record(dayKey(workout.start)).delete(txn);
  });
  Future<void> setImportedEffort(String id, int effort, DateTime now) =>
      db.transaction((txn) async {
        final record = _workouts.record(id);
        final stored = await record.get(txn);
        if (stored == null) return;
        final workout = Workout.fromRow(id, stored);
        if (!workout.origin.imported) return;
        await record.put(txn, workout.withEffort(effort, now).toRow());
      });

  Future<void> deleteWorkout(String id) => db.transaction((txn) async {
    final record = _workouts.record(id);
    final stored = await record.get(txn);
    if (stored == null) return;
    final origin = Origin.values.byName(stored['origin'] as String);
    if (!origin.imported && origin != Origin.demo) await record.delete(txn);
  });
  Future<void> clearWorkoutHistory(DateTime now) => db.transaction((txn) async {
    await _workouts.delete(txn);
    await _workoutHistoryCleared.put(txn, {'at': clockStamp(now)});
  });
  Future<void> putReadiness(ReadinessEntry entry) async =>
      _readiness.record(dayKey(entry.day)).put(db, entry.toRow());
  Future<void> putProfile(AthleteProfile profile) async {
    final id = profileId;
    if (id == null) {
      await _profile.put(db, profile.toRow());
    } else {
      await db.transaction((txn) => _saveProfile(txn, id, profile));
    }
  }

  Future<void> putRest(DateTime day, bool confirm) =>
      db.transaction((txn) async {
        final record = _rest.record(dayKey(day));
        if (!confirm) {
          await record.delete(txn);
          return;
        }
        final hasWorkout = (await _workouts.find(
          txn,
        )).any((row) => dayKey(stamp(row.value, 'start')) == dayKey(day));
        if (hasWorkout) throw const DuplicateRecord();
        await record.put(txn, {});
      });
  Future<void> beginSession(Session session) => db.transaction((txn) async {
    if (await _watchDraft.get(txn) != null) throw const WorkoutInProgress();
    if (await _session.get(txn) != null) return;
    await _session.put(txn, {'id': session.id, ...session.toRow()});
  });
  Future<void> updateSession(Session session) => db.transaction((txn) async {
    final current = await _session.get(txn);
    if (current?['id'] != session.id) return;
    await _session.put(txn, {'id': session.id, ...session.toRow()});
  });
  Future<void> finishSession(Workout workout) => db.transaction((txn) async {
    final active = await _session.get(txn);
    if (active?['id'] != workout.id) return;
    await _workouts.record(workout.id).put(txn, workout.toRow());
    await _rest.record(dayKey(workout.start)).delete(txn);
    await _session.delete(txn);
  });

  Future<void> putWatchLink(WatchLink? link) => db.transaction((txn) async {
    final old = (await _watchLink.get(txn))?['deviceId'] as String?;
    final id = profileId;
    if (old != link?.deviceId && await _watchDraft.get(txn) != null) {
      throw const WorkoutInProgress();
    }
    if (link != null && id != null) {
      final target = _watchOwners.record(link.deviceId);
      final owner = (await target.get(txn))?['profileId'];
      if (owner != null && owner != id) throw const WatchAlreadyLinked();
      await target.put(txn, {'profileId': id});
    }
    if (old != null && old != link?.deviceId && id != null) {
      final former = _watchOwners.record(old);
      if ((await former.get(txn))?['profileId'] == id) await former.delete(txn);
    }
    if (link == null) {
      await _watchLink.delete(txn);
    } else {
      await _watchLink.put(txn, link.toRow());
    }
  });

  Future<void> beginWatchDraft(WatchDraft draft) => db.transaction((txn) async {
    if (await _session.get(txn) != null || await _watchDraft.get(txn) != null) {
      throw const WorkoutInProgress();
    }
    if ((await _watchLink.get(txn))?['deviceId'] != draft.deviceId) {
      throw const WatchSessionMismatch();
    }
    await _watchDraft.put(txn, draft.toRow());
  });

  Future<void> markWatchStart(String id, DateTime now) => db.transaction((
    txn,
  ) async {
    final draft = await _watchDraft.get(txn);
    if (draft == null || draft['id'] != id) throw const WatchSessionMismatch();
    if (draft['startSent'] == true) return;
    await _watchDraft.put(txn, {
      'started': clockStamp(now),
      'startSent': true,
    }, merge: true);
  });

  Future<void> finishWatchDraft(String id, WatchReading reading) =>
      db.transaction((txn) async {
        final draft = await _watchDraft.get(txn);
        if (draft?['id'] != id ||
            draft?['token'] != reading.token ||
            !reading.finished) {
          throw const WatchSessionMismatch();
        }
        await _watchDraft.put(txn, {'result': reading.toRow()}, merge: true);
      });

  Future<void> discardWatchDraft(String id) => db.transaction((txn) async {
    if ((await _watchDraft.get(txn))?['id'] == id) {
      await _watchDraft.delete(txn);
    }
  });

  Future<void> saveWatchWorkout(Workout workout, {String? draftId}) =>
      db.transaction((txn) async {
        final target = _workouts.record(workout.id);
        if (await target.get(txn) != null) {
          if (draftId == null) throw const DuplicateRecord();
          return;
        }
        if (draftId != null) {
          final draft = await _watchDraft.get(txn);
          if (draft == null ||
              draft['id'] != draftId ||
              draft['result'] == null) {
            throw const WatchSessionMismatch();
          }
          await _watchDraft.delete(txn);
        }
        await target.put(txn, workout.toRow());
        await _rest.record(dayKey(workout.start)).delete(txn);
      });

  Future<bool> healthLinkedElsewhere() async {
    if (profileId == null) return false;
    final owner = (await _healthOwner.get(db))?['id'];
    return owner != null && owner != profileId;
  }

  Future<void> setSyncEnabled(bool enabled) => db.transaction((txn) async {
    final id = profileId;
    if (id != null) {
      final owner = (await _healthOwner.get(txn))?['id'];
      if (enabled) {
        if (owner != null && owner != id) throw const HealthAlreadyLinked();
        await _healthOwner.put(txn, {'id': id});
      } else if (owner == id) {
        await _healthOwner.delete(txn);
      }
    }
    await _sync.put(txn, {'enabled': enabled}, merge: true);
  });

  Future<void> saveImport(HealthImport batch, DateTime now) =>
      db.transaction((txn) async {
        if ((await _sync.get(txn))?['enabled'] != true) return;
        if (profileId != null &&
            (await _healthOwner.get(txn))?['id'] != profileId) {
          return;
        }
        final cleared = await _workoutHistoryCleared.get(txn);
        final clearedAt = cleared == null ? null : stamp(cleared, 'at');
        for (final workout in batch.workouts) {
          if (clearedAt != null && !workout.start.isAfter(clearedAt)) continue;
          final target = _workouts.record(workout.id);
          final previous = await target.get(txn);
          final next = workout.toRow();
          if (previous != null) {
            if (previous['activity'] == next['activity'] &&
                previous['start'] == next['start'] &&
                previous['seconds'] == next['seconds'] &&
                previous['source'] == next['source']) {
              continue;
            }
            next['effort'] = previous['effort'];
            next['created'] = previous['created'];
          }
          await target.put(txn, next);
          await _rest.record(dayKey(workout.start)).delete(txn);
        }
        await _sync.put(txn, {'lastSync': clockStamp(now)}, merge: true);
      });
}

class DuplicateRecord implements Exception {
  const DuplicateRecord();
}

class MissingProfile implements Exception {
  const MissingProfile();
}

class ProfileNameInUse implements Exception {
  const ProfileNameInUse();
}

class HealthAlreadyLinked implements Exception {
  const HealthAlreadyLinked();
}

class WatchAlreadyLinked implements Exception {
  const WatchAlreadyLinked();
}

class WorkoutInProgress implements Exception {
  const WorkoutInProgress();
}

class WatchSessionMismatch implements Exception {
  const WatchSessionMismatch();
}
