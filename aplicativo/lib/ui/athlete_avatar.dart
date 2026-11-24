import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

class AthleteAvatar extends StatelessWidget {
  const AthleteAvatar(
    this.profile, {
    super.key,
    this.demo = false,
    this.radius = 22,
  });
  final AthleteProfile profile;
  final bool demo;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFF244626),
    foregroundColor: Palette.text,
    foregroundImage: profile.photo.isNotEmpty
        ? MemoryImage(base64Decode(profile.photo))
        : demo
        ? const AssetImage('assets/demo-avatar.png')
        : null,
    child: profile.photo.isNotEmpty || demo
        ? null
        : profile.name.isEmpty
        ? const Icon(CupertinoIcons.person_fill, size: 23)
        : Text(
            String.fromCharCode(profile.name.runes.first).toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
  );
}
