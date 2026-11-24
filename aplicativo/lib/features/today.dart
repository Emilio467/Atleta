import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../ui/athlete_avatar.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'profile.dart';
import 'records.dart';
import 'watch.dart';
import 'workouts.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.onOpenWorkout});

  final VoidCallback onOpenWorkout;

  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final today = store.today;
    final readiness = store.readinessOn(today);
    final latest = store.data.workouts.firstOrNull;
    return Screen(
      background: const DashboardBackground(),
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 13,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(S.today, style: Design.header),
                  Text(
                    S.shortDay(today),
                    style: Design.section.copyWith(color: Palette.muted),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('avatar'),
              tooltip: S.profile,
              onPressed: () =>
                  pushScreen(context, (_) => const ProfileScreen()),
              padding: EdgeInsets.zero,
              icon: AthleteAvatar(
                store.data.profile,
                demo: store.demo,
                radius: 23,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        ListenableBuilder(
          listenable: store.watch,
          builder: (context, _) {
            final watch = store.watch;
            final draft = store.data.watchDraft;
            final session = store.data.session;
            final packet = draft == null
                ? null
                : draft.result ?? watch.latestFor(draft.token);
            final hasWorkout = draft != null || session != null;
            final connected = watch.connected;
            final status = switch ((draft, session, connected, packet)) {
              (_, _, _, final reading?) when reading.finished => S.m5Stopped,
              (_, final local?, _, _) =>
                local.activeSince == null ? S.paused : S.running,
              (final pending?, _, false, _) when pending.result == null =>
                S.lostConnection,
              (final pending?, _, true, final reading?)
                  when pending.result == null && !reading.running =>
                S.paused,
              (_, _, true, _) => S.m5Connected,
              _ => S.m5Disconnected,
            };
            final seconds = packet == null
                ? null
                : watch.activeSecondsForDisplay(packet);
            final steps = packet?.steps;
            return DashboardPanel(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.watch_outlined,
                    size: 69,
                    color: Palette.lime,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    session == null ? S.m5Watch : S.running,
                    style: Design.section.copyWith(fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 7,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: connected ? Palette.lime : Palette.muted,
                      ),
                      Text(status, style: Design.foot.copyWith(fontSize: 14)),
                    ],
                  ),
                  if (seconds != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      [
                        S.stopwatch(seconds),
                        if (steps != null) '${S.number(steps)} ${S.stepsUnit}',
                      ].join(' · '),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: Design.mono,
                        fontSize: 17,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const ValueKey('today-watch-action'),
                    style: Design.dashboardButton,
                    onPressed: store.demo
                        ? null
                        : hasWorkout || connected
                        ? onOpenWorkout
                        : () => showWatchConnection(
                            context,
                            onConnected: onOpenWorkout,
                          ),
                    child: Text(
                      hasWorkout || connected ? S.viewWorkout : S.connectM5,
                    ),
                  ),
                  if (!hasWorkout && !connected) ...[
                    const SizedBox(height: 9),
                    const Text(
                      S.watchStartHint,
                      textAlign: TextAlign.center,
                      style: Design.foot,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text(S.latestWorkout, style: Design.dashboardSection),
        const SizedBox(height: 10),
        if (latest != null)
          WorkoutTile(
            latest,
            onTap: () =>
                pushScreen(context, (_) => WorkoutScreen(id: latest.id)),
          )
        else
          const EmptyCard(S.noWorkouts),
        const SizedBox(height: 20),
        const Text(S.readiness, style: Design.dashboardSection),
        const SizedBox(height: 10),
        CompactTile(
          title: readiness == null
              ? S.dashboardRegister
              : '${readiness.score}%',
          icon: Icons.assignment_outlined,
          radius: 15,
          accent: Palette.lime,
          onTap: () => showReadinessForm(context),
        ),
      ],
    );
  }
}
