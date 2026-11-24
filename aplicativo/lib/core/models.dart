import 'dart:math';

typedef RowData = Map<String, Object?>;

enum Origin {
  manual,
  timer,
  healthKit,
  healthConnect,
  demo,
  m5;

  bool get imported => this == healthKit || this == healthConnect;
}

DateTime dayOf(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime offsetDay(DateTime date, int offset) =>
    DateTime(date.year, date.month, date.day + offset);
String dayKey(DateTime date) => dayOf(date).toIso8601String().substring(0, 10);
DateTime stamp(RowData row, String key) =>
    DateTime.fromMillisecondsSinceEpoch(row[key] as int, isUtc: true);
int clockStamp(DateTime time) => time.millisecondsSinceEpoch;
String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class Workout {
  const Workout({
    required this.id,
    required this.activity,
    required this.start,
    required this.seconds,
    required this.origin,
    required this.created,
    required this.updated,
    this.effort,
    this.notes = '',
    this.source = '',
    this.watchStats,
  });
  final String id, activity, notes, source;
  final DateTime start, created, updated;
  final int seconds;
  final int? effort;
  final Origin origin;
  final WatchStats? watchStats;

  factory Workout.fromRow(String id, RowData row) => Workout(
    id: id,
    activity: row['activity'] as String,
    start: stamp(row, 'start'),
    seconds: row['seconds'] as int,
    origin: Origin.values.byName(row['origin'] as String),
    created: stamp(row, 'created'),
    updated: stamp(row, 'updated'),
    effort: row['effort'] as int?,
    notes: row['notes'] as String? ?? '',
    source: row['source'] as String? ?? '',
    watchStats: row['watchStats'] is Map
        ? WatchStats.fromRow(
            Map<String, Object?>.from(row['watchStats'] as Map),
          )
        : null,
  );
  RowData toRow() => {
    'activity': activity,
    'start': clockStamp(start),
    'seconds': seconds,
    'effort': effort,
    'notes': notes,
    'origin': origin.name,
    'source': source,
    'created': clockStamp(created),
    'updated': clockStamp(updated),
    if (watchStats case final stats?) 'watchStats': stats.toRow(),
  };
  Workout withEffort(int value, DateTime now) => Workout(
    id: id,
    activity: activity,
    start: start,
    seconds: seconds,
    origin: origin,
    created: created,
    updated: now,
    notes: notes,
    source: source,
    effort: value,
    watchStats: watchStats,
  );
}

class WatchStats {
  const WatchStats({this.steps, this.distanceKm, this.batteryPercent});
  final int? steps, batteryPercent;
  final double? distanceKm;

  factory WatchStats.fromRow(RowData row) => WatchStats(
    steps: row['steps'] as int?,
    distanceKm: (row['distanceKm'] as num?)?.toDouble(),
    batteryPercent: row['batteryPercent'] as int?,
  );
  RowData toRow() => {
    'steps': steps,
    'distanceKm': distanceKm,
    'batteryPercent': batteryPercent,
  };
}

class ReadinessEntry {
  const ReadinessEntry(
    this.day,
    this.score,
    this.updated, {
    this.origin = Origin.manual,
    this.source = '',
  });
  final DateTime day, updated;
  final int score;
  final Origin origin;
  final String source;

  factory ReadinessEntry.fromRow(String day, RowData row) => ReadinessEntry(
    DateTime.parse(day),
    row['score'] as int,
    stamp(row, 'updated'),
    origin: Origin.values.byName(row['origin'] as String),
    source: row['source'] as String? ?? '',
  );
  RowData toRow() => {
    'score': score,
    'updated': clockStamp(updated),
    'origin': origin.name,
    'source': source,
  };
}

class AthleteProfile {
  const AthleteProfile({
    this.name = '',
    this.photo = '',
    this.heightCm,
    this.weightKg,
    this.birthYear,
    this.stepLengthCm,
  });
  final String name, photo;
  final double? heightCm, weightKg;
  final int? birthYear;
  final double? stepLengthCm;

  factory AthleteProfile.fromRow(RowData row) => AthleteProfile(
    name: row['name'] as String? ?? '',
    photo: row['photo'] as String? ?? '',
    heightCm: (row['heightCm'] as num?)?.toDouble(),
    weightKg: (row['weightKg'] as num?)?.toDouble(),
    birthYear: row['birthYear'] as int?,
    stepLengthCm: (row['stepLengthCm'] as num?)?.toDouble(),
  );
  RowData toRow() => {
    'name': name,
    'photo': photo,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'birthYear': birthYear,
    'stepLengthCm': stepLengthCm,
  };
}

class Session {
  const Session({
    required this.id,
    required this.started,
    required this.activity,
    this.activeSince,
    this.accumulated = 0,
  });
  final String id, activity;
  final DateTime started;
  final DateTime? activeSince;
  final int accumulated;

  Duration elapsed(DateTime now) => Duration(
    milliseconds:
        accumulated +
        (activeSince == null
            ? 0
            : max(0, now.difference(activeSince!).inMilliseconds)),
  );
  Session pause(DateTime now) => Session(
    id: id,
    started: started,
    activity: activity,
    accumulated: elapsed(now).inMilliseconds,
  );
  Session resume(DateTime now) => activeSince != null
      ? this
      : Session(
          id: id,
          started: started,
          activity: activity,
          accumulated: accumulated,
          activeSince: now,
        );

  factory Session.fromRow(String id, RowData row) => Session(
    id: id,
    started: stamp(row, 'started'),
    activity: row['activity'] as String,
    accumulated: row['accumulated'] as int,
    activeSince: row['activeSince'] == null ? null : stamp(row, 'activeSince'),
  );
  RowData toRow() => {
    'started': clockStamp(started),
    'activity': activity,
    'accumulated': accumulated,
    'activeSince': activeSince?.millisecondsSinceEpoch,
  };
}

class DayValue {
  const DayValue(this.day, this.value);
  final DateTime day;
  final double? value;
}
