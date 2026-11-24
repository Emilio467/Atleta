import 'models.dart';

class MetricSummary {
  MetricSummary(List<DayValue> series) : days = series.length {
    final values = series.map((x) => x.value).nonNulls.toList()..sort();
    count = values.length;
    if (values.isEmpty) return;
    min = values.first;
    max = values.last;
    average = values.reduce((a, b) => a + b) / values.length;
  }
  final int days;
  late final int count;
  double? min, max, average;
}

class LoadHistory {
  LoadHistory(Iterable<Workout> workouts, Set<String> restDays) {
    for (final day in restDays) {
      _daily[DateTime.parse(day)] = 0;
    }
    final incomplete = <DateTime>{};
    for (final workout in workouts) {
      final day = dayOf(workout.start);
      final effort = workout.effort;
      if (effort == null || effort < 0 || effort > 10 || workout.seconds <= 0) {
        incomplete.add(day);
        continue;
      }
      _daily.update(
        day,
        (prior) => prior + workout.seconds / 60 * effort,
        ifAbsent: () => workout.seconds / 60 * effort,
      );
    }
    _daily.removeWhere((day, _) => incomplete.contains(day));
    final dates = _daily.keys.toList()..sort();
    var run = 0;
    DateTime? previous;
    for (final day in dates) {
      run = previous != null && offsetDay(previous, 1) == day ? run + 1 : 1;
      previous = day;
      if (run < 28) continue;
      final chronic = _sum(day, 28);
      if (chronic > 0) ratios[day] = 4 * _sum(day, 7) / chronic;
    }
  }
  final _daily = <DateTime, double>{};
  final ratios = <DateTime, double>{};

  double _sum(DateTime end, int days) => List.generate(
    days,
    (i) => _daily[offsetDay(end, -i)]!,
  ).reduce((a, b) => a + b);

  int coverage(DateTime end) => List.generate(
    28,
    (i) => offsetDay(end, -i),
  ).where(_daily.containsKey).length;
}

List<DayValue> seriesEnding(
  DateTime end,
  int days,
  Map<DateTime, double> values,
) => List.generate(days, (i) {
  final day = offsetDay(dayOf(end), i - days + 1);
  return DayValue(day, values[day]);
});
