import 'models.dart';

abstract final class Demo {
  static final today = DateTime(2025, 12, 14);
  static final loadEnd = DateTime(2025, 12, 18);
  static final loadFocus = DateTime(2025, 11, 7);
  static final load = <DateTime, double>{
    for (final (i, ratio) in [
      1.28,
      .94,
      .71,
      .53,
      .41,
      .31,
      .24,
      .18,
      .13,
      .10,
      .08,
      .76,
      1.29,
      1.00,
      1.39,
      1.14,
      .91,
      .69,
      1.29,
      1.02,
      .80,
      .62,
      .47,
      .33,
      1.06,
      .81,
      1.55,
      1.19,
    ].indexed)
      offsetDay(loadFocus, i - 14): ratio,
    loadEnd: .98,
  };
  static final workout = Workout(
    id: 'demo-aerobics',
    activity: 'Aerobics',
    start: DateTime(2025, 12, 14, 9, 41),
    seconds: 300,
    effort: 4,
    origin: Origin.demo,
    created: today,
    updated: today,
  );
  static final readiness = ReadinessEntry(
    today,
    73,
    DateTime(2025, 12, 14, 9, 41),
    origin: Origin.demo,
  );
}
