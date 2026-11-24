import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/models.dart';
import '../core/strings.dart';
import 'theme.dart';

class MetricChart extends StatefulWidget {
  const MetricChart({
    super.key,
    required this.series,
    required this.format,
    this.selection,
    this.ratio = false,
    this.demo = false,
    this.steps = false,
  });

  final List<DayValue> series;
  final String Function(double value) format;
  final DateTime? selection;
  final bool ratio, demo, steps;

  @override
  State<MetricChart> createState() => _MetricChartState();
}

class _MetricChartState extends State<MetricChart> {
  int? _picked;
  bool _interacted = false;

  int? get _selected {
    if (_picked case final index?) return index;
    final date = widget.selection;
    final matching = widget.series.indexWhere(
      (p) => p.day == date && p.value != null,
    );
    if (matching >= 0) return matching;
    final last = widget.series.lastIndexWhere((p) => p.value != null);
    return last < 0 ? null : last;
  }

  @override
  void didUpdateWidget(covariant MetricChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series.length != widget.series.length ||
        oldWidget.series.firstOrNull?.day != widget.series.firstOrNull?.day ||
        oldWidget.series.lastOrNull?.day != widget.series.lastOrNull?.day ||
        (_picked != null && widget.series[_picked!].value == null)) {
      _picked = null;
      _interacted = false;
    }
  }

  void _choose(int index) {
    if ((_interacted && _picked == index) ||
        widget.series[index].value == null) {
      return;
    }
    setState(() {
      _picked = index;
      _interacted = true;
    });
  }

  int? _neighbor(int direction) {
    final selected = _selected;
    if (selected == null) return null;
    for (
      var i = selected + direction;
      i >= 0 && i < widget.series.length;
      i += direction
    ) {
      if (widget.series[i].value != null) return i;
    }
    return null;
  }

  void _step(int direction) {
    if (_neighbor(direction) case final index?) _choose(index);
  }

  String? _semanticValue(int? index) {
    if (index == null) return null;
    final point = widget.series[index];
    return widget.steps
        ? '${S.shortDay(point.day)} · ${widget.format(point.value!)}'
        : '${widget.format(point.value!)} · ${S.day(point.day)}';
  }

  void _selectNear(double x, _Geometry geometry) {
    final index = List.generate(widget.series.length, (i) => i)
        .where((i) => widget.series[i].value != null)
        .fold<int?>(
          null,
          (nearest, i) =>
              nearest == null ||
                  (geometry.x(i) - x).abs() < (geometry.x(nearest) - x).abs()
              ? i
              : nearest,
        );
    if (index != null) _choose(index);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final current = selected == null ? null : widget.series[selected];
    final values = widget.series.map((p) => p.value).nonNulls.toList();
    final isRatio = widget.ratio;
    final isDemo = widget.demo;
    final isSteps = widget.steps;
    final scale = _Scale(values, ratio: isRatio, demo: isDemo, steps: isSteps);
    final height = isSteps
        ? 208.0
        : isRatio
        ? 334.0
        : 262.0;
    final top = isSteps
        ? 31.0
        : isRatio
        ? 88.0
        : 10.0;
    final marker = isSteps
        ? Palette.lime
        : isRatio
        ? Palette.orange
        : Palette.green;
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _step(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _step(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        label: isSteps ? S.stepsByDay : S.load,
        value: _semanticValue(selected) ?? S.chartEmpty,
        increasedValue: _semanticValue(_neighbor(1)),
        decreasedValue: _semanticValue(_neighbor(-1)),
        onIncrease: _neighbor(1) == null ? null : () => _step(1),
        onDecrease: _neighbor(-1) == null ? null : () => _step(-1),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, box) {
              final geometry = _Geometry(
                width: box.maxWidth,
                top: top,
                bottom: height - 43,
                count: widget.series.length,
                ratio: isRatio,
                steps: isSteps,
                scale: scale,
              );
              final showTooltip =
                  current?.value != null && (isSteps || isRatio || _interacted);
              final tipWidth = math.min(
                box.maxWidth,
                isSteps
                    ? MediaQuery.textScalerOf(context).scale(164)
                    : math.max(
                        97.0,
                        MediaQuery.textScalerOf(context).scale(79),
                      ),
              );
              final tipX = selected == null
                  ? 0.0
                  : (geometry.x(selected) - tipWidth / 2).clamp(
                      0.0,
                      box.maxWidth - tipWidth,
                    );
              final tipY = isRatio ? 5.0 : 0.0;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: selected == null
                    ? null
                    : (event) => _selectNear(event.localPosition.dx, geometry),
                onHorizontalDragStart: selected == null
                    ? null
                    : (event) => _selectNear(event.localPosition.dx, geometry),
                onHorizontalDragUpdate: selected == null
                    ? null
                    : (event) => _selectNear(event.localPosition.dx, geometry),
                child: Stack(
                  children: [
                    CustomPaint(
                      size: Size(box.maxWidth, height),
                      painter: _Plot(
                        series: widget.series,
                        geometry: geometry,
                        selected: selected,
                        marker: marker,
                        demo: isDemo,
                        showTooltip: showTooltip,
                        textScale: MediaQuery.textScalerOf(context),
                      ),
                    ),
                    if (current == null)
                      Center(
                        child: Text(
                          isSteps ? S.noStepHistory : S.chartEmpty,
                          style: Design.foot,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (showTooltip)
                      Positioned(
                        top: tipY,
                        left: tipX,
                        width: tipWidth,
                        child: IgnorePointer(
                          child: isSteps
                              ? _StepsTip(_semanticValue(selected)!)
                              : _ChartTip(
                                  widget.format(current!.value!),
                                  S.day(current.day),
                                ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StepsTip extends StatelessWidget {
  const _StepsTip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF182216),
      border: Border.all(color: const Color(0xFF586651)),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class _ChartTip extends StatelessWidget {
  const _ChartTip(this.value, this.date);
  final String value, date;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF22D442E),
      borderRadius: BorderRadius.circular(19),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontFamily: Design.mono,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            date,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
        ],
      ),
    ),
  );
}

class _Scale {
  _Scale(
    List<double> values, {
    required this.ratio,
    required this.demo,
    required bool steps,
  }) {
    if (steps) {
      final max = values.fold(0.0, math.max);
      final step = math.max(1, (max / 2500).ceil()) * 500.0;
      lower = 0;
      upper = step * 5;
      ticks = [for (var i = 0; i <= 5; i++) step * i];
    } else if (ratio) {
      lower = 0;
      upper = demo
          ? 1.85
          : math.max(1.5, values.isEmpty ? 0 : values.reduce(math.max) + .12);
      ticks = demo ? [0, .8, 1.3, 1.5] : [0, upper / 3, upper * 2 / 3, upper];
    } else if (demo) {
      lower = 55;
      upper = 71.5;
      ticks = [60, 65, 70];
    } else {
      final min = values.isEmpty ? 55.0 : values.reduce(math.min);
      final max = values.isEmpty ? 75.0 : values.reduce(math.max);
      final step = math.max(5.0, (((max - min) / 4) / 5).ceil() * 5.0);
      lower = math.max(0, (min / step).floor() * step - step);
      upper = (max / step).ceil() * step + step;
      ticks = [
        for (var value = lower + step; value < upper; value += step) value,
      ];
    }
  }
  final bool ratio, demo;
  late final double lower, upper;
  late final List<double> ticks;
}

class _Geometry {
  const _Geometry({
    required this.width,
    required this.top,
    required this.bottom,
    required this.count,
    required this.ratio,
    required this.steps,
    required this.scale,
  });
  final double width, top, bottom;
  final int count;
  final bool ratio, steps;
  final _Scale scale;
  double get right => steps ? width - 3 : width - 35;
  double get left => steps
      ? 44
      : ratio
      ? 1
      : 28;
  double x(int index) {
    final start = steps ? left + 13 : left;
    final end =
        right -
        (steps
            ? 15
            : ratio
            ? 0
            : 30);
    if (count <= 1) return (end + start) / 2;
    return start + (end - start) * index / (count - 1);
  }

  double y(double value) =>
      bottom -
      (bottom - top) *
          ((value - scale.lower) / (scale.upper - scale.lower)).clamp(0, 1);
}

class _Plot extends CustomPainter {
  _Plot({
    required this.series,
    required this.geometry,
    required this.selected,
    required this.marker,
    required this.demo,
    required this.showTooltip,
    required this.textScale,
  });
  final List<DayValue> series;
  final _Geometry geometry;
  final int? selected;
  final Color marker;
  final bool demo, showTooltip;
  final TextScaler textScale;

  void _text(
    Canvas canvas,
    String value,
    Offset point,
    Color color,
    double font, {
    bool center = false,
    FontWeight weight = FontWeight.w400,
    double maxWidth = 100,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: font,
          fontFamily: 'Inter',
          fontWeight: weight,
          height: 1.06,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.start,
      textScaler: TextScaler.linear(
        math.min(1.25, textScale.scale(font) / font),
      ),
      maxLines: 2,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, point.translate(center ? -painter.width / 2 : 0, 0));
    painter.dispose();
  }

  void _band(Canvas canvas, double high, double low, Color color) {
    canvas.drawRect(
      Rect.fromLTRB(0, geometry.y(high), geometry.right, geometry.y(low)),
      Paint()..color = color,
    );
  }

  void _dashes(Canvas canvas, double y, double end, Paint paint) {
    for (var x = 0.0; x < end; x += 4) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 1, end), y), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final axis = Paint()
      ..color = const Color(0xFF3B3F3A)
      ..strokeWidth = .8;
    final grid = Paint()
      ..color = const Color(0x604B534B)
      ..strokeWidth = .65;
    if (g.ratio) {
      if (demo) {
        _band(canvas, 1.3, .8, const Color(0xA338373C));
        _band(canvas, 1.5, 1.3, const Color(0x1F55565A));
        for (final entry in [
          (1.65, S.loadDemoBandTop),
          (1.44, S.loadDemoBandMiddle),
          (1.11, S.loadDemoBandNear),
          (.45, S.loadDemoBandBottom),
        ]) {
          _text(
            canvas,
            entry.$2,
            Offset(6, g.y(entry.$1)),
            const Color(0xFF818680),
            9,
          );
        }
      } else {
        _band(canvas, 1.1, .9, const Color(0x3B494F49));
        canvas.drawLine(Offset(0, g.y(1)), Offset(g.right, g.y(1)), grid);
      }
    } else if (demo) {
      _band(canvas, 66, 57, const Color(0x7E152D12));
      canvas.drawLine(
        Offset(19, g.y(62)),
        Offset(g.right - 19, g.y(62)),
        Paint()
          ..color = const Color(0xFFA9BBA6)
          ..strokeWidth = 1.9,
      );
    }
    for (final tick in g.scale.ticks) {
      final y = g.y(tick);
      if (g.steps || g.ratio) {
        canvas.drawLine(
          Offset(g.steps ? g.left : 0, y),
          Offset(g.right, y),
          grid,
        );
      } else {
        _dashes(canvas, y, g.right, grid);
      }
      _text(
        canvas,
        g.steps
            ? S.number(tick.round())
            : g.ratio
            ? tick.toStringAsFixed(2)
            : tick.round().toString(),
        Offset(g.steps ? 0 : g.right + 6, y - 5),
        Palette.axis,
        g.ratio ? 9 : 10,
        maxWidth: g.steps ? 42 : 32,
      );
    }
    final axisX = g.steps ? g.left : g.right;
    canvas.drawLine(
      Offset(g.steps ? g.left : 0, g.bottom),
      Offset(g.right, g.bottom),
      axis,
    );
    canvas.drawLine(Offset(axisX, g.top), Offset(axisX, g.bottom), axis);

    final path = Path();
    // The demo crop contains the end of a stroke to the left of its
    // first labelled point. It is decorative and has no selectable sample.
    var penDown = demo && !g.ratio && series.firstOrNull?.value != null;
    if (penDown) path.moveTo(0, g.y(69));
    for (final (i, point) in series.indexed) {
      final value = point.value;
      if (value == null) {
        penDown = false;
        continue;
      }
      if (penDown) {
        path.lineTo(g.x(i), g.y(value));
      } else {
        path.moveTo(g.x(i), g.y(value));
      }
      penDown = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = g.ratio ? 2.6 : 2.05
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = g.steps ? Palette.lime : Palette.line,
    );

    for (final (i, point) in series.indexed) {
      final value = point.value;
      if (value == null) continue;
      final chosen = i == selected;
      final position = Offset(g.x(i), g.y(value));
      if (chosen) {
        if (g.ratio || (!g.steps && showTooltip)) {
          canvas.drawLine(
            Offset(position.dx, g.ratio ? 68 : g.top),
            Offset(position.dx, g.bottom),
            Paint()
              ..color = const Color(0x9C9D9B96)
              ..strokeWidth = .75,
          );
        }
        canvas.drawCircle(
          position,
          9,
          Paint()
            ..color = marker
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawCircle(position, 7, Paint()..color = marker);
        if (!g.steps) {
          canvas.drawCircle(
            position,
            3.8,
            Paint()..color = const Color(0xFF1B2419),
          );
        }
      } else if (!g.ratio || series.where((d) => d.value != null).length <= 2) {
        final dense = g.steps && series.length > 14;
        canvas.drawCircle(
          position,
          dense ? 2 : 3.6,
          Paint()..color = g.steps ? Palette.lime : const Color(0xFFD3D9D0),
        );
        if (!dense) {
          canvas.drawCircle(position, 2, Paint()..color = Palette.background);
        }
      }
      if (!g.steps && !g.ratio && series.length <= 7) {
        _text(
          canvas,
          value.round().toString(),
          position.translate(0, chosen ? -22 : -20),
          Palette.text,
          11,
          center: true,
          weight: FontWeight.w600,
        );
      }
    }

    if (!g.ratio && series.length <= 7) {
      for (final (i, point) in series.indexed) {
        final chosen = i == selected;
        final weekday = g.steps
            ? S.weekday(point.day)
            : DateFormat('EEE', 'en_US').format(point.day);
        _text(
          canvas,
          '$weekday\n${point.day.day}',
          Offset(g.x(i), g.bottom + 12),
          chosen ? Palette.text : Palette.muted,
          10,
          center: true,
          weight: chosen ? FontWeight.w600 : FontWeight.w400,
        );
      }
    } else {
      final stride = math.max(1, (series.length / 4).floor());
      final firstTick = g.ratio ? 2 : 0;
      final spacing = g.ratio && demo ? 7 : stride;
      for (var i = firstTick; i < series.length; i += spacing) {
        if (g.x(i) > g.right - 11) continue;
        final day = series[i].day;
        final showMonth = i == firstTick
            ? !g.ratio || !demo
            : series[i - spacing].day.month != day.month;
        final month = g.steps
            ? S.month(day)
            : DateFormat('MMM', 'en_US').format(day);
        _text(
          canvas,
          showMonth ? '${day.day}\n$month' : day.day.toString(),
          Offset(g.x(i), g.bottom + 11),
          Palette.muted,
          10,
          center: true,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Plot oldDelegate) => true;
}
