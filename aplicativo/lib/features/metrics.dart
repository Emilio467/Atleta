import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/demo.dart';
import '../core/metrics.dart';
import '../core/models.dart';
import '../core/strings.dart';
import '../ui/components.dart';
import '../ui/metric_chart.dart';
import '../ui/reference_icons.dart';
import '../ui/theme.dart';
import 'records.dart';

class LoadScreen extends StatefulWidget {
  const LoadScreen({super.key});
  @override
  State<LoadScreen> createState() => _LoadScreenState();
}

class _LoadScreenState extends State<LoadScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final values = store.ratios;
    final dates = values.keys.toList()..sort();
    final latest = dates.lastOrNull;
    final lastValue = latest == null ? null : values[latest]!;
    final anchor = store.demo
        ? (_page == 0 ? offsetDay(Demo.loadFocus, 13) : Demo.loadEnd)
        : latest ?? store.today;
    final end = store.demo ? anchor : offsetDay(anchor, -_page * 28);
    final series = seriesEnding(end, 28, values);
    return Screen(
      margin: 0,
      background: const DetailBackground(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Design.detailMargin),
          child: MetricHeader(
            symbol: ReferenceSymbol.load,
            title: S.load,
            value: lastValue?.toStringAsFixed(2),
            mono: true,
            date: latest == null ? null : S.day(latest),
            description: store.demo
                ? S.loadDemo
                : lastValue == null
                ? '${S.emptyLoad} ${S.loadCoverage(store.history.coverage(store.today))}.'
                : S.loadInfo,
            action: store.demo
                ? null
                : IconButton(
                    tooltip: S.metrics,
                    icon: const Icon(
                      CupertinoIcons.info_circle,
                      color: Palette.green,
                      size: 20,
                    ),
                    onPressed: () => showLoadMethod(context),
                  ),
          ),
        ),
        if (!store.demo) ...[
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Design.page),
            child: PeriodBar(
              days: 28,
              start: series.first.day,
              end: end,
              canGoNext: _page > 0,
              onBack: () => setState(() => _page++),
              onForward: () => setState(() => _page--),
            ),
          ),
        ],
        const SizedBox(height: 28),
        if (store.demo)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Design.detailMargin),
            child: Divider(height: 1, color: Color(0x2444773E)),
          ),
        SizedBox(height: store.demo ? 10 : 11),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: MetricChart(
            series: series,
            ratio: true,
            demo: store.demo && _page == 0,
            selection: store.demo && _page == 0 ? Demo.loadFocus : null,
            format: (value) => value.toStringAsFixed(2),
          ),
        ),
        const SizedBox(height: 29),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Design.detailMargin),
          child: Column(
            children: [
              MetricOverview(
                series: series,
                format: (value) => value.toStringAsFixed(2),
                showFullCoverage: !store.demo,
              ),
              const SizedBox(height: 16),
              if (store.demo)
                CompactTile(
                  title: _page == 0 ? S.latest : S.previous,
                  onTap: () => setState(() => _page = _page == 0 ? 1 : 0),
                ),
              const SizedBox(height: 8),
              CompactTile(
                title: S.metrics,
                icon: CupertinoIcons.info_circle,
                onTap: () => showLoadMethod(context),
              ),
              if (!store.demo) ...[
                const SizedBox(height: 8),
                CompactTile(
                  title: S.markRest,
                  icon: CupertinoIcons.moon,
                  onTap: () => showRestForm(context),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> showLoadMethod(BuildContext context) async {
  final isDemo = AtletaScope.of(context).demo;
  await sheet<void>(
    context,
    (_) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormHeading(S.load),
        const SizedBox(height: 13),
        const Text(S.loadInfo, style: Design.body),
        const SizedBox(height: 10),
        const Text(S.loadRules, style: Design.body),
        const SizedBox(height: 10),
        Text(
          isDemo ? S.loadDemoBandExplanation : S.loadBandsInfo,
          style: Design.foot,
        ),
      ],
    ),
  );
}

class DetailBackground extends StatelessWidget {
  const DetailBackground({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: SizedBox(
      height: 503,
      child: DecoratedBox(decoration: BoxDecoration(gradient: Palette.detail)),
    ),
  );
}

class MetricHeader extends StatelessWidget {
  const MetricHeader({
    super.key,
    required this.symbol,
    required this.title,
    required this.description,
    this.value,
    this.unit,
    this.date,
    this.action,
    this.mono = false,
  });
  final ReferenceSymbol symbol;
  final String title, description;
  final String? value, unit, date;
  final Widget? action;
  final bool mono;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const CircleBack(),
      const SizedBox(height: 24),
      Row(
        children: [
          ReferenceIcon(symbol, color: Palette.green, size: 26),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: Design.label)),
          ?action,
        ],
      ),
      SizedBox(height: mono ? 31 : 34),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: value ?? S.noValue),
            if (unit != null && value != null)
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -.25,
                  color: Palette.muted,
                ),
              ),
          ],
        ),
        style: Design.metric.copyWith(
          fontFamily: mono ? Design.mono : null,
          letterSpacing: mono ? 1.5 : -1.6,
        ),
      ),
      if (date case final day?) ...[
        const SizedBox(height: 3),
        Text(day, style: Design.foot),
      ],
      const SizedBox(height: 12),
      Text(description, style: Design.body),
    ],
  );
}

class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.days,
    required this.start,
    required this.end,
    required this.canGoNext,
    required this.onBack,
    required this.onForward,
    this.onPeriod,
  });
  final int days;
  final DateTime start, end;
  final bool canGoNext;
  final VoidCallback onBack, onForward;
  final ValueChanged<int>? onPeriod;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('d MMM y', 'en_US');
    final beginning = start.month == end.month && start.year == end.year
        ? start.day.toString()
        : (start.year == end.year ? DateFormat('d MMM', 'en_US') : format)
              .format(start);
    final interval = '$beginning–${format.format(end)}';
    return Row(
      children: [
        _PeriodButton(
          label: S.previous,
          icon: CupertinoIcons.chevron_left,
          onTap: onBack,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              interval,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.1),
            ),
          ),
        ),
        _PeriodButton(
          label: S.next,
          icon: CupertinoIcons.chevron_right,
          onTap: canGoNext ? onForward : null,
        ),
        if (onPeriod != null)
          PopupMenuButton<int>(
            key: const ValueKey('metric-period'),
            initialValue: days,
            tooltip: S.period,
            onSelected: onPeriod,
            itemBuilder: (_) => [
              for (final period in [7, 14, 30])
                PopupMenuItem(
                  value: period,
                  child: Text(S.periodLabel(period)),
                ),
            ],
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              height: 42,
              alignment: Alignment.center,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xC4263927),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        S.periodLabel(days),
                        style: const TextStyle(fontSize: 14, height: 1.06),
                      ),
                      const SizedBox(width: 11),
                      const Icon(
                        CupertinoIcons.chevron_up_chevron_down,
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    icon: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onTap == null
            ? const Color(0x42243627)
            : const Color(0xE1263928),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(icon, size: 18),
      ),
    ),
  );
}
