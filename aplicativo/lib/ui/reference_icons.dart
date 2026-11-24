import 'package:flutter/material.dart';

enum ReferenceSymbol {
  today,
  progress,
  workouts,
  aerobics,
  info,
  load,
  average,
  maximum,
  minimum,
  effort;

  String get assetName => 'assets/icons/$name.png';
}

/// Individually isolated glyphs from the supplied visual reference.
class ReferenceIcon extends StatelessWidget {
  const ReferenceIcon(
    this.symbol, {
    super.key,
    required this.size,
    required this.color,
  });

  final ReferenceSymbol symbol;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Image.asset(
    symbol.assetName,
    width: size,
    height: size,
    fit: BoxFit.contain,
    color: color,
    colorBlendMode: BlendMode.srcIn,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}
