import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/metrics.dart';
import '../core/models.dart';
import '../core/strings.dart';
import '../ui/components.dart';
import '../ui/metric_chart.dart';
import '../ui/reference_icons.dart';
import '../ui/theme.dart';
import 'metrics.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int _days = 7, _page = 0;

  Widget _summaryRow(_SummaryTile first, _SummaryTile second) =>
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final end = offsetDay(store.today, -_page * _days);
    final start = offsetDay(end, 1 - _days);
    bool within(DateTime date) =>
        !dayOf(date).isBefore(start) && !dayOf(date).isAfter(end);
    final workouts = store.data.workouts.where(
      (record) => within(record.start),
    );
    var seconds = 0;
    var count = 0;
    double? distance;
    final stepsByDay = <DateTime, double>{};
    for (final workout in workouts) {
      count++;
      seconds += workout.seconds;
      if (workout.watchStats?.steps case final steps?) {
        stepsByDay.update(
          dayOf(workout.start),
          (total) => total + steps,
          ifAbsent: () => steps.toDouble(),
        );
      }
      if (workout.watchStats?.distanceKm case final km?) {
        distance = (distance ?? 0) + km;
      }
    }
    final steps = stepsByDay.values.fold(
      0,
      (total, value) => total + value.round(),
    );
    return Screen(
      background: const DashboardBackground(),
      children: [
        const Text(S.progress, style: Design.header),
        const SizedBox(height: 19),
        _PeriodSelector(
          selected: _days,
          onChange: (days) => setState(() {
            _days = days;
            _page = 0;
          }),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                S.shortPeriod(start, end),
                style: Design.foot.copyWith(fontSize: 14),
              ),
            ),
            IconButton(
              tooltip: S.previous,
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _page++),
              icon: const Icon(CupertinoIcons.chevron_left, size: 15),
            ),
            IconButton(
              tooltip: S.next,
              visualDensity: VisualDensity.compact,
              onPressed: _page > 0 ? () => setState(() => _page--) : null,
              icon: const Icon(CupertinoIcons.chevron_right, size: 15),
            ),
          ],
        ),
        _summaryRow(
          _SummaryTile(S.workouts, S.number(count)),
          _SummaryTile(S.duration, S.compactDuration(seconds)),
        ),
        const SizedBox(height: 10),
        _summaryRow(
          _SummaryTile(
            S.m5Steps,
            stepsByDay.isEmpty ? S.noValue : S.number(steps),
          ),
          _SummaryTile(
            S.distance,
            distance == null ? S.noValue : S.kilometers(distance),
          ),
        ),
        const SizedBox(height: 22),
        const Text(S.stepsByDay, style: Design.dashboardSection),
        const SizedBox(height: 8),
        if (stepsByDay.isEmpty)
          const EmptyCard(S.noStepHistory)
        else
          MetricChart(
            steps: true,
            series: seriesEnding(end, _days, stepsByDay),
            format: (value) => '${S.number(value.round())} ${S.stepsUnit}',
          ),
        const SizedBox(height: 16),
        CompactTile(
          key: const ValueKey('open-load'),
          title: S.load,
          symbol: ReferenceSymbol.load,
          radius: 15,
          accent: Palette.lime,
          onTap: () => pushScreen(context, (_) => const LoadScreen()),
        ),
      ],
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onChange});

  final int selected;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Design.pill);
    return Material(
      color: const Color(0x2E122410),
      shape: StadiumBorder(
        side: BorderSide(color: Palette.muted.withValues(alpha: .38)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final days in [7, 30, 90])
            Expanded(
              child: Semantics(
                selected: days == selected,
                button: true,
                child: InkWell(
                  borderRadius: radius,
                  onTap: () => onChange(days),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      color: days == selected ? Palette.lime : null,
                      borderRadius: radius,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 9,
                    ),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    child: Text(
                      '$days dias',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: days == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: days == selected
                            ? const Color(0xFF0D2105)
                            : Palette.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => DashboardPanel(
    radius: 15,
    color: const Color(0xB3233222),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 25,
            height: 1.08,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Design.foot.copyWith(fontSize: 14)),
      ],
    ),
  );
}
