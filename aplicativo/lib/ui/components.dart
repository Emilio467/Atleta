import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/metrics.dart';
import '../core/models.dart';
import '../core/strings.dart';
import 'reference_icons.dart';
import 'theme.dart';

class AtletaScope extends InheritedNotifier<AtletaController> {
  const AtletaScope({
    super.key,
    required AtletaController store,
    this.onSwitchProfile,
    required super.child,
  }) : super(notifier: store);
  final VoidCallback? onSwitchProfile;

  static AtletaController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AtletaScope>()!.notifier!;

  static VoidCallback? switchProfileOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AtletaScope>()!
      .onSwitchProfile;
}

class Screen extends StatelessWidget {
  const Screen({
    super.key,
    required this.children,
    this.background,
    this.margin = Design.page,
    this.topSpacing = 3,
    this.controller,
  });

  final List<Widget> children;
  final Widget? background;
  final double margin, topSpacing;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: Palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (background case final artwork?)
            Positioned(left: 0, right: 0, top: 0, child: artwork),
          CustomScrollView(
            controller: controller,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  math.max(margin, safe.left),
                  math.max(safe.top, kIsWeb ? 53 : 48) + topSpacing,
                  math.max(margin, safe.right),
                  111 + safe.bottom,
                ),
                sliver: SliverList.list(children: children),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DashboardBackground extends StatelessWidget {
  const DashboardBackground({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height,
    child: const DecoratedBox(
      decoration: BoxDecoration(gradient: Palette.dashboard),
    ),
  );
}

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.color = const Color(0x661F4A20),
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0x2698C985)),
    ),
    child: child,
  );
}

class CircleBack extends StatelessWidget {
  const CircleBack({super.key});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: IconButton(
      tooltip: S.back,
      onPressed: () => Navigator.of(context).maybePop(),
      style: IconButton.styleFrom(
        side: const BorderSide(color: Color(0x4D96C986)),
        minimumSize: const Size(46, 46),
        foregroundColor: const Color(0xFFCAEDC0),
      ),
      icon: const Icon(CupertinoIcons.chevron_left, size: 20),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: Design.section);
}

class CompactTile extends StatelessWidget {
  const CompactTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.symbol,
    this.onTap,
    this.trailing,
    this.radius = Design.card,
    this.titleStyle,
    this.minimumHeight = 44,
    this.accent = Palette.green,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final ReferenceSymbol? symbol;
  final VoidCallback? onTap;
  final Widget? trailing;
  final double radius, minimumHeight;
  final TextStyle? titleStyle;
  final Color accent;

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.surface,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: subtitle == null ? (minimumHeight - 16) / 2 : 15,
        ),
        child: Row(
          children: [
            if (symbol != null || icon != null) ...[
              if (symbol case final glyph?)
                ReferenceIcon(glyph, size: 23, color: accent)
              else
                Icon(icon, size: 23, color: accent),
              const SizedBox(width: 13),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        titleStyle ??
                        const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (subtitle case final text?) ...[
                    const SizedBox(height: 4),
                    Text(text, style: Design.foot),
                  ],
                ],
              ),
            ),
            if (trailing case final end?) ...[
              const SizedBox(width: Design.small),
              end,
            ] else if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: Palette.axis,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class WorkoutTile extends StatelessWidget {
  const WorkoutTile(this.workout, {super.key, required this.onTap});

  final Workout workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CompactTile(
    title: S.activityName(workout.activity),
    subtitle:
        '${S.shortDay(workout.start.toLocal())} · ${S.compactDuration(workout.seconds)}',
    icon: switch (workout.activity.toLowerCase()) {
      'walking' || 'caminhada' => Icons.directions_walk_rounded,
      'cycling' || 'ciclismo' => Icons.directions_bike_rounded,
      'swimming' || 'natação' => Icons.pool_rounded,
      'strength' || 'musculação' => Icons.fitness_center_rounded,
      'aerobics' || 'aeróbica' => null,
      _ => Icons.directions_run_rounded,
    },
    symbol: switch (workout.activity.toLowerCase()) {
      'aerobics' || 'aeróbica' => ReferenceSymbol.aerobics,
      _ => null,
    },
    radius: 15,
    accent: Palette.lime,
    onTap: onTap,
  );
}

