import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/strings.dart';
import '../data/native_health.dart';
import '../ui/athlete_avatar.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'metrics.dart';
import 'records.dart';
import 'watch.dart';
import 'profile_editor.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final profile = store.data.profile;
    final details = S.profileDetails(profile);
    final switchProfile = AtletaScope.switchProfileOf(context);
    return Screen(
      background: const DetailBackground(),
      children: [
        const CircleBack(),
        const SizedBox(height: 17),
        const Text(S.profile, style: Design.header),
        const SizedBox(height: 22),
        Align(
          alignment: Alignment.centerLeft,
          child: AthleteAvatar(profile, demo: store.demo, radius: 33),
        ),
        const SizedBox(height: 15),
        if (profile.name.isNotEmpty) ...[
          Text(profile.name, style: Design.section),
          const SizedBox(height: 8),
        ],
        if (details.isNotEmpty) ...[
          Text(details, style: Design.foot),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: () => showProfileEditor(
            context,
            title: S.editProfile,
            current: profile,
            demo: store.demo,
            onSave: store.saveProfile,
          ),
          child: const Text(S.editProfile),
        ),
        if (switchProfile != null)
          OutlinedButton(
            onPressed: switchProfile,
            child: const Text(S.switchProfile),
          ),
        const SizedBox(height: 24),
        if (!store.demo) ...[
          const WatchStatusTile(),
          const SizedBox(height: 8),
        ],
        CompactTile(
          title: S.integration,
          icon: CupertinoIcons.link,
          onTap: () => pushScreen(context, (_) => const IntegrationScreen()),
        ),
        const SizedBox(height: 8),
        CompactTile(
          title: S.manual,
          icon: CupertinoIcons.square_pencil,
          onTap: () => pushScreen(context, (_) => const ManualScreen()),
        ),
        const SizedBox(height: 8),
        CompactTile(
          title: S.readinessHistory,
          icon: CupertinoIcons.gauge,
          onTap: () => pushScreen(context, (_) => const ReadinessHistory()),
        ),
        const SizedBox(height: 8),
        CompactTile(
          title: S.metrics,
          icon: CupertinoIcons.info_circle,
          onTap: () => pushScreen(context, (_) => const MetricInfoScreen()),
        ),
        const SizedBox(height: 15),
        Text(store.demo ? S.demoOnly : S.dataLocal, style: Design.foot),
      ],
    );
  }
}

class IntegrationScreen extends StatelessWidget {
  const IntegrationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final state = store.healthStatus;
    final syncEnabled = store.data.syncEnabled;
    final canRequest = {
      HealthStatus.ready,
      HealthStatus.restricted,
      HealthStatus.empty,
      HealthStatus.synced,
      HealthStatus.failed,
    }.contains(state);
    return Screen(
      background: const DetailBackground(),
      children: [
        const CircleBack(),
        const SizedBox(height: 18),
        const Text(S.integration, style: Design.header),
        const SizedBox(height: 17),
        const SectionTitle(S.healthName),
        const SizedBox(height: 8),
        const Text(S.healthNotice, style: Design.body),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: EmptyCard(store.demo ? S.demoOnly : S.healthStatus(state)),
        ),
        const SizedBox(height: 8),
        Text(
          store.data.lastSync == null
              ? S.noSync
              : S.timestamp(store.data.lastSync!),
          style: Design.foot,
        ),
        const SizedBox(height: 13),
        if (state == HealthStatus.installRequired)
          FilledButton(
            onPressed: () async {
              try {
                await store.health.install();
              } on Exception {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text(S.healthFailed)));
                }
              }
            },
            child: const Text(S.installConnect),
          ),
        if (!store.demo && canRequest)
          FilledButton(
            onPressed: store.syncing ? null : () => store.sync(request: true),
            child: Text(syncEnabled ? S.manage : S.connect),
          ),
        if (syncEnabled) ...[
          const SizedBox(height: 5),
          OutlinedButton(
            onPressed: store.syncing ? null : () => store.sync(),
            child: const Text(S.sync),
          ),
          TextButton(
            onPressed: store.syncing
                ? null
                : () async {
                    try {
                      await store.stopImporting();
                    } on Exception {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text(S.failed)));
                      }
                    }
                  },
            child: const Text(S.disconnect),
          ),
        ],
        const SizedBox(height: 13),
        CompactTile(
          title: S.manual,
          icon: CupertinoIcons.square_pencil,
          onTap: () => pushScreen(context, (_) => const ManualScreen()),
        ),
        const SizedBox(height: 8),
        CompactTile(
          title: S.privacy,
          icon: CupertinoIcons.lock_shield,
          onTap: () => sheet<void>(
            context,
            (_) => const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FormHeading(S.privacy),
                SizedBox(height: 12),
                Text(S.privacyBody, style: Design.body),
              ],
            ),
          ),
        ),
        const SizedBox(height: 13),
        if (store.data.workouts.any((w) => w.origin.imported)) ...[
          const SectionTitle(S.importedSources),
          const SizedBox(height: 10),
          for (final source in <String>{
            for (final w in store.data.workouts.where((w) => w.origin.imported))
              _source(w.origin, w.source),
          })
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: EmptyCard(source),
            ),
        ],
      ],
    );
  }

  String _source(Origin kind, String name) =>
      name.isEmpty ? S.origin(kind) : '${S.origin(kind)} · $name';
}

