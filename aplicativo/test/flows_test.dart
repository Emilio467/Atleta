import 'package:atleta/app.dart';
import 'package:atleta/core/controller.dart';
import 'package:atleta/core/models.dart';
import 'package:atleta/core/strings.dart';
import 'package:atleta/data/native_health.dart';
import 'package:atleta/data/repository.dart';
import 'package:atleta/ui/metric_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;

class OfflineHealth extends NativeHealth {
  @override
  Future<HealthStatus> status() async => HealthStatus.unsupported;
}

Future<AtletaController> loadApp(
  WidgetTester tester, {
  bool demo = false,
  DateTime Function()? clock,
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  late AtletaController store;
  await tester.runAsync(() async {
    final db = await newDatabaseFactoryMemory().openDatabase(
      demo ? 'demo' : 'normal',
    );
    store = AtletaController(
      AtletaRepository(db),
      demo: demo,
      clock: clock,
      health: OfflineHealth(),
    );
    await store.initialize();
  });
  await tester.pumpWidget(AtletaApp(load: () async => store, capture: true));
  await tester.pumpAndSettle();
  return store;
}

Finder label(String text) => find.text(text).hitTestable();
Future<void> tap(WidgetTester t, Finder target) async {
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> tab(WidgetTester t, int index) =>
    tap(t, find.byKey(ValueKey('tab-$index')));

Future<void> scrollTo(WidgetTester t, Finder target) async {
  await t.scrollUntilVisible(
    target,
    140,
    scrollable: find.byType(Scrollable).hitTestable().first,
  );
  await t.pumpAndSettle();
}

Finder _fieldByLabel(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

Future<void> enter(WidgetTester t, String label, String value) async {
  await t.enterText(_fieldByLabel(label).last, value);
  await t.pumpAndSettle();
}

Future<void> effort(WidgetTester t, int value) async {
  final dropdown = find.byType(DropdownButtonFormField<int>).hitTestable();
  await t.ensureVisible(dropdown);
  await tap(t, dropdown);
  await tap(t, label(value.toString()).last);
}

Future<void> save(WidgetTester t) async {
  final button = label(S.save);
  await t.ensureVisible(button);
  await t.runAsync(() async {
    await t.tap(button);
    await Future<void>.delayed(const Duration(milliseconds: 35));
  });
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Workouts lists all dates and clears history only after confirmation',
    (tester) async {
      final now = DateTime(2026, 11, 16, 13);
      final old = now.subtract(const Duration(days: 20));
      final store = await loadApp(tester, clock: () => now);
      await tester.runAsync(() async {
        for (final (id, activity, start) in [
          ('today', 'Walking', now),
          ('old', 'Cycling', old),
        ]) {
          await store.saveWorkout(
            Workout(
              id: id,
              activity: activity,
              start: start,
              seconds: 60,
              origin: Origin.manual,
              created: start,
              updated: start,
            ),
          );
        }
      });
      await tester.pumpAndSettle();
      await tab(tester, 1);
      expect(find.text(S.workoutHistory), findsNothing);
      expect(label(S.clearHistory), findsNothing);
      await tab(tester, 2);
      await scrollTo(tester, find.text(S.workoutHistory));
      expect(find.text('Caminhada'), findsOneWidget);
      expect(find.text('Ciclismo'), findsOneWidget);
      await tap(tester, find.byTooltip(S.historyOptions));
      await tap(tester, label(S.clearHistory));
      expect(find.text(S.clearHistoryTitle), findsOneWidget);
      await tap(tester, label(S.cancel));
      expect(store.data.workouts, hasLength(2));

      await tap(tester, find.byTooltip(S.historyOptions));
      await tap(tester, label(S.clearHistory));
      final confirm = find.widgetWithText(FilledButton, S.clearHistory);
      await tap(tester, confirm);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
      expect(store.data.workouts, isEmpty);
      expect(find.text(S.noWorkouts), findsOneWidget);
    },
  );

  testWidgets('Today, load chart selection, period changes and tab history', (
    tester,
  ) async {
    await loadApp(tester, demo: true);
    expect(find.text('14 dez'), findsOneWidget);
    await tab(tester, 1);
    await scrollTo(tester, find.byKey(const ValueKey('open-load')));
    await tap(tester, find.byKey(const ValueKey('open-load')));
    expect(find.text('0.98'), findsOneWidget);
    expect(find.text('Nov 7, 2025'), findsOneWidget);
    final plot = find.byType(MetricChart).hitTestable();
    final box = tester.getRect(plot);
    await tester.tapAt(Offset(box.left + 37, box.top + 125));
    await tester.pumpAndSettle();
    expect(find.text('Nov 7, 2025'), findsNothing);
    await tap(tester, find.byTooltip(S.back));
    await tab(tester, 1);
    await tap(tester, label('30 dias'));
    expect(find.text('15 nov – 14 dez'), findsOneWidget);
    await tap(tester, label(S.load));
    expect(find.text('0.98'), findsOneWidget);
    await tap(tester, find.byTooltip(S.back));
    expect(find.text(S.progress), findsWidgets);
    await tab(tester, 0);
  });

  testWidgets('normal app logs, edits, reports and deletes a local workout', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 16, 13);
    final store = await loadApp(tester, clock: () => now);
    expect(find.text(S.noWorkouts), findsOneWidget);
    await tab(tester, 2);
    await tap(tester, find.byKey(const ValueKey('add-workout')));
    await enter(tester, S.activity, 'Running');
    await enter(tester, S.durationInput, '30');
    await effort(tester, 6);
    await save(tester);
    expect(store.data.workouts.single.seconds, 1800);
    await tab(tester, 0);
    expect(find.text('Corrida'), findsOneWidget);
    await tab(tester, 2);
    await tap(tester, label('Corrida'));
    await tap(tester, label(S.editWorkout));
    await enter(tester, S.durationInput, '45');
    await save(tester);
    expect(store.data.workouts.single.seconds, 2700);
    await tab(tester, 1);
    expect(find.text('45 min'), findsOneWidget);
    await tab(tester, 2);
    await scrollTo(tester, label(S.deleteWorkout));
    await tap(tester, label(S.deleteWorkout));
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, S.deleteWorkout),
    );
    await tap(tester, confirm);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();
    expect(store.data.workouts, isEmpty);
    await tab(tester, 1);
    expect(find.text('0s'), findsOneWidget);
  });

  testWidgets(
    'timer pause/resume/finish, daily readiness, and unsupported integration',
    (tester) async {
      var now = DateTime(2026, 11, 16, 13);
      final store = await loadApp(tester, clock: () => now);
      await tap(tester, label(S.dashboardRegister));
      await enter(tester, S.readiness, '73');
      await save(tester);
      expect(find.text('73%'), findsOneWidget);
      await tab(tester, 2);
      await tap(tester, label(S.startSession));
      await tester.runAsync(() async {
        await tester.tap(label(S.startSession).last);
        await Future<void>.delayed(const Duration(milliseconds: 35));
      });
      await tester.pumpAndSettle();
      expect(store.data.session, isNotNull);
      now = now.add(const Duration(seconds: 60));
      await tester.runAsync(() async {
        await tester.tap(label(S.pause));
        await Future<void>.delayed(const Duration(milliseconds: 35));
      });
      await tester.pumpAndSettle();
      expect(store.data.session!.activeSince, isNull);
      now = now.add(const Duration(hours: 1));
      await tester.runAsync(() async {
        await tester.tap(label(S.resume));
        await Future<void>.delayed(const Duration(milliseconds: 35));
      });
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 30));
      await tap(tester, label(S.finish));
      await effort(tester, 4);
      await save(tester);
      expect(store.data.workouts.single.seconds, 90);
      expect(store.data.session, isNull);
      await tab(tester, 0);
      await tap(tester, find.byKey(const ValueKey('avatar')));
      await tap(tester, label(S.integration));
      expect(find.text(S.healthUnsupported), findsOneWidget);
    },
  );

  testWidgets(
    'small viewport with large type preserves navigation and scroll',
    (tester) async {
      await loadApp(tester, demo: true, size: const Size(320, 660), scale: 1.6);
      expect(tester.takeException(), isNull);
      await tab(tester, 1);
      await scrollTo(tester, find.byKey(const ValueKey('open-load')));
      await tap(tester, find.byKey(const ValueKey('open-load')));
      expect(tester.takeException(), isNull);
      expect(find.byTooltip(S.back), findsOneWidget);
      await tab(tester, 2);
      expect(tester.takeException(), isNull);
      await tab(tester, 1);
      await tap(tester, find.byTooltip(S.back));
      await tester.scrollUntilVisible(
        find.text('90 dias'),
        -150,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
      await tester.pumpAndSettle();
      await tap(tester, label('90 dias'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Progress rolls up M5 steps by day and selects chart points', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 17, 13);
    final store = await loadApp(tester, clock: () => now);
    await tester.runAsync(() async {
      for (final (id, daysAgo, steps) in [
        ('yesterday', 1, 600),
        ('today-am', 0, 700),
        ('today-pm', 0, 800),
        ('last-week', 12, 900),
      ]) {
        final time = now.subtract(
          Duration(days: daysAgo, hours: id == 'today-am' ? 2 : 0),
        );
        await store.saveWorkout(
          Workout(
            id: id,
            activity: 'Walking',
            start: time,
            seconds: 360,
            origin: Origin.m5,
            created: time,
            updated: time,
            watchStats: WatchStats(steps: steps, distanceKm: steps * .0007),
          ),
        );
      }
    });
    await tester.pumpAndSettle();
    await tab(tester, 1);
    expect(find.text('2.100'), findsOneWidget);
    expect(find.text('1,47 km'), findsOneWidget);
    expect(find.text('17 nov · 1.500 passos'), findsOneWidget);
    final bounds = tester.getRect(find.byType(MetricChart).hitTestable());
    await tester.tapAt(Offset(bounds.right - 65, bounds.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('16 nov · 600 passos'), findsOneWidget);
    await tap(tester, label('30 dias'));
    expect(find.text('3.000'), findsOneWidget);
    expect(find.text('17 nov · 1.500 passos'), findsOneWidget);
  });
}