class MetricOverview extends StatelessWidget {
  const MetricOverview({
    super.key,
    required this.series,
    required this.format,
    this.title,
    this.showFullCoverage = true,
  });
  final List<DayValue> series;
  final String Function(double value) format;
  final String? title;
  final bool showFullCoverage;

  @override
  Widget build(BuildContext context) {
    final summary = MetricSummary(series);
    final cards = [
      (S.avg, ReferenceSymbol.average, summary.average),
      (S.max, ReferenceSymbol.maximum, summary.max),
      (S.min, ReferenceSymbol.minimum, summary.min),
    ];
    final wide = MediaQuery.textScalerOf(context).scale(13) < 19;
    final widgets = cards
        .map(
          (card) => SummaryCard(
            card.$1,
            card.$3 == null ? S.noValue : format(card.$3!),
            symbol: card.$2,
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title ?? S.overview(summary.days),
          style: Design.foot.copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        if (wide)
          Row(
            children: [
              for (final (index, card) in widgets.indexed) ...[
                if (index > 0) const SizedBox(width: 9),
                Expanded(child: card),
              ],
            ],
          )
        else
          Column(
            children: [
              for (final card in widgets)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: card),
            ],
          ),
        if (showFullCoverage || summary.count != summary.days) ...[
          const SizedBox(height: 10),
          Text(S.coverage(summary.count, summary.days), style: Design.foot),
        ],
      ],
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard(
    this.label,
    this.value, {
    super.key,
    this.icon = Icons.bar_chart,
    this.symbol,
  });
  final String label, value;
  final IconData icon;
  final ReferenceSymbol? symbol;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1B1A1C), Color(0xFF101012)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (symbol case final glyph?)
          ReferenceIcon(glyph, size: 24, color: Palette.text)
        else
          Icon(icon, size: 21, color: Palette.muted),
        const SizedBox(height: 6),
        Text(label, style: Design.foot),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontFamily: Design.mono,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class FormHeading extends StatelessWidget {
  const FormHeading(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      fontSize: 25,
      height: 1.14,
      fontWeight: FontWeight.w700,
      letterSpacing: -.7,
    ),
  );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(Design.card),
    ),
    child: Text(text, style: Design.foot),
  );
}

Future<T?> sheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: Design.maxWidth),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: builder(context),
          ),
        ),
      ),
    );

void pushScreen(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const names = [S.today, S.progress, S.workouts];
  static const symbols = [
    ReferenceSymbol.today,
    ReferenceSymbol.progress,
    ReferenceSymbol.workouts,
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) {
      final scaled = MediaQuery.textScalerOf(context).scale(10);
      final height = Design.navHeight + math.max(0.0, scaled - 11);
      final width = math.min(
        390.0,
        viewport.maxWidth * (scaled <= 12 ? .86 : .94),
      );
      final radius = BorderRadius.circular(Design.pill);
      return Center(
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: Palette.navigationGlass,
                borderRadius: radius,
                border: Border.all(color: Palette.navigationBorder),
              ),
              child: SizedBox(
                width: width,
                height: height,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Row(
                      children: [
                        for (var i = 0; i < names.length; i++)
                          Expanded(
                            child: Semantics(
                              selected: index == i,
                              button: true,
                              child: InkWell(
                                key: ValueKey('tab-$i'),
                                borderRadius: radius,
                                onTap: () => onTap(i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  decoration: BoxDecoration(
                                    borderRadius: radius,
                                    gradient: index == i
                                        ? Palette.navigationSelected
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        height: 30,
                                        child: Center(
                                          child: ReferenceIcon(
                                            symbols[i],
                                            color: index == i
                                                ? Palette.pink
                                                : Palette.text,
                                            size: i == 2 ? 32 : 29,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        names[i],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: index == i
                                              ? Palette.pink
                                              : Palette.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
