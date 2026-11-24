import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../data/repository.dart';
import '../ui/athlete_avatar.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'metrics.dart';
import 'profile_editor.dart';

class ProfilePicker extends StatefulWidget {
  const ProfilePicker({
    super.key,
    required this.directory,
    required this.onOpen,
  });

  final LocalProfilesRepository directory;
  final Future<void> Function(String) onOpen;

  @override
  State<ProfilePicker> createState() => _ProfilePickerState();
}

class _ProfilePickerState extends State<ProfilePicker> {
  late Future<List<LocalProfile>> _profiles = widget.directory.list();
  bool _busy = false;
  String? _error;

  Future<void> _select(LocalProfile choice) async {
    if (_busy) return;
    if (choice.profile.name.trim().isEmpty) {
      await showProfileEditor(
        context,
        title: S.nameExistingProfile,
        label: S.continueProfile,
        current: choice.profile,
        onSave: (profile) async {
          final repo = await widget.directory.trainingFor(choice.id);
          await repo.putProfile(profile);
          await widget.onOpen(choice.id);
        },
      );
      if (mounted) setState(() => _profiles = widget.directory.list());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onOpen(choice.id);
    } on Exception {
      if (mounted) setState(() => _error = S.openProfileFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    String? created;
    await showProfileEditor(
      context,
      title: S.createProfile,
      label: S.continueProfile,
      onSave: (profile) async {
        final id = created;
        if (id == null) {
          created = await widget.directory.create(profile);
        } else {
          final repo = await widget.directory.trainingFor(id);
          await repo.putProfile(profile);
        }
        await widget.onOpen(created!);
      },
    );
    if (mounted) setState(() => _profiles = widget.directory.list());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Design.maxWidth),
        child: Screen(
          background: const DetailBackground(),
          children: [
            const Text(S.app, style: Design.label),
            const SizedBox(height: 18),
            const Text(S.chooseProfile, style: Design.header),
            const SizedBox(height: 11),
            const Text(S.profileHelp, style: Design.body),
            const SizedBox(height: 24),
            FutureBuilder<List<LocalProfile>>(
              future: _profiles,
              builder: (context, result) {
                if (result.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const EmptyCard(S.openFailed),
                      TextButton(
                        onPressed: () =>
                            setState(() => _profiles = widget.directory.list()),
                        child: const Text(S.retry),
                      ),
                    ],
                  );
                }
                if (!result.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  children: [
                    for (final choice in result.requireData) ...[
                      Material(
                        color: Palette.surface,
                        borderRadius: BorderRadius.circular(Design.card),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          key: ValueKey(choice.id),
                          leading: AthleteAvatar(choice.profile, radius: 20),
                          title: Text(
                            choice.profile.name.trim().isEmpty
                                ? S.localHistory
                                : choice.profile.name,
                          ),
                          subtitle: S.profileDetails(choice.profile).isEmpty
                              ? null
                              : Text(S.profileDetails(choice.profile)),
                          trailing: const Icon(
                            CupertinoIcons.chevron_right,
                            size: 16,
                          ),
                          onTap: _busy ? null : () => _select(choice),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_error case final message?) ...[
                      Semantics(liveRegion: true, child: EmptyCard(message)),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: const Icon(CupertinoIcons.plus, size: 18),
                        label: const Text(S.createProfile),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
