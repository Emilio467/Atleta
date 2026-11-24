import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models.dart';
import '../core/strings.dart';
import '../data/repository.dart';
import '../ui/athlete_avatar.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'records.dart';

Future<void> showProfileEditor(
  BuildContext context, {
  required String title,
  required Future<void> Function(AthleteProfile) onSave,
  String label = S.save,
  AthleteProfile current = const AthleteProfile(),
  bool demo = false,
}) async {
  var name = current.name;
  var photo = current.photo;
  var height = current.heightCm?.toString() ?? '';
  var weight = current.weightKg?.toString() ?? '';
  var birth = current.birthYear?.toString() ?? '';
  var stepLength = current.stepLengthCm?.toString() ?? '';
  final thisYear = DateTime.now().year;
  String? photoError;
  var picking = false;

  await sheet<void>(
    context,
    (_) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> pickPhoto() async {
          setState(() {
            picking = true;
            photoError = null;
          });
          try {
            final selected = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 384,
              maxHeight: 384,
              imageQuality: 82,
            );
            if (selected == null || !context.mounted) return;
            if (await selected.length() > 2 * 1024 * 1024) {
              if (context.mounted) setState(() => photoError = S.photoMax);
              return;
            }
            final next = await _encodePhoto(await selected.readAsBytes());
            if (context.mounted) setState(() => photo = next);
          } on Exception {
            if (context.mounted) setState(() => photoError = S.photoError);
          } finally {
            if (context.mounted) setState(() => picking = false);
          }
        }

        return EntryForm(
          title: title,
          label: label,
          fields: [
            input(
              label: S.name,
              initial: name,
              onChange: (value) => name = value,
              maxLength: 48,
              validator: requiredText,
            ),
            const Text(S.optionalProfileFields, style: Design.foot),
            input(
              label: S.heightCm,
              initial: height,
              onChange: (value) => height = value,
              number: true,
              decimal: true,
              maxLength: 8,
              validator: (value) =>
                  _inRange(value, 30, 300) ? null : S.heightInvalid,
            ),
            input(
              label: S.weightKg,
              initial: weight,
              onChange: (value) => weight = value,
              number: true,
              decimal: true,
              maxLength: 8,
              validator: (value) =>
                  _inRange(value, 1, 700) ? null : S.weightInvalid,
            ),
            input(
              label: S.birthYear,
              initial: birth,
              onChange: (value) => birth = value,
              number: true,
              maxLength: 4,
              validator: (value) {
                final year = int.tryParse(value ?? '');
                if ((value ?? '').isEmpty ||
                    (year != null && year >= 1900 && year <= thisYear)) {
                  return null;
                }
                return S.birthYearInvalid;
              },
            ),
            Row(
              children: [
                AthleteAvatar(
                  AthleteProfile(name: name, photo: photo),
                  demo: demo,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      OutlinedButton(
                        onPressed: picking ? null : pickPhoto,
                        child: const Text(S.choosePhoto),
                      ),
                      if (photo.isNotEmpty)
                        TextButton(
                          onPressed: picking
                              ? null
                              : () => setState(() => photo = ''),
                          child: const Text(S.removePhoto),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (photoError case final error?)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            input(
              label: S.stepLengthCm,
              initial: stepLength,
              onChange: (value) => stepLength = value,
              number: true,
              decimal: true,
              maxLength: 8,
              validator: (value) =>
                  _inRange(value, 10, 250) ? null : S.stepLengthInvalid,
            ),
          ],
          onSave: () async {
            try {
              await onSave(
                AthleteProfile(
                  name: name.trim(),
                  photo: photo,
                  heightCm: _decimal(height),
                  weightKg: _decimal(weight),
                  birthYear: int.tryParse(birth),
                  stepLengthCm: _decimal(stepLength),
                ),
              );
            } on ProfileNameInUse {
              throw const ValidationIssue(S.profileNameInUse);
            }
          },
        );
      },
    ),
  );
}

double? _decimal(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

bool _inRange(String? text, double min, double max) {
  if (text == null || text.trim().isEmpty) return true;
  final amount = _decimal(text);
  return amount != null && amount >= min && amount <= max;
}

Future<String> _encodePhoto(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 288,
    allowUpscaling: false,
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const ValidationIssue(S.photoError);
      return base64Encode(data.buffer.asUint8List());
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