class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    return Screen(
      background: const DetailBackground(),
      children: [
        const CircleBack(),
        const SizedBox(height: 18),
        const Text(S.manual, style: Design.header),
        const SizedBox(height: 20),
        for (final row in <(String, IconData, VoidCallback)>[
          (
            S.addWorkout,
            CupertinoIcons.sportscourt,
            () => showWorkoutForm(context),
          ),
          (
            S.addReadiness,
            CupertinoIcons.gauge,
            () => editReadinessForDay(context, store),
          ),
          (S.markRest, CupertinoIcons.calendar, () => showRestForm(context)),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CompactTile(title: row.$1, icon: row.$2, onTap: row.$3),
          ),
      ],
    );
  }
}

class MetricInfoScreen extends StatelessWidget {
  const MetricInfoScreen({super.key});
  @override
  Widget build(BuildContext context) => const Screen(
    background: DetailBackground(),
    children: [
      CircleBack(),
      SizedBox(height: 18),
      Text(S.metrics, style: Design.header),
      SizedBox(height: 24),
      SectionTitle(S.readiness),
      SizedBox(height: 7),
      Text(S.readinessMethod, style: Design.body),
      SizedBox(height: 4),
      Text(S.readinessBands, style: Design.foot),
      SizedBox(height: 20),
      SectionTitle(S.load),
      SizedBox(height: 7),
      Text(S.loadInfo, style: Design.body),
      SizedBox(height: 4),
      Text(S.loadRules, style: Design.body),
    ],
  );
}

class ReadinessHistory extends StatelessWidget {
  const ReadinessHistory({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final entries = store.data.readiness;
    return Screen(
      background: const DetailBackground(),
      children: [
        const CircleBack(),
        const SizedBox(height: 18),
        const Text(S.readinessHistory, style: Design.header),
        const SizedBox(height: 17),
        FilledButton(
          onPressed: () => editReadinessForDay(context, store),
          child: const Text(S.addReadiness),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty) EmptyCard(S.readinessNoHistory),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CompactTile(
              title: '${entry.score}% · ${S.readinessLabel(entry.score)}',
              subtitle:
                  '${S.day(entry.day)} · ${entry.origin == Origin.manual ? S.readinessSource : S.origin(entry.origin)}',
              icon: CupertinoIcons.gauge,
              onTap: () => showReadinessForm(context, chosenDay: entry.day),
            ),
          ),
      ],
    );
  }
}
