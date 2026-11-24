import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller.dart';
import '../core/models.dart';
import '../core/strings.dart';
import '../data/repository.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

typedef FormAction = Future<void> Function();

class EntryForm extends StatefulWidget {
  const EntryForm({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    this.label = S.save,
    this.success = S.saved,
    this.afterSave,
  });
  final String title, label, success;
  final List<Widget> fields;
  final FormAction onSave;
  final VoidCallback? afterSave;

  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final formKey = GlobalKey<FormState>();
  bool saving = false;
  String? error;

  Future<void> _save() async {
    if (saving || !formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final afterSave = widget.afterSave;
      navigator.pop();
      afterSave?.call();
      messenger.showSnackBar(SnackBar(content: Text(widget.success)));
    } on ValidationIssue catch (issue) {
      if (mounted) setState(() => error = issue.message);
    } on DuplicateRecord {
      if (mounted) setState(() => error = S.duplicate);
    } on WorkoutInProgress {
      if (mounted) setState(() => error = S.m5Busy);
    } on Exception {
      if (mounted) setState(() => error = S.failed);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormHeading(widget.title),
          const SizedBox(height: 19),
          for (final field in widget.fields) ...[
            field,
            const SizedBox(height: 13),
          ],
          if (error case final errorText?) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                errorText,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.label),
          ),
        ],
      ),
    ),
  );
}

class ValidationIssue implements Exception {
  const ValidationIssue(this.message);
  final String message;
}

Widget input({
  required String label,
  required ValueChanged<String> onChange,
  String? initial,
  String? Function(String?)? validator,
  bool number = false,
  bool decimal = false,
  int? maxLength,
  int lines = 1,
}) => TextFormField(
  initialValue: initial,
  onChanged: onChange,
  validator: validator,
  keyboardType: number
      ? TextInputType.numberWithOptions(decimal: decimal)
      : TextInputType.text,
  maxLength: maxLength,
  maxLines: lines,
  inputFormatters: number && !decimal
      ? [FilteringTextInputFormatter.digitsOnly]
      : [],
  decoration: InputDecoration(labelText: label, counterText: ''),
);

String? requiredText(String? value) =>
    (value?.trim().isEmpty ?? true) ? S.required : null;
int? durationSeconds(String? text) {
  final parsed = double.tryParse((text ?? '').trim().replaceAll(',', '.'));
  if (parsed == null || !parsed.isFinite || parsed <= 0 || parsed > 1440) {
    return null;
  }
  final seconds = (parsed * 60).round();
  return seconds == 0 ? null : seconds;
}

Future<DateTime?> chooseDate(
  BuildContext context,
  DateTime initial,
  DateTime now,
) => showDatePicker(
  context: context,
  initialDate: initial.isAfter(now) ? now : initial,
  firstDate: DateTime(1970),
  lastDate: now,
);

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.now,
    required this.onChanged,
    this.withTime = false,
  });
  final String label;
  final DateTime value, now;
  final ValueChanged<DateTime> onChanged;
  final bool withTime;

  Future<void> _date(BuildContext context) async {
    final date = await chooseDate(context, value, now);
    if (date != null) {
      onChanged(
        DateTime(date.year, date.month, date.day, value.hour, value.minute),
      );
    }
  }

  Future<void> _time(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time != null) {
      onChanged(
        DateTime(value.year, value.month, value.day, time.hour, time.minute),
      );
    }
  }

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
    ),
    child: Wrap(
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: () => _date(context),
          icon: const Icon(CupertinoIcons.calendar, size: 18),
          label: Text(S.day(value)),
        ),
        if (withTime)
          TextButton.icon(
            onPressed: () => _time(context),
            icon: const Icon(CupertinoIcons.clock, size: 18),
            label: Text(S.clock(value)),
          ),
      ],
    ),
  );
}

