import 'dart:typed_data';

import 'models.dart';

const m5ServiceUuid = '747e1000-7e91-4e27-a560-697562673001';
const m5SummaryUuid = '747e1001-7e91-4e27-a560-697562673001';
const m5SessionUuid = '747e1002-7e91-4e27-a560-697562673001';
const m5ControlUuid = '747e1003-7e91-4e27-a560-697562673001';

class WatchLink {
  const WatchLink(this.deviceId, this.name);
  final String deviceId, name;

  factory WatchLink.fromRow(RowData row) =>
      WatchLink(row['deviceId'] as String, row['name'] as String);

  RowData toRow() => {'deviceId': deviceId, 'name': name};
}

enum WatchAction {
  start(1),
  pause(2),
  resume(3),
  finish(4);

  const WatchAction(this.code);
  final int code;

  Uint8List encode(int token) =>
      (ByteData(5)
            ..setUint8(0, code)
            ..setUint32(1, token, Endian.little))
          .buffer
          .asUint8List();

  bool confirmedBy(WatchReading reading, int token) {
    if (reading.token != token) return false;
    return switch (this) {
      start || resume => reading.running && !reading.finished,
      pause => !reading.running && !reading.finished,
      finish => !reading.running && reading.finished,
    };
  }
}

class WatchReading {
  const WatchReading({
    required this.activeSeconds,
    required this.steps,
    required this.running,
    required this.finished,
    required this.token,
    this.batteryPercent,
    this.batteryMv,
  });
  final int activeSeconds, token;
  final int? steps, batteryPercent, batteryMv;
  final bool running, finished;

  static WatchReading? decode(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final version = bytes[0];
    if ((version == 1 && bytes.length != 16) ||
        (version == 2 && bytes.length != 18) ||
        (version != 1 && version != 2)) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final flags = bytes[1];
    final mv = data.getUint16(10, Endian.little);
    return WatchReading(
      running: flags & 1 != 0,
      finished: version == 2 && flags & 16 != 0,
      steps: flags & 2 != 0 ? data.getUint32(2, Endian.little) : null,
      activeSeconds: data.getUint32(6, Endian.little),
      batteryMv: mv == 0 || mv == 65535 ? null : mv,
      batteryPercent: mv != 0 && mv != 65535 && bytes[12] <= 100
          ? bytes[12]
          : null,
      token: version == 2 ? data.getUint32(13, Endian.little) : 0,
    );
  }

  factory WatchReading.fromRow(RowData row) => WatchReading(
    activeSeconds: row['seconds'] as int,
    steps: row['steps'] as int?,
    running: row['running'] as bool,
    finished: row['finished'] as bool,
    token: row['token'] as int,
    batteryPercent: row['percent'] as int?,
    batteryMv: row['mv'] as int?,
  );

  RowData toRow() => {
    'seconds': activeSeconds,
    'steps': steps,
    'running': running,
    'finished': finished,
    'token': token,
    'percent': batteryPercent,
    'mv': batteryMv,
  };

  WatchStats totals(AthleteProfile profile) {
    final stepLength = profile.stepLengthCm;
    return WatchStats(
      steps: steps,
      batteryPercent: batteryPercent,
      distanceKm: stepLength == null || steps == null
          ? null
          : steps! * stepLength / 100000,
    );
  }
}

class WatchDraft {
  const WatchDraft({
    required this.id,
    required this.token,
    required this.deviceId,
    required this.activity,
    required this.started,
    this.result,
  });
  final String id, deviceId, activity;
  final int token;
  final DateTime started;
  final WatchReading? result;

  factory WatchDraft.fromRow(RowData row) => WatchDraft(
    id: row['id'] as String,
    token: row['token'] as int,
    deviceId: row['deviceId'] as String,
    activity: row['activity'] as String,
    started: stamp(row, 'started'),
    result: row['result'] == null
        ? null
        : WatchReading.fromRow(Map<String, Object?>.from(row['result'] as Map)),
  );

  RowData toRow() => {
    'id': id,
    'token': token,
    'deviceId': deviceId,
    'activity': activity,
    'started': clockStamp(started),
    'result': result?.toRow(),
  };
}
