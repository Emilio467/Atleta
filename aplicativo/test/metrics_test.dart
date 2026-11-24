import 'package:atleta/core/metrics.dart';
import 'package:atleta/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

Workout workout(
  DateTime date, {
  int? effort = 5,
  int seconds = 1800,
  String id = 'a',
}) => Workout(
  id: id,
  activity: 'Running',
  start: date,
  seconds: seconds,
  effort: effort,
  origin: Origin.manual,
  created: date,
  updated: date,
);

void main() {
  test('load uses 7/28 daily means, confirmed rest and all sessions', () {
    final end = DateTime(2025, 12, 19);
    final previous = offsetDay(end, -7);
    final rest = {
      for (var day = 1; day < 28; day++)
        if (day != 7) dayKey(offsetDay(end, -day)),
    };
    final loads = LoadHistory([
      workout(end),
      workout(end, effort: 5, id: 'second'),
      workout(previous, effort: 10),
    ], rest);
    expect(loads.coverage(end), 28);
    expect(loads.ratios[end], 2);
    expect(loads.ratios[offsetDay(end, -1)], isNull);
    expect(LoadHistory([workout(end)], rest).ratios[end], isNull);
    final changed = LoadHistory([
      workout(end, effort: 10),
      workout(end, id: 'second'),
      workout(previous, effort: 10),
    ], rest);
    expect(changed.ratios[end], closeTo(2.4, .001));
    final removed = LoadHistory([workout(previous, effort: 10)], rest);
    expect(removed.ratios[end], isNull);
    final noEffort = LoadHistory([
      workout(end),
      workout(previous, effort: null),
    ], rest);
    expect(noEffort.coverage(end), 27);
    expect(noEffort.ratios[end], isNull);
  });

  test('zero chronic load is unavailable, while zero recent load is valid', () {
    final end = DateTime(2025, 12, 19);
    final rest = {for (var i = 0; i < 28; i++) dayKey(offsetDay(end, -i))};
    expect(LoadHistory([], rest).ratios, isEmpty);
    expect(LoadHistory([workout(offsetDay(end, -8))], rest).ratios[end], 0);
  });

  test('session elapsed uses timestamps and excludes time paused', () {
    final start = DateTime(2025, 12, 19, 12);
    final session = Session(
      id: 'one',
      started: start,
      activeSince: start,
      activity: 'Walking',
    );
    final paused = session.pause(start.add(const Duration(seconds: 42)));
    final resumeAt = start.add(const Duration(hours: 1));
    expect(paused.elapsed(resumeAt).inSeconds, 42);
    expect(
      paused
          .resume(resumeAt)
          .elapsed(resumeAt.add(const Duration(seconds: 21)))
          .inSeconds,
      63,
    );
  });
}
