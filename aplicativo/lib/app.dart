import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sembast/sembast.dart';

import 'core/controller.dart';
import 'core/models.dart';
import 'core/strings.dart';
import 'features/metrics.dart';
import 'features/progress.dart';
import 'features/profile_picker.dart';
import 'data/repository.dart';
import 'features/today.dart';
import 'features/workouts.dart';
import 'ui/components.dart';
import 'ui/theme.dart';

class AtletaApp extends StatefulWidget {
  const AtletaApp({
    super.key,
    required this.load,
    this.scene = '',
    this.capture = false,
  }) : openDatabase = null;

  const AtletaApp.local({super.key, required this.openDatabase})
    : load = null,
      scene = '',
      capture = false;

  final Future<AtletaController> Function()? load;
  final Future<Database> Function()? openDatabase;
  final String scene;
  final bool capture;

  @override
  State<AtletaApp> createState() => _AtletaAppState();
}

class _AtletaAppState extends State<AtletaApp> {
  late Future<void> _boot;
  Database? _database;
  LocalProfilesRepository? _directory;
  AtletaController? _controller;

  @override
  void initState() {
    super.initState();
    _boot = _start();
  }

  Future<void> _start() async {
    if (widget.openDatabase case final open?) {
      final db = await open();
      final directory = LocalProfilesRepository(db);
      try {
        await directory.initialize();
      } catch (_) {
        await db.close();
        rethrow;
      }
      if (!mounted) {
        await db.close();
        return;
      }
      _database = db;
      _directory = directory;
    } else {
      final controller = await widget.load!();
      final db = controller.repository.db;
      if (!mounted) {
        controller.dispose();
        await db.close();
        return;
      }
      _database = db;
      _controller = controller;
    }
  }

  Future<void> _openProfile(String id) async {
    final repo = await _directory!.trainingFor(id);
    final controller = AtletaController(repo);
    try {
      await controller.initialize();
    } catch (_) {
      controller.dispose();
      rethrow;
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  void _switchProfile() {
    final current = _controller;
    setState(() => _controller = null);
    current?.dispose();
  }

  @override
  void dispose() {
    _controller?.dispose();
    if (_database case final db?) unawaited(db.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: S.app,
    debugShowCheckedModeBanner: false,
    theme: Design.theme(),
    home: FutureBuilder<void>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(S.openFailed),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () => setState(() => _boot = _start()),
                          child: const Text(S.retry),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(
                      semanticsLabel: S.chartLoading,
                    ),
            ),
          );
        }
        if (_controller case final controller?) {
          return AtletaScope(
            key: ObjectKey(controller),
            store: controller,
            onSwitchProfile: _directory == null ? null : _switchProfile,
            child: _TabShell(
              store: controller,
              scene: widget.scene,
              capture: widget.capture,
            ),
          );
        }
        return ProfilePicker(directory: _directory!, onOpen: _openProfile);
      },
    ),
  );
}

class _TabShell extends StatefulWidget {
  const _TabShell({
    required this.store,
    required this.scene,
    required this.capture,
  });
  final AtletaController store;
  final String scene;
  final bool capture;

  @override
  State<_TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<_TabShell> with WidgetsBindingObserver {
  int _active = 0;
  final _keys = List.generate(3, (_) => GlobalKey<NavigatorState>());
  Timer? _clock;
  DateTime? _day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _day = dayOf(widget.store.now());
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      final day = dayOf(widget.store.now());
      if (_day == day) return;
      _day = day;
      widget.store.onResume();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.store.onResume();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.store.onResume();
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<Route<void>> _routes(int tab) {
    final scene = tab == 0 && widget.store.demo ? widget.scene : '';
    return [
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/'),
        builder: (_) => switch (tab) {
          0 => TodayScreen(onOpenWorkout: _openWorkoutTab),
          1 => const ProgressScreen(),
          _ => const WorkoutsScreen(),
        },
      ),
      if (scene == 'load')
        MaterialPageRoute<void>(builder: (_) => const LoadScreen()),
    ];
  }

  void _select(int index) {
    if (_active == index) {
      _keys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _active = index);
    }
  }

  void _openWorkoutTab() {
    if (!mounted) return;
    _keys[2].currentState?.popUntil((route) => route.isFirst);
    _select(2);
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Design.maxWidth),
          child: Stack(
            fit: StackFit.expand,
            children: [
              IndexedStack(
                index: _active,
                sizing: StackFit.expand,
                children: [
                  for (final (index, key) in _keys.indexed)
                    TickerMode(
                      enabled: _active == index,
                      child: NavigatorPopHandler<void>(
                        enabled: _active == index,
                        onPopWithResult: (_) => key.currentState?.pop(),
                        child: Navigator(
                          key: key,
                          onGenerateInitialRoutes: (_, _) => _routes(index),
                        ),
                      ),
                    ),
                ],
              ),
              if (!keyboard)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: math.max(safe.bottom + 10, 24),
                  child: BottomNav(index: _active, onTap: _select),
                ),
              if (widget.store.demo && !widget.capture)
                Positioned(
                  top: kIsWeb ? 7 : safe.top + 1,
                  right: 15,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Palette.background.withValues(alpha: .8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Text(
                          S.demo,
                          style: TextStyle(fontSize: 10, color: Palette.muted),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