class EffortField extends StatelessWidget {
  const EffortField({super.key, required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value,
    onChanged: onChanged,
    isExpanded: true,
    decoration: const InputDecoration(labelText: S.effortInput),
    validator: (value) => value == null ? S.required : null,
    items: [
      for (var effort = 0; effort <= 10; effort++)
        DropdownMenuItem(value: effort, child: Text(effort.toString())),
    ],
  );
}

Future<void> showWorkoutForm(
  BuildContext context, {
  Workout? original,
  Session? session,
}) async {
  final store = AtletaScope.of(context);
  final finishedAt = store.now();
  var start =
      original?.start.toLocal() ??
      session?.started.toLocal() ??
      (store.demo
          ? DateTime(store.today.year, store.today.month, store.today.day, 9)
          : finishedAt.subtract(const Duration(hours: 1)));
  final sessionSeconds = session?.elapsed(finishedAt).inSeconds;
  var activity = original?.activity ?? session?.activity ?? '';
  var duration = original == null
      ? ''
      : (original.seconds / 60)
            .toStringAsFixed(4)
            .replaceFirst(RegExp(r'\.?0+$'), '');
  var effort = original?.effort;
  var notes = original?.notes ?? '';
  final imported = original?.origin.imported == true;
  if (session != null && sessionSeconds! <= 0) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(S.durationInvalid)));
    return;
  }
  await sheet<void>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) {
        return EntryForm(
          title: session != null
              ? S.finishSession
              : imported
              ? S.adjustEffort
              : original != null
              ? S.editWorkout
              : S.addWorkout,
          fields: [
            if (imported) const Text(S.importedLocked, style: Design.foot),
            if (!imported && session == null) ...[
              input(
                label: S.activity,
                initial: activity,
                maxLength: 48,
                onChange: (value) => activity = value,
                validator: requiredText,
              ),
              DateField(
                label: S.startTime,
                value: start,
                now: store.now(),
                withTime: true,
                onChanged: (value) => setState(() => start = value),
              ),
              input(
                label: S.durationInput,
                initial: duration,
                number: true,
                decimal: true,
                onChange: (value) => duration = value,
                validator: (text) =>
                    durationSeconds(text) == null ? S.durationInvalid : null,
              ),
            ],
            if (session != null)
              Text(
                '$activity · ${S.durationLabel(sessionSeconds!)}',
                style: Design.body,
              ),
            EffortField(value: effort, onChanged: (value) => effort = value),
            if (!imported)
              input(
                label: S.optionalNotes,
                initial: notes,
                lines: 3,
                maxLength: 500,
                onChange: (value) => notes = value,
              ),
          ],
          onSave: () async {
            final now = store.now();
            if (imported) {
              await store.setImportedEffort(original!.id, effort!);
              return;
            }
            final seconds = sessionSeconds ?? durationSeconds(duration)!;
            if (start.add(Duration(seconds: seconds)).isAfter(now)) {
              throw const ValidationIssue(S.future);
            }

            final workout = Workout(
              id: original?.id ?? session?.id ?? newId(),
              activity: activity.trim(),
              start: start,
              seconds: seconds,
              notes: notes.trim(),
              effort: effort,
              origin:
                  original?.origin ??
                  (session == null ? Origin.manual : Origin.timer),
              created: original?.created ?? now,
              updated: now,
              source: original?.source ?? '',
              watchStats: original?.watchStats,
            );
            if (session != null) {
              await store.finishSession(workout);
            } else {
              await store.saveWorkout(workout);
            }
          },
        );
      },
    ),
  );
}

Future<void> showStartSession(BuildContext context) async {
  final store = AtletaScope.of(context);
  var activity = S.exerciseList.first;
  await sheet<void>(
    context,
    (_) => EntryForm(
      title: S.startSession,
      label: S.startSession,
      fields: [
        DropdownButtonFormField<String>(
          initialValue: activity,
          isExpanded: true,
          decoration: const InputDecoration(labelText: S.activity),
          items: [
            for (final type in S.exerciseList)
              DropdownMenuItem(value: type, child: Text(S.activityName(type))),
          ],
          onChanged: (value) => activity = value ?? activity,
        ),
      ],
      onSave: () => store.begin(activity),
    ),
  );
}

Future<void> showReadinessForm(
  BuildContext context, {
  DateTime? chosenDay,
}) async {
  final store = AtletaScope.of(context);
  final day = chosenDay ?? store.today;
  final initial = store.readinessOn(day);
  String score = initial?.score.toString() ?? '';
  await sheet<void>(
    context,
    (_) => EntryForm(
      title: initial == null ? S.addReadiness : S.editReadiness,
      fields: [
        const Text(S.readinessInput, style: Design.body),
        Text(S.day(day), style: Design.foot),
        input(
          label: S.readiness,
          initial: score,
          onChange: (value) => score = value,
          number: true,
          validator: (text) {
            final value = int.tryParse(text ?? '');
            return value == null || value > 100 ? S.readinessInvalid : null;
          },
        ),
        const Text(S.readinessMethod, style: Design.foot),
      ],
      onSave: () => store.saveReadiness(
        ReadinessEntry(day, int.parse(score), store.now()),
      ),
    ),
  );
}

Future<void> showRestForm(BuildContext context, {DateTime? selected}) async {
  final store = AtletaScope.of(context);
  var date = selected ?? store.today;
  await sheet<void>(
    context,
    (_) => StatefulBuilder(
      builder: (context, setState) {
        final exists = store.data.rest.contains(dayKey(date));
        return EntryForm(
          title: S.markRest,
          label: exists ? S.undoRest : S.confirmRest,
          fields: [
            const Text(S.restHelp, style: Design.body),
            DateField(
              label: S.date,
              value: date,
              now: store.now(),
              onChanged: (value) => setState(() => date = value),
            ),
          ],
          onSave: () => store.saveRest(date, !exists),
        );
      },
    ),
  );
}

Future<void> editReadinessForDay(
  BuildContext context,
  AtletaController store,
) async {
  final day = await chooseDate(context, store.today, store.now());
  if (day != null && context.mounted) {
    await showReadinessForm(context, chosenDay: day);
  }
}
