import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_store.dart';
import '../data/planning_adapter.dart';
import '../data/bake_replan.dart';
import '../data/starter_routine.dart';
import 'plan_review_screen.dart';
import 'kitchen_calculator.dart';
import 'bake_coach_screen.dart';
import 'starter_insights_screen.dart';
import 'journal_book_screen.dart';
import 'private_recipe_editor.dart';
import 'kitchen_design.dart';
import '../platform/export_share.dart';
import '../platform/local_media.dart';
import '../platform/app_analytics.dart';

// Screen state is deliberately separate from persisted kitchen records.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.store, this.servicesBuilder, this.onTabSelected});
  final AppStore store;
  final WidgetBuilder? servicesBuilder;
  final ValueChanged<KitchenTab>? onTabSelected;
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int tab = KitchenTab.home.index;
  void selectTab(KitchenTab destination) {
    if (tab == destination.index) return;
    setState(() => tab = destination.index);
    widget.onTabSelected?.call(destination);
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Row(children: [
        KitchenBrandMark(),
        SizedBox(width: 10),
        Flexible(child: Text('Crispy Crust', maxLines: 1, overflow: TextOverflow.ellipsis)),
      ])),
      body: IndexedStack(index: tab, children: [
        StartersScreen(store: widget.store),
        RecipesScreen(store: widget.store),
        HomeScreen(store: widget.store),
        KitchenScreen(store: widget.store, servicesBuilder: widget.servicesBuilder),
        JournalScreen(store: widget.store),
      ]),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
        child: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => selectTab(KitchenTab.values[i]), destinations: const [
        NavigationDestination(icon: Icon(Icons.water_drop_outlined), selectedIcon: Icon(Icons.water_drop), label: 'Starters'),
        NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Recipes'),
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Features'),
        NavigationDestination(icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories), label: 'Journal'),
      ])),
    ),
  );
}

void _open(BuildContext context, Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
Future<void> _run(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
  } catch (e) {
    final message = switch (e) {
      FormatException() => e.message,
      StateError() => '${e.message}',
      _ => 'Could not save. Try again.',
    };
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
  }
}
String _str(dynamic value, [String fallback = '']) => value?.toString() ?? fallback;
double _num(dynamic value, [double fallback = 0]) => value is num ? value.toDouble() : double.tryParse(_str(value)) ?? fallback;
List<Map<String, dynamic>> _maps(dynamic value) => (value is List ? value : const []).whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();
String _date(dynamic value) {
  final d = value is DateTime ? value : DateTime.tryParse(_str(value));
  if (d == null) return 'Not recorded';
  final l = d.toLocal();
  return '${l.day}/${l.month}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
String _grams(dynamic value) => '${_num(value).toStringAsFixed(_num(value) == _num(value).roundToDouble() ? 0 : 1)} g';


class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
  );
}
class _Panel extends StatelessWidget {
  const _Panel({required this.children, this.tone = false});
  final List<Widget> children;
  final bool tone;
  @override
  Widget build(BuildContext context) => Card(color: tone ? Theme.of(context).colorScheme.secondaryContainer : null, margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)));
}
class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.icon = Icons.info_outline});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 20), const SizedBox(width: 10), Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium))]));
}
class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.title, this.body);
  final IconData icon;
  final String title, body;
  @override
  Widget build(BuildContext context) => _Panel(children: [
    Align(alignment: Alignment.centerLeft, child: Icon(icon, size: 26, color: Theme.of(context).colorScheme.primary)),
    const SizedBox(height: 12),
    Text(title, style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 6),
    Text(body),
  ]);
}

class _Field {
  const _Field(this.key, this.label, {this.initial = '', this.numeric = false, this.multiline = false, this.required = true});
  final String key, label, initial;
  final bool numeric, multiline, required;
}
Future<Map<String, String>?> _form(BuildContext context, String title, List<_Field> fields, {String? explanation, String submit = 'Save', bool chooseStorage = false, bool allowEarlier = false, String earlierLabel = 'Fed earlier?', DateTime? initialEarlier}) => Navigator.of(context).push<Map<String, String>>(MaterialPageRoute(builder: (_) => _FormScreen(title: title, fields: fields, explanation: explanation, submit: submit, chooseStorage: chooseStorage, allowEarlier: allowEarlier, earlierLabel: earlierLabel, initialEarlier: initialEarlier)));
class _FormScreen extends StatefulWidget {
  const _FormScreen({required this.title, required this.fields, this.explanation, required this.submit, required this.chooseStorage, required this.allowEarlier, required this.earlierLabel, this.initialEarlier});
  final String title, submit;
  final List<_Field> fields;
  final bool chooseStorage, allowEarlier;
  final String earlierLabel;
  final DateTime? initialEarlier;
  final String? explanation;
  @override
  State<_FormScreen> createState() => _FormScreenState();
}
class _FormScreenState extends State<_FormScreen> {
  final key = GlobalKey<FormState>();
  String storage = 'counter';
  late DateTime? earlier = widget.initialEarlier;
  late final values = {for (final f in widget.fields) f.key: TextEditingController(text: f.initial)};
  @override
  void dispose() {for (final c in values.values) {c.dispose();} super.dispose();}
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.title)),
    bottomNavigationBar: KitchenActions(children: [
      FilledButton(onPressed: () {
        if (key.currentState!.validate()) Navigator.pop(context, {
          for (final e in values.entries) e.key: e.value.text.trim(),
          if (widget.chooseStorage) 'storage': storage,
          if (earlier != null) 'at': earlier!.toIso8601String(),
        });
      }, child: Text(widget.submit)),
    ]),
    body: Form(key: key, child: KitchenPage(children: [
    if (widget.explanation != null) _Notice(widget.explanation!),
    for (final f in widget.fields) Padding(padding: const EdgeInsets.only(bottom: 18), child: TextFormField(controller: values[f.key], decoration: InputDecoration(labelText: f.label, alignLabelWithHint: true), minLines: f.multiline ? 3 : 1, maxLines: f.multiline ? 8 : 1, keyboardType: f.numeric ? const TextInputType.numberWithOptions(decimal: true) : f.multiline ? TextInputType.multiline : TextInputType.text, validator: (v) {
      if (f.required && (v == null || v.trim().isEmpty)) return 'Enter ${f.label.toLowerCase()}';
      if (!f.required && (v == null || v.trim().isEmpty)) return null;
      if (f.numeric && (double.tryParse(v ?? '') == null || !double.parse(v!).isFinite || double.parse(v) < 0)) return 'Enter a finite non-negative number';
      return null;
    })),
    if (widget.chooseStorage)
      DropdownButtonFormField<String>(initialValue: storage, decoration: const InputDecoration(labelText: 'Where it lives'),
        items: const [DropdownMenuItem(value: 'counter', child: Text('Counter')), DropdownMenuItem(value: 'fridge', child: Text('Fridge'))],
        onChanged: (value) => setState(() => storage = value ?? 'counter')),
    if (widget.allowEarlier)
      TextButton.icon(icon: const Icon(Icons.access_time), label: Text(earlier == null ? widget.earlierLabel : _date(earlier)),
        onPressed: () async {
          final date = await _pickLocalTime(context, earlier ?? DateTime.now(), allowPast: true);
          if (mounted && date != null) setState(() => earlier = date);
        }),
  ])));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Timer refresh;

  @override
  void initState() {
    super.initState();
    refresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { refresh.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timers = _activeTimers(store);
    final active = store.records('bake').where((b) =>
      !['complete', 'abandoned', 'archived'].contains(b.text('state', b.text('status')))).toList();
    final jars = store.records('starter').where((jar) => !jar.flag('archived')).toList();
    final entries = <(DateTime, String, String, bool, VoidCallback)>[];
    for (final bake in active) {
      final steps = _maps(bake.fields['steps']);
      final index = bake.number('stepIndex').toInt();
      if (index < 0 || index >= steps.length) continue;
      final step = steps[index];
      final due = _stepDue(bake, step, index);
      final stepId = _str(step['id']);
      if (stepId.isNotEmpty && timers.any((timer) =>
        timer.text('bakeId') == bake.id && timer.text('stepId') == stepId)) continue;
      entries.add((due, _str(step['title'], 'Continue bake'), bake.text('name'), false,
        () => _open(context, BakeDetail(store: store, id: bake.id))));
    }
    for (final timer in timers) {
      if (timer.date('dueAt') case final due?) {
        entries.add((due, timer.text('name', 'Timer'), timer.text('bakeName', timer.text('starterName')),
          timer.text('starterId').isNotEmpty,
          () => _open(context, TimerCentreScreen(store: store, focusedTimerId: timer.id))));
      }
    }
    for (final jar in jars) {
      if (_nextStarterFeed(jar) case final due?) {
        if (!due.isBefore(tomorrow)) continue;
        entries.add((due, 'Feed ${jar.text('name')}', 'Starter care', true,
          () => _logStarterFeed(context, store, jar)));
      }
    }
    entries.sort((a, b) => a.$1.compareTo(b.$1));
    final primary = active.where((b) => b.text('state', b.text('status')) == 'active')
      .toList()..sort((a, b) {
        DateTime due(AppRecord bake) {
          final index = bake.number('stepIndex').toInt();
          final steps = _maps(bake.fields['steps']);
          return index >= 0 && index < steps.length ? _stepDue(bake, steps[index], index) : bake.updatedAt;
        }
        return due(a).compareTo(due(b));
      });
    void chooseBake({bool later = false}) => _open(context, RecipesScreen(
      store: store, chooseForBake: true, later: later));
    return Column(children: [
      Expanded(child: KitchenPage(children: [
        if (entries.isEmpty) ...[
          _Panel(tone: true, children: [
            Row(children: [
              const CrumbArt(size: 64), const SizedBox(width: 12),
              Expanded(child: Text('Your next bake', style: Theme.of(context).textTheme.titleLarge)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(onPressed: chooseBake, child: const Text('Bake now')),
              OutlinedButton(onPressed: () => chooseBake(later: true), child: const Text('Future bake')),
            ]),
          ]),
          _Panel(children: [
            Text('Your starter', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => _addStarter(context, store),
              icon: const Icon(Icons.add), label: const Text('Add starter')),
          ]),
        ] else ...[
          if (primary.firstOrNull case final bake?)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Continue bake'), subtitle: Text(bake.text('name')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, BakeDetail(store: store, id: bake.id)),
            ),
          const _Section('Kitchen timeline'),
          for (final (i, entry) in entries.indexed)
            KitchenTimelineEntry(at: entry.$1, title: entry.$2, detail: entry.$3,
              starter: entry.$4, onTap: entry.$5, last: i == entries.length - 1),
        ],
      ])),
      if (entries.isNotEmpty) KitchenActions(children: [
        OutlinedButton(onPressed: () => chooseBake(later: true), child: const Text('Future bake')),
        FilledButton(onPressed: chooseBake, child: const Text('Bake now')),
      ]),
    ]);
  }
}



bool _isPinned(AppStore store, AppRecord record) =>
    store.preference('todayPin.${record.id}', false) == true;


String _storageName(AppRecord jar) => switch (jar.text('storage', 'counter')) {
  'counter' => 'Counter', 'fridge' => 'Fridge', 'travel' => 'Travelling',
  'paused' => 'Paused', 'revival' => 'Reviving', _ => 'Storage not set',
};

String _feedStatus(AppRecord jar) {
  final routine = StarterRoutine.read(jar);
  if (routine == null) return 'Feed reminder off';
  final due = routine.dueAt(jar);
  if (due == null) return 'Feed reminder paused';
  return due.isAfter(DateTime.now()) ? 'Next feed reminder · ${_date(due)}' : 'Feed reminder due';
}

Future<DateTime?> _pickLocalTime(BuildContext context, DateTime initial, {bool allowPast = false}) async {
  final now = DateTime.now();
  final first = allowPast ? DateTime(now.year - 10) : DateTime(now.year, now.month, now.day);
  final last = allowPast ? now : now.add(const Duration(days: 365));
  final seed = initial.isBefore(first) ? first : initial.isAfter(last) ? last : initial;
  final date = await showDatePicker(context: context, initialDate: seed, firstDate: first, lastDate: last);
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(seed));
  return time == null ? null : DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<(DateTime, DateTime)?> _askTimeAway(BuildContext context, DateTime suggested, {DateTime? ending}) async {
  var start = suggested;
  var end = ending ?? suggested.add(const Duration(hours: 3));
  return showModalBottomSheet<(DateTime, DateTime)>(
    context: context, isScrollControlled: true, showDragHandle: true,
    builder: (sheet) => StatefulBuilder(builder: (sheet, update) => SafeArea(
      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('When will you be away?', style: Theme.of(sheet).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('We’ll try to fit the bake around you. For suitable doughs, a covered fridge rest can slow fermentation; we’ll add tasks to chill the dough and take it back out. Check how the dough looks before shaping.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () async {
            final next = await _pickLocalTime(sheet, start);
            if (next != null && sheet.mounted) update(() {
              start = next;
              if (!end.isAfter(start)) end = start.add(const Duration(hours: 3));
            });
          }, child: Text('Leave · ${_date(start)}')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () async {
            final next = await _pickLocalTime(sheet, end);
            if (next != null && sheet.mounted) update(() => end = next);
          }, child: Text('Back · ${_date(end)}')),
          const SizedBox(height: 12),
          FilledButton(onPressed: end.isAfter(start) && start.isAfter(DateTime.now())
            ? () => Navigator.pop(sheet, (start, end)) : null, child: const Text('Use these times')),
        ]),
      ),
    )),
  );
}

Future<void> _logStarterFeed(BuildContext context, AppStore store, AppRecord jar) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
    _StarterFeedScreen(store: store, jar: jar)));
}

class _StarterFeedScreen extends StatefulWidget {
  const _StarterFeedScreen({required this.store, required this.jar});
  final AppStore store;
  final AppRecord jar;
  @override
  State<_StarterFeedScreen> createState() => _StarterFeedScreenState();
}

class _StarterFeedScreenState extends State<_StarterFeedScreen> {
  late final double? mass = double.tryParse(widget.jar.text('mass'));
  late final retained = TextEditingController(text: mass == null ? '' : _weight(mass!));
  late final removed = TextEditingController(text: mass == null ? '' : '0');
  late final flour = TextEditingController(text: widget.jar.text('lastFlour'));
  late final water = TextEditingController(text: widget.jar.text('lastWater'));
  final key = GlobalKey<FormState>();
  DateTime? fedAt;
  bool busy = false;

  String _weight(double value) => value.toString().replaceFirst(RegExp(r'\.0$'), '');

  @override
  void dispose() {
    for (final input in [retained, removed, flour, water]) { input.dispose(); }
    super.dispose();
  }

  double? _amount(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite && value >= 0 ? value : null;
  }

  Widget _field(String label, TextEditingController controller, {
    ValueChanged<String>? onChanged, double? maximum, bool positive = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller, onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (text) {
        final grams = _amount(text ?? '');
        if (grams == null || (positive && grams == 0)) return 'Enter a valid weight';
        if (maximum != null && grams > maximum) return 'Use at most ${_grams(maximum)}';
        return null;
      },
    ),
  );

  void _balance(String value, TextEditingController other) {
    final grams = _amount(value);
    if (mass == null) return;
    other.text = grams != null && grams <= mass! ? _weight(mass! - grams) : '';
    setState(() {});
  }

  Future<void> _save() async {
    if (busy || !key.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final latest = widget.store.find(widget.jar.id);
      if (latest == null || latest.fields['mass'] != widget.jar.fields['mass']) {
        throw StateError('The jar weight changed. Reopen this feed to use the latest amount.');
      }
      await widget.store.logFeed(widget.jar.id, seed: _amount(retained.text)!,
        flour: _amount(flour.text)!, water: _amount(water.text)!, occurredAt: fedAt);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sum = [_amount(retained.text), _amount(flour.text), _amount(water.text)];
    final total = sum.every((value) => value != null)
      ? sum.fold<double>(0, (total, value) => total + value!) : null;
    return Scaffold(
      appBar: AppBar(title: Text('Feed ${widget.jar.text('name')}')),
      bottomNavigationBar: KitchenActions(children: [
        FilledButton(onPressed: busy ? null : _save, child: const Text('Record feed')),
      ]),
      body: Form(key: key, child: KitchenPage(children: [
        if (mass != null) ...[
          Text('Starting weight · ${_grams(mass)}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _field('Starter removed (g)', removed, maximum: mass,
            onChanged: (value) => _balance(value, retained)),
        ],
        _field('Starter retained (g)', retained, maximum: mass,
          onChanged: (value) => mass == null ? setState(() {}) : _balance(value, removed)),
        _field('Flour added (g)', flour, positive: true, onChanged: (_) => setState(() {})),
        _field('Water added (g)', water, onChanged: (_) => setState(() {})),
        if (total != null) Text('After feeding · ${_grams(total)}'),
        TextButton(onPressed: () async {
          final value = await _pickLocalTime(context, fedAt ?? DateTime.now(), allowPast: true);
          if (value != null && mounted) setState(() => fedAt = value);
        }, child: Text(fedAt == null ? 'Fed earlier?' : _date(fedAt))),
      ])),
    );
  }
}


Future<void> _editStarterRoutine(BuildContext context, AppStore store, AppRecord jar) async {
  final prior = StarterRoutine.read(jar);
  final suggested = StarterRoutine.suggestedHours(jar.text('storage'));
  var selectedHours = prior?.hours ?? suggested;
  var firstDue = prior?.dueAt(jar)?.toLocal() ?? DateTime.now().add(Duration(hours: selectedHours));
  if (!firstDue.isAfter(DateTime.now())) firstDue = DateTime.now().add(Duration(hours: selectedHours));
  final hasSuggestedInterval = ['counter', 'fridge'].contains(jar.text('storage'));
    final choice = await showModalBottomSheet<int>(context: context, isScrollControlled: true,
      showDragHandle: true, builder: (sheet) => StatefulBuilder(builder: (sheet, setState) => SafeArea(
        child: Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Feed reminder', style: Theme.of(sheet).textTheme.titleLarge)),
              const KitchenInfo(title: 'About feed reminders', text: 'The suggested interval is a starting point for established starters. Use your own routine and observations. A scheduled reminder cannot tell if a jar needs feeding or is ready to bake.'),
            ]),
            if (hasSuggestedInterval)
              Text(suggested == 168 ? 'Fridge suggestion · 7 days' : 'Counter suggestion · 24 hours'),
            const SizedBox(height: 12),
            TextFormField(initialValue: selectedHours.toString(), keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Repeat after (hours)', helperText: '1 to 720 hours'),
              onChanged: (value) => setState(() {
                selectedHours = int.tryParse(value) ?? 0;
                if (selectedHours >= 1 && selectedHours <= 720) {
                  firstDue = DateTime.now().add(Duration(hours: selectedHours));
                }
              })),
            OutlinedButton.icon(icon: const Icon(Icons.schedule), label: Text('First reminder · '+_date(firstDue)),
              onPressed: () async {
                final date = await _pickLocalTime(sheet, firstDue);
                if (date != null && sheet.mounted) setState(() => firstDue = date);
              }),
            if (StarterRoutine.isAway(jar.text('storage')))
              const Text('Change the jar’s care mode to resume its reminders.'),
            FilledButton(
              onPressed: selectedHours < 1 || selectedHours > 720 || !firstDue.isAfter(DateTime.now()) ||
                StarterRoutine.isAway(jar.text('storage')) ? null : () => Navigator.pop(sheet, selectedHours),
              child: Text(prior?.paused == true ? 'Resume feed reminder' : 'Save feed reminder')),
            if (prior != null)
              TextButton(onPressed: () => Navigator.pop(sheet, 0), child: const Text('Turn off feed reminder')),
          ])),
        ),
      )));
    if (choice == null || !context.mounted) return;
    final latest = store.find(jar.id);
    if (latest == null || latest.flag('archived')) return;
    final fields = {...latest.fields};
    if (choice == 0) {
      fields.remove('feedRoutine');
    } else {
      fields['feedRoutine'] = StarterRoutine(choice, firstDue.subtract(Duration(hours: choice)),
        configuredAt: DateTime.now(), paused: StarterRoutine.isAway(latest.text('storage'))).toJson();
    }
    await _run(context, () => store.save('starter', fields, id: jar.id));
}

Future<void> _addStarter(BuildContext context, AppStore store) async {
  final fields = await _form(context, 'Add a starter',
    const [_Field('name', 'Jar name'), _Field('jarWeight', 'Empty jar weight (g, optional)', numeric: true, required: false)],
    chooseStorage: true);
  if (fields == null || !context.mounted) return;
  final weight = double.tryParse(fields['jarWeight']!);
  await _run(context, () async {
    if (weight != null && (!weight.isFinite || weight <= 0)) {
      throw const FormatException('Use a positive empty jar weight.');
    }
    final used = store.records('starter').map((record) => record.number('mascot', -1).toInt()).toSet();
    final mascot = List.generate(10, (index) => index).where((index) => !used.contains(index)).firstOrNull
      ?? store.records('starter').length % 10;
    await store.save('starter', {
      'name': fields['name'], 'storage': fields['storage'], 'hydration': 100,
      'mascot': mascot, 'createdAt': DateTime.now().toUtc().toIso8601String(),
      if (weight != null) 'jarWeight': weight,
    });
  });
}

DateTime? _nextStarterFeed(AppRecord jar) {
  if (StarterRoutine.isAway(jar.text('storage')) || jar.flag('archived')) return null;
  final routine = StarterRoutine.read(jar);
  if (routine != null) return routine.dueAt(jar);
  final last = jar.date('lastFeedAt');
  if (last == null || !['counter', 'fridge'].contains(jar.text('storage', 'counter'))) return null;
  return last.add(Duration(hours: StarterRoutine.suggestedHours(jar.text('storage'))));
}

class _StarterAvatar extends StatelessWidget {
  const _StarterAvatar(this.jar, this.store, {this.size = 60});
  final AppRecord jar;
  final AppStore store;
  final double size;
  @override
  Widget build(BuildContext context) {
    final cover = store.find(jar.text('coverObservationId'));
    final metadata = cover?.fields['photo'];
    final fallback = jar.id.codeUnits.fold(0, (value, unit) => value + unit) % 10;
    return SizedBox.square(dimension: size, child: metadata is Map
      ? _LocalPhotoView(metadata: Map<String, dynamic>.from(metadata), label: 'Starter photo', thumbnail: true)
      : Image.asset('assets/editorial/jar-${jar.number('mascot', fallback).toInt().clamp(0, 9)}.webp',
        fit: BoxFit.contain, excludeFromSemantics: true,
        errorBuilder: (_, _, _) => CrumbArt(size: size)));
  }
}

class StartersScreen extends StatelessWidget {
  const StartersScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final jars = store.records('starter').where((jar) => !jar.flag('archived')).toList();
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Column(children: [
      Expanded(child: KitchenPage(children: [
        if (jars.isEmpty) const _Panel(children: [
          Row(children: [CrumbArt(size: 64), SizedBox(width: 12), Expanded(child: Text('Add your first jar to track feeds.'))]),
        ]),
        for (final jar in jars)
          Builder(builder: (context) {
            final last = jar.date('lastFeedAt');
            final due = _nextStarterFeed(jar);
            final remaining = due?.difference(now);
            final overdue = remaining?.isNegative ?? false;
            final color = overdue ? theme.colorScheme.error : theme.colorScheme.primary;
            final daysUntil = remaining == null ? null : (remaining.inMinutes / 1440);
            final countdown = daysUntil == null ? null : overdue ? daysUntil.floor() : daysUntil.ceil();
            final daysAgo = last == null ? null : now.difference(last).inDays.clamp(0, 999999);
            return _Panel(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _StarterAvatar(jar, store),
                title: Text(jar.text('name'), style: theme.textTheme.titleMedium),
                subtitle: Text(_storageName(jar)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, StarterDetail(store: store, id: jar.id)),
              ),
              Text(daysAgo == null ? 'First feed unlogged' : 'Last fed · $daysAgo ${daysAgo == 1 ? 'day' : 'days'} ago',
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              if (countdown != null)
                Text('Next feed · $countdown ${countdown.abs() == 1 ? 'day' : 'days'}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ]);
          }),
      ])),
      KitchenActions(children: [
        FilledButton.icon(onPressed: () => _addStarter(context, store),
          icon: const Icon(Icons.add), label: const Text('Add a starter')),
      ]),
    ]);
  }
}

class StarterDetail extends StatelessWidget {
  const StarterDetail({super.key, required this.store, required this.id});
  final AppStore store;
  final String id;

  Future<void> _appearance(BuildContext context, AppRecord jar) async {
    final selection = await showModalBottomSheet<int>(context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Choose a starter mascot'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < 10; i++) IconButton(
              tooltip: 'Choose mascot ${i + 1}',
              onPressed: () => Navigator.pop(sheet, i),
              icon: Image.asset('assets/editorial/jar-$i.webp', width: 48, height: 48, fit: BoxFit.contain),
            ),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () => Navigator.pop(sheet, -1),
            icon: const Icon(Icons.image_outlined), label: const Text('Use a real photo')),
        ]),
      )));
    if (selection == null || !context.mounted) return;
    if (selection == -1) {
      _open(context, ObservationCaptureScreen(store: store, objectId: id, starter: true,
        outcomePhoto: true, starterCover: true));
      return;
    }
    await _run(context, () async {
      final current = store.find(id);
      if (current == null) return;
      final fields = {...current.fields, 'mascot': selection}..remove('coverObservationId');
      await store.save('starter', fields, id: id);
    });
  }

  Future<void> _editJar(BuildContext context, AppRecord jar) async {
    final initially = jar.date('createdAt');
    final fields = await _form(context, 'Edit jar', [
      _Field('name', 'Jar name', initial: jar.text('name')),
      _Field('jarWeight', 'Empty jar weight (g)', initial: jar.text('jarWeight'), required: false, numeric: true),
    ], allowEarlier: true, earlierLabel: 'Set starter birthday', initialEarlier: initially);
    if (fields == null || !context.mounted) return;
    final tare = double.tryParse(fields['jarWeight']!);
    await _run(context, () async {
      if (tare != null && (!tare.isFinite || tare <= 0)) throw const FormatException('Use a positive empty jar weight.');
      final current = store.find(id);
      if (current == null) return;
      await store.save('starter', {
        ...current.fields, 'name': fields['name'], 'jarWeight': tare,
        if (fields['at'] != null) 'createdAt': fields['at'],
      }, id: id);
    });
  }

  Future<void> _mode(BuildContext context, AppRecord jar) async {
    final choice = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (key, label) in const [
          ('counter', 'Counter'), ('fridge', 'Fridge'), ('travel', 'Travelling'),
          ('paused', 'Paused'), ('revival', 'Reviving'),
        ]) ListTile(title: Text(label), leading: Icon(key == jar.text('storage')
          ? Icons.check_circle_outline : Icons.circle_outlined), onTap: () => Navigator.pop(sheet, key)),
      ])));
    if (choice != null && context.mounted) {
      await _run(context, () => setStarterCareMode(store, id, choice));
    }
  }

  void _guides(BuildContext context) => _open(context, LearnScreen(store: store, starterFirst: true));

  Future<void> _settings(BuildContext context, AppRecord jar) async {
    final choice = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: const Text('Edit jar details'), leading: const Icon(Icons.edit_outlined),
          onTap: () => Navigator.pop(sheet, 'edit')),
        ListTile(title: const Text('Storage, travel or pause'), subtitle: Text(_storageName(jar)),
          leading: const Icon(Icons.kitchen_outlined), onTap: () => Navigator.pop(sheet, 'storage')),
        ListTile(title: const Text('Feed reminder'), subtitle: Text(_feedStatus(jar)),
          leading: const Icon(Icons.notifications_outlined), onTap: () => Navigator.pop(sheet, 'feed')),
        ListTile(title: const Text('Correct measured starter weight'), leading: const Icon(Icons.scale_outlined),
          onTap: () => Navigator.pop(sheet, 'weight')),
        ListTile(title: const Text('Delete this jar'), leading: const Icon(Icons.delete_outline),
          onTap: () => Navigator.pop(sheet, 'delete')),
      ])));
    if (!context.mounted) return;
    final latest = store.find(id);
    if (latest == null) return;
    switch (choice) {
      case 'edit': await _editJar(context, latest);
      case 'storage': await _mode(context, latest);
      case 'feed': await _editStarterRoutine(context, store, latest);
      case 'weight': await _changeStock(context, store, latest);
      case 'delete': await _confirmDelete(context, store, latest);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) {
    final jar = store.find(id);
    if (jar == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This jar is unavailable.')));
    final feeds = store.records('feed').where((feed) => feed.text('starterId') == id).toList()
      ..sort((a, b) => (b.date('occurredAt') ?? b.updatedAt).compareTo(a.date('occurredAt') ?? a.updatedAt));
    final observations = store.records('observation').where((o) => o.text('objectId') == id).toList();
    final photos = observations.where((o) => o.fields['photo'] is Map);
    final uses = store.records('bake').where((bake) => bake.text('starterId') == id);
    final withdrawals = store.records('correction').where((entry) =>
      entry.text('correctsId') == id && entry.fields['usedGrams'] != null);
    final birthday = jar.date('createdAt') ?? feeds.lastOrNull?.date('occurredAt');
    final age = birthday == null ? '—' : '${DateTime.now().difference(birthday).inDays.clamp(0, 999999)} days';
    return Scaffold(
      appBar: AppBar(title: const Text('Back to Starters'), actions: [
        IconButton(tooltip: 'Starter settings', onPressed: () => _settings(context, jar),
          icon: const Icon(Icons.settings_outlined)),
      ]),
      bottomNavigationBar: KitchenActions(children: [
        OutlinedButton(onPressed: () => _guides(context), child: const Text('Need help?')),
        FilledButton(onPressed: () => _logStarterFeed(context, store, jar), child: const Text('Feed')),
      ]),
      body: KitchenPage(children: [
        _Panel(tone: true, children: [
          Row(children: [
            _StarterAvatar(jar, store, size: 88),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(jar.text('name'), style: Theme.of(context).textTheme.titleLarge),
              Text(_storageName(jar)),
            ])),
            IconButton(tooltip: 'Edit starter photo or mascot', onPressed: () => _appearance(context, jar),
              icon: const Icon(Icons.edit_outlined)),
          ]),
          const SizedBox(height: 14),
          for (final (label, value) in [
            ('Age', age),
            ('Starter weight', jar.fields['mass'] == null ? '—' : _grams(jar.fields['mass'])),
            ('Empty jar weight', jar.fields['jarWeight'] == null ? '—' : _grams(jar.fields['jarWeight'])),
            ('Hydration', jar.fields['hydration'] == null ? '—' : '${jar.number('hydration').toStringAsFixed(1)}%'),
          ]) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
            Expanded(child: Text(label)), Text(value),
          ])),
        ]),
        ExpansionTile(title: const Text('Feed history'), children: [
          if (feeds.isEmpty) const ListTile(title: Text('No feeds yet')),
          for (final feed in feeds) ListTile(
            title: Text(_date(feed.fields['occurredAt'])),
            subtitle: Text('${_grams(feed.fields['seed'])} starter · ${_grams(feed.fields['flour'])} flour · ${_grams(feed.fields['water'])} water'),
            trailing: IconButton(tooltip: 'Edit feed record', icon: const Icon(Icons.edit_outlined),
              onPressed: () => _open(context, RecordHistoryScreen(store: store, record: feed))),
          ),
        ]),
        ExpansionTile(title: const Text('History'), children: [
          ListTile(leading: const Icon(Icons.add_a_photo_outlined), title: const Text('Add photos'),
            onTap: () => _open(context, ObservationCaptureScreen(store: store,
              objectId: id, starter: true, outcomePhoto: true))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final photo in photos)
              InkWell(onTap: () => showDialog<void>(context: context, builder: (dialog) => Dialog(
                child: Padding(padding: const EdgeInsets.all(12), child: _LocalPhotoView(
                  metadata: Map<String, dynamic>.from(photo.fields['photo'] as Map), label: 'Starter photo')))),
                child: SizedBox(width: 60, child: _LocalPhotoView(
                  metadata: Map<String, dynamic>.from(photo.fields['photo'] as Map), label: 'Starter photo', thumbnail: true))),
          ]),
        ]),
        ExpansionTile(title: const Text('Starter used'), children: [
          if (uses.isEmpty && withdrawals.isEmpty) const ListTile(title: Text('No baking history for this jar yet')),
          for (final bake in uses) Card(child: ListTile(
            title: Text(bake.text('name', 'Bake')),
            subtitle: Text([
              _grams(bake.fields['starterGrams']),
              bake.date('starterUsedAt') == null ? 'Planned' : 'Used ${_date(bake.fields['starterUsedAt'])}',
              if (bake.fields['starterStockDeducted'] == false) 'Check jar weight',
            ].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, BakeDetail(store: store, id: bake.id)),
          )),
          for (final entry in withdrawals.where((entry) =>
            !uses.any((bake) => bake.id == entry.text('bakeId'))))
            Card(child: ListTile(title: Text(store.find(entry.text('bakeId'))?.text('name') ?? 'Recorded use'),
              subtitle: Text('${_grams(entry.fields['usedGrams'])} · ${_date(entry.fields['occurredAt'])}'))),
          TextButton(onPressed: () => _changeStock(context, store, jar, withdrawal: true),
            child: const Text('Record other starter use')),
        ]),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Starter guides'),
          subtitle: const Text('A healthy starter is the foundation of a good loaf.'),
          trailing: const Icon(Icons.chevron_right), onTap: () => _guides(context)),
      ]),
    );
  });
}



Future<void> _confirmDelete(BuildContext context, AppStore store, AppRecord record) async {
  final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text('Delete ${record.text('name', record.kind)}?'), content: const Text('This removes the local record. Existing bake snapshots stay independent. Export your data first if you need a copy.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete record'))]));
  if (yes == true && context.mounted) await _run(context, () async {await store.remove(record.id); if (context.mounted) Navigator.pop(context);});
}

Future<void> _changeStock(BuildContext context, AppStore store, AppRecord record, {
  bool withdrawal = false,
}) async {
  String? bakeId;
  final bakes = record.kind == 'starter' && withdrawal
    ? store.records('bake').where((bake) => bake.text('starterId') != record.id).toList()
    : const <AppRecord>[];
  if (bakes.isNotEmpty) {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which bake used the starter?'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, ''), child: const Text('No linked bake')),
          for (final bake in bakes)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, bake.id), child: Text(bake.text('name', 'Bake'))),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice.isNotEmpty) bakeId = choice;
  }
  final form = await _form(context, withdrawal ? 'Record stock used' : 'Correct measured stock', [
    _Field('grams', withdrawal ? 'Grams used' : 'Grams remaining', numeric: true),
    const _Field('reason', 'Reason'),
  ], explanation: withdrawal
      ? 'Enter what you physically used. The remaining amount stays in this record.'
      : 'Weigh the stock now. The previous amount stays in the audit history.');
  if (form == null || !context.mounted) return;
  await _run(context, () => store.reconcileStock(
    record.id, expectedRevision: record.revision, grams: double.parse(form['grams']!),
    reason: form['reason']!, withdrawal: withdrawal, bakeId: bakeId,
  ), success: 'Stock and its audit entry saved.');
}

enum _RecipeStyle {
  all('All'), bread('Bread', 'bread'), focaccia('Focaccia', 'focaccia'),
  pizza('Pizza', 'pizza'), sweets('Sweets', 'sweets'),
  discard('Discard', 'discard'), mine('My recipes');

  const _RecipeStyle(this.label, [this.art]);
  final String label;
  final String? art;
}

_RecipeStyle _recipeStyle(Map<String, dynamic> recipe) {
  final family = _str(recipe['family']).toLowerCase();
  final name = _str(recipe['title']).toLowerCase();
  if (family == 'discard' || name.contains('discard')) return _RecipeStyle.discard;
  if (family == 'focaccia' || name.contains('focaccia')) return _RecipeStyle.focaccia;
  if (family == 'pizza' || name.contains('pizza')) return _RecipeStyle.pizza;
  if (family == 'sweets' || RegExp(r'cinnamon rolls?|cake|cookie|brownie|muffin|dessert').hasMatch(name)) {
    return _RecipeStyle.sweets;
  }
  return _RecipeStyle.bread;
}

bool _canBake(Map<String, dynamic> recipe) => recipe['schedulable'] != false &&
  _maps(recipe['ingredients']).isNotEmpty && _maps(recipe['steps']).isNotEmpty;

class _RecipeIcon extends StatelessWidget {
  const _RecipeIcon(this.style, {required this.size});
  final _RecipeStyle style;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/editorial/${style.art}-icon.webp',
    width: size, height: size, fit: BoxFit.contain, excludeFromSemantics: true,
  );
}

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key, required this.store, this.chooseForBake = false, this.later = false});
  final AppStore store;
  final bool chooseForBake;
  final bool later;
  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  String query = '';
  _RecipeStyle style = _RecipeStyle.all;

  @override
  Widget build(BuildContext context) {
    final body = ListenableBuilder(listenable: widget.store, builder: (context, _) {
      final records = widget.store.records('recipe');
      final ownIds = records.map((r) => r.id).toSet();
      final all = [
        ...widget.store.recipes,
        ...records.map((r) => {...r.fields, 'id': r.id}),
      ];
      final matches = all.where((r) =>
        _str(r['title']).toLowerCase().contains(query.trim().toLowerCase()) &&
        (style == _RecipeStyle.all ||
          (style == _RecipeStyle.mine ? ownIds.contains(r['id']) : _recipeStyle(r) == style)));
      return Column(children: [
      Expanded(child: KitchenPage(children: [
        TextField(
          decoration: const InputDecoration(labelText: 'Search recipes', prefixIcon: Icon(Icons.search)),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final option in _RecipeStyle.values)
            ChoiceChip(
              showCheckmark: false,
              avatar: option.art == null ? null : _RecipeIcon(option, size: 22),
              label: Text(option.label),
              selected: option == style,
              onSelected: (_) => setState(() => style = option),
            ),
        ]),
        const SizedBox(height: 12),
        if (matches.isEmpty) const _Empty(Icons.search_off, 'No recipes found', 'Try another filter or search.'),
        for (final recipe in matches)
          _RecipeRow(recipe: recipe, onOpen: () => _open(context,
            widget.chooseForBake && _canBake(recipe)
              ? PlanScreen(store: widget.store, initialRecipe: recipe, standalone: true, later: widget.later)
              : RecipeDetail(store: widget.store, recipe: recipe, editId: ownIds.contains(recipe['id']) ? recipe['id'] as String : null),
          )),
      ])),
      if (!widget.chooseForBake) KitchenActions(children: [
        OutlinedButton.icon(onPressed: () => _open(context, RecipeEditor(store: widget.store)),
          icon: const Icon(Icons.add), label: const Text('Add recipe')),
      ]),
      ]);
    });
    return widget.chooseForBake ? Scaffold(appBar: AppBar(title: const Text('Start a bake')), body: body) : body;
  }
}


class _RecipeRow extends StatelessWidget {
  const _RecipeRow({required this.recipe, required this.onOpen});
  final Map<String, dynamic> recipe;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(
              width: 72, height: 56, child: _RecipePhoto(recipe),
            )),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_str(recipe['title']), style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              if (_canBake(recipe)) _RecipeStats(recipe, compact: true)
              else Text('Draft · Needs a method', style: theme.textTheme.bodySmall),
            ])),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20),
          ]),
        ),
      ),
    );
  }
}

class RecipeDetail extends StatefulWidget {
  const RecipeDetail({super.key, required this.store, required this.recipe, this.editId});
  final AppStore store;
  final Map<String, dynamic> recipe;
  final String? editId;
  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}
typedef _RecipeMetrics = ({int? skill, int total, int work});

_RecipeMetrics _recipeMetrics(Map<String, dynamic> recipe) {
  const ratings = [2, 3, 6, 3, 3, 4, 4, 5, 6, 5, 3, 4, 7, 2, 3, 4, 5, 6, 4, 2, 1, 2, 2, 6, 3, 4, 4, 3, 3, 3];
  final number = int.tryParse(_str(recipe['id']).replaceFirst(RegExp(r'^R'), ''));
  final skill = number != null && number >= 1 && number <= ratings.length ? ratings[number - 1] : null;
  final steps = _maps(recipe['steps']);
  List<dynamic> dependencies(Map<String, dynamic> step) =>
    step['after'] is List ? step['after'] as List : const [];
  final ends = <String, int>{};
  final pending = [...steps];
  var overall = 0, work = 0;
  while (pending.isNotEmpty) {
    final index = pending.indexWhere((step) => dependencies(step).every(ends.containsKey));
    if (index < 0) break;
    final step = pending.removeAt(index);
    final minutes = _num(step['durationMinutes']);
    final duration = minutes.isFinite ? minutes.round().clamp(0, 20160) : 0;
    final id = _str(step['id']);
    final start = dependencies(step).fold<int>(0, (latest, dep) =>
      ends[dep]! > latest ? ends[dep]! : latest);
    final end = start + duration;
    ends[id] = end;
    if (end > overall) overall = end;
    final title = _str(step['title']).toLowerCase();
    work += switch (step['kind']) {
      'check' => duration.clamp(0, 1),
      'handsOn' when title.contains('preheat') => duration.clamp(0, 3),
      'handsOn' when (title.contains('bake') || title.contains('cool')) => duration.clamp(0, 8),
      'handsOn' => duration,
      _ => 0,
    };
  }
  return (skill: skill, total: overall, work: work);
}

class _RecipeStats extends StatelessWidget {
  const _RecipeStats(this.recipe, {this.compact = false});
  final Map<String, dynamic> recipe;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final metrics = _recipeMetrics(recipe);
    final theme = Theme.of(context);
    final values = [
      (Icons.signal_cellular_alt, 'Skill level', metrics.skill == null ? '—' : '${metrics.skill}/10'),
      (Icons.schedule, 'Overall time', metrics.total == 0 ? '—' : '${(metrics.total / 60).toStringAsFixed(1)} h'),
      (Icons.back_hand_outlined, 'Work time', metrics.total == 0 ? '—' : '${metrics.work} min'),
    ];
    if (compact) return Wrap(spacing: 9, runSpacing: 4, children: [
      for (final (icon, label, value) in values) Semantics(
        label: '$label $value',
        child: ExcludeSemantics(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary), const SizedBox(width: 3),
          Text(value, style: theme.textTheme.labelSmall),
        ])),
      ),
    ]);
    return Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(children: [
        for (final (icon, label, value) in values) ListTile(
          dense: true, leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(label), trailing: Text(value, style: theme.textTheme.titleSmall),
        ),
      ]),
    ));
  }
}

class _RecipeDetailState extends State<RecipeDetail> {
  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    final ingredients = _maps(recipe['ingredients']);
    final steps = _maps(recipe['steps']);
    final theme = Theme.of(context);
    return DefaultTabController(length: 3, child: Scaffold(
      appBar: AppBar(title: Text(_str(recipe['title']))),
      bottomNavigationBar: KitchenActions(children: [
        if (_canBake(recipe)) FilledButton(onPressed: () => _open(context,
          PlanScreen(store: widget.store, initialRecipe: recipe, standalone: true)),
          child: const Text('Start this bake'))
        else if (widget.editId != null) FilledButton(onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
            RecipeEditor(store: widget.store, original: recipe, editId: widget.editId)));
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('Edit recipe')),
      ]),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(padding: const EdgeInsets.fromLTRB(20, 5, 20, 12),
              child: ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(
                aspectRatio: 1.8, child: _RecipePhoto(recipe),
              )),
            ),
          ))),
          const SliverAppBar(primary: false, pinned: true, toolbarHeight: 0,
            automaticallyImplyLeading: false, bottom: TabBar(tabs: [
              Tab(text: 'Overview'), Tab(text: 'Ingredients'), Tab(text: 'Step by step'),
            ])),
        ],
        body: TabBarView(children: [
          KitchenPage(scrollKey: const PageStorageKey('recipe-overview'), children: [
            _RecipeStats(recipe),
            if (_str(recipe['description']).isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 16), child: Text(_str(recipe['description']))),
          ]),
          KitchenPage(scrollKey: const PageStorageKey('recipe-ingredients'), children: [
            for (final item in ingredients)
              ListTile(dense: true, contentPadding: EdgeInsets.zero,
                title: Text(_str(item['name'], _str(item['ingredientId'], 'Ingredient'))),
                trailing: Text(_grams(_ingredientGrams(item)), style: theme.textTheme.titleSmall)),
          ]),
          KitchenPage(scrollKey: const PageStorageKey('recipe-method'), children: [
            for (final (i, step) in steps.indexed)
              _Panel(children: [
                Text('${i + 1}. ${_str(step['title'], _str(step['name'], 'Step'))}',
                  style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                _MethodCue(instructions: _str(step['instructions'], _str(step['instruction'])),
                  cue: _str(step['readinessCue'] ?? step['cues'])),
              ]),
          ]),
        ]),
      ),
    ));
  }
}


class _RecipePhoto extends StatelessWidget {
  const _RecipePhoto(this.recipe);
  final Map<String, dynamic> recipe;
  @override
  Widget build(BuildContext context) {
    final id = _str(recipe['id']);
    final fallback = KitchenPhoto(KitchenArtwork.forRecipe(_str(recipe['family'])));
    if (!RegExp(r'^R(0[1-9]|[12][0-9]|30)$').hasMatch(id)) return fallback;
    return Image.asset('assets/editorial/${id.toLowerCase()}.webp',
      fit: BoxFit.cover, width: double.infinity, height: double.infinity,
      semanticLabel: 'Illustrated finished ${_str(recipe['title'])}',
      errorBuilder: (_, _, _) => fallback);
  }
}

class _MethodCue extends StatelessWidget {
  const _MethodCue({required this.instructions, required this.cue});
  final String instructions, cue;
  @override
  Widget build(BuildContext context) {
    if (cue.isEmpty) return Text(instructions);
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final lookout = DecoratedBox(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(9)),
        child: Padding(padding: const EdgeInsets.all(10), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('What to look for', style: theme.textTheme.labelLarge),
            const SizedBox(height: 5), Text(cue),
          ],
        )),
      );
      if (constraints.maxWidth < 255 || MediaQuery.textScalerOf(context).scale(14) > 21) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(instructions), const SizedBox(height: 8), lookout,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(instructions)), const SizedBox(width: 10), Expanded(child: lookout),
      ]);
    });
  }
}


double _ingredientGrams(Map<String, dynamic> i) => _num(i['grams'] ?? i['massG'] ?? i['quantityG'] ?? i['weightG']);

class RecipeEditor extends StatelessWidget {
  const RecipeEditor({super.key,required this.store,this.original,this.editId});
  final AppStore store;
  final Map<String,dynamic>? original;
  final String? editId;
  @override Widget build(BuildContext context)=>PrivateRecipeEditor(store:store,original:original,editId:editId);
}

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.store, this.initialRecipe, this.initialScale = 1, this.standalone = false, this.later = false});
  final AppStore store;
  final Map<String, dynamic>? initialRecipe;
  final double initialScale;
  final bool standalone;
  final bool later;
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}
enum _PlanAnchor { serving, mixing, soon }

class _PlanScreenState extends State<PlanScreen> {
  String? recipeId, starterId;
  late double scale = widget.initialScale;
  bool busy = false, shopping = true;
  late _PlanAnchor anchor = widget.later ? _PlanAnchor.mixing : _PlanAnchor.soon;
  DateTime target = DateTime.now().add(const Duration(days: 1)).copyWith(hour: 11, minute: 0);
  late double kitchenTemperature = (_num(widget.store.preference('roomTemperature', 23), 23))
    .clamp(0, 40).toDouble();
  final awayTimes = <(DateTime, DateTime)>[];

  Future<void> _unavailable({int? index}) async {
    final start = index != null ? awayTimes[index].$1 : awayTimes.lastOrNull?.$2 ??
      (anchor == _PlanAnchor.mixing ? target : DateTime.now()).add(const Duration(hours: 2));
    final value = await _askTimeAway(context, start, ending: index == null ? null : awayTimes[index].$2);
    if (value == null || !mounted) return;
    setState(() {
      if (index == null) {
        awayTimes.add(value);
      } else {
        awayTimes[index] = value;
      }
      awayTimes.sort((a, b) => a.$1.compareTo(b.$1));
    });
  }

  Future<void> _review(Map<String, dynamic> recipe) async {
    setState(() => busy = true);
    try {
      await _run(context, () async {
        final serveAt = anchor == _PlanAnchor.serving ? target : null;
        final reviewScale = scale;
        final setup = BakeSetup(starterId: starterId, addToShopping: shopping, timeAway: List.of(awayTimes));
        while (mounted) {
          final start = switch (anchor) {
            _PlanAnchor.serving => null,
            _PlanAnchor.mixing => target,
            _PlanAnchor.soon => DateTime.now().toUtc().add(const Duration(minutes: 2)),
          };
          final store = widget.store;
          final options = prepareBakeSchedule(recipe, [...store.records('availability'), ...setup.awayRecords],
            [...store.records('bake'), ...store.records('production')],
            {'oven': (store.preference('ovenCapacity', 1) as num).toInt()},
            serveAt: serveAt, startAt: start, doughTemperatureC: kitchenTemperature);
          if (!mounted) return;
          final candidate = await reviewScheduleOptions(context, options.recipe, options.candidates,
            scale: reviewScale, warning: options.warning,
            immediateAnchor: anchor == _PlanAnchor.soon ? start : null);
          if (candidate == null || !mounted) return;
          final immediate = anchor == _PlanAnchor.soon && candidate.startsAt.isAtSameMomentAs(start!);
          final navigator = Navigator.of(context);
          try {
            if (immediate && !start.isAfter(DateTime.now())) throw BakeScheduleChanged();
            final bake = await store.createBake({
              ...options.recipe, 'baseRecipeSnapshot': recipe,
            }, scale: reviewScale, serveAt: options.serveAt, startAt: options.startAt,
              expectedSchedule: candidate.toJson(), beginImmediately: immediate, setup: setup);
            if (mounted) navigator.pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => BakeDetail(store: store, id: bake.id)),
              (route) => route.isFirst,
            );
            return;
          } on BakeScheduleChanged {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('The schedule changed. Review the updated times.')));
          }
        }
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final all = widget.initialRecipe == null ? [
      ...store.recipes, ...store.records('recipe').map((r) => {...r.fields, 'id': r.id}),
    ].where(_canBake).toList() : const <Map<String, dynamic>>[];
    final selected = widget.initialRecipe ?? all.where((r) => _str(r['id']) == recipeId).firstOrNull;
    final starters = store.records('starter').where((jar) => !jar.flag('archived')).toList();
    final selectedStarter = starters.where((jar) => jar.id == starterId).firstOrNull;
    final needsStarter = selected != null && _maps(selected['ingredients']).any((item) => item['role'] == 'starter');
    final body = Column(children: [
      Expanded(child: KitchenPage(scrollKey: const ValueKey('plan-scroll'), children: [
        if (selected != null) Text(_str(selected['title'], 'Your bake'), style: Theme.of(context).textTheme.titleMedium),
        if (widget.initialRecipe == null)
          DropdownButtonFormField<String>(initialValue: recipeId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Recipe'),
            items: all.map((r) => DropdownMenuItem(value: _str(r['id']),
              child: Text(_str(r['title']), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: busy ? null : (value) => setState(() => recipeId = value)),
        const _Section('When do you want to bake?'),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Start now'), selected: anchor == _PlanAnchor.soon,
            onSelected: busy ? null : (_) => setState(() => anchor = _PlanAnchor.soon)),
          ChoiceChip(label: const Text('Schedule for later'), selected: anchor != _PlanAnchor.soon,
            onSelected: busy ? null : (_) => setState(() => anchor = _PlanAnchor.mixing)),
        ]),
        if (anchor != _PlanAnchor.soon) ...[
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Mix at'), selected: anchor == _PlanAnchor.mixing,
              onSelected: busy ? null : (_) => setState(() => anchor = _PlanAnchor.mixing)),
            ChoiceChip(label: const Text('Ready by'), selected: anchor == _PlanAnchor.serving,
              onSelected: busy ? null : (_) => setState(() => anchor = _PlanAnchor.serving)),
          ]),
          OutlinedButton.icon(onPressed: busy ? null : () async {
            final date = await _pickLocalTime(context, target);
            if (date != null && mounted) setState(() => target = date);
          }, icon: const Icon(Icons.event), label: Text(_date(target))),
        ],
        const _Section('Away from the Kitchen'),
        for (final (i, window) in awayTimes.indexed) Row(children: [
          Expanded(child: KitchenTimelineEntry(at: window.$1, title: 'Away',
            detail: 'Back ${_date(window.$2)}', last: i == awayTimes.length - 1,
            onTap: busy ? null : () => _unavailable(index: i))),
          IconButton(tooltip: 'Remove time away', icon: const Icon(Icons.close),
            onPressed: busy ? null : () => setState(() => awayTimes.removeAt(i))),
        ]),
        OutlinedButton.icon(onPressed: busy ? null : () => _unavailable(),
          icon: const Icon(Icons.add), label: Text(awayTimes.isEmpty ? 'Add time away' : 'Add another time')),
        const _Section('Kitchen temperature'),
        _Panel(children: [
          Row(children: [
            SizedBox(height: 152, width: 48, child: RotatedBox(quarterTurns: 3, child: Slider(
              value: kitchenTemperature, min: 0, max: 40, divisions: 40,
              label: '${kitchenTemperature.round()}°C',
              semanticFormatterCallback: (value) => '${value.round()} degrees Celsius',
              onChanged: busy ? null : (value) => setState(() => kitchenTemperature = value),
            ))),
            const SizedBox(height: 134, child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('40°C'), Text('0°C')])),
            const SizedBox(width: 18),
            Expanded(child: Text('${kitchenTemperature.round()}°C', style: Theme.of(context).textTheme.headlineSmall)),
          ]),
        ]),
        if (needsStarter) ...[
          const _Section('Starter'),
          DropdownButtonFormField<String>(initialValue: selectedStarter?.id ?? '', isExpanded: true,
            decoration: const InputDecoration(labelText: 'Which starter will you use?'),
            items: [
              const DropdownMenuItem(value: '', child: Text('No saved starter')),
              for (final jar in starters) DropdownMenuItem(value: jar.id, child: Text(jar.text('name'))),
            ],
            onChanged: busy ? null : (value) => setState(() => starterId = value == '' ? null : value),
          ),
        ],
        const _Section('Batch size'),
        Row(children: [
          const Expanded(child: Text('Recipe yield')),
          IconButton(tooltip: 'Smaller batch', onPressed: busy || scale <= .25 ? null : () => setState(() => scale -= .25), icon: const Icon(Icons.remove_circle_outline)),
          Text('${scale.toStringAsFixed(2)}×'),
          IconButton(tooltip: 'Larger batch', onPressed: busy || scale >= 1 ? null : () => setState(() => scale += .25), icon: const Icon(Icons.add_circle_outline)),
        ]),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Kitchen equipment'),
          subtitle: Text('${store.preference('ovenCapacity', 1)} oven batch capacity'),
          trailing: const Icon(Icons.chevron_right),
          onTap: busy ? null : () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(store: store)));
            if (mounted) setState(() {});
          }),
        CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Add to shopping list'),
          value: shopping, onChanged: busy ? null : (value) => setState(() => shopping = value ?? false)),
      ])),
      KitchenActions(children: [
        FilledButton(onPressed: busy || selected == null || scale > 1 ? null : () => _review(selected),
          child: Text(busy ? 'Checking schedule…' : 'Review bake')),
      ]),
    ]);
    return widget.standalone ? Scaffold(appBar: AppBar(title: const Text('Bake setup')), body: body) : body;
  }
}


class BakeDetail extends StatefulWidget {
  const BakeDetail({super.key, required this.store, required this.id});
  final AppStore store;
  final String id;
  @override
  State<BakeDetail> createState() => _BakeDetailState();
}
class _BakeDetailState extends State<BakeDetail> {
  bool reviewing = false;

  Future<void> _adjust(AppRecord bake, DateTime suggested) async {
    if (reviewing) return;
    setState(() => reviewing = true);
    try {
      final away = await _askTimeAway(context, suggested);
      if (away == null || !mounted) return;
      final store = widget.store;
      await _run(context, () async {
        final minimum = DateTime.now().toUtc().add(const Duration(minutes: 2));
        final planned = bake.date('startAt');
        final anchor = bake.text('state') == 'planned' && planned != null && planned.isAfter(minimum)
          ? planned : minimum;
        final proposal = reviewRemainingBake(store, bake, anchor, away);
        final accepted = await reviewScheduleOptions(context, proposal.recipe, proposal.candidates,
          scale: bake.number('scale', 1).toDouble(), replan: true, warning: proposal.warning);
        if (accepted == null || !mounted) return;
        final current = store.find(bake.id);
        if (current == null || current.revision != bake.revision || !anchor.isAfter(DateTime.now())) {
          throw StateError('This timeline changed. Open time away again to refresh the schedule.');
        }
        final rechecked = reviewRemainingBake(store, current, anchor, away);
        await store.saveBakeSchedule(current, updatedBakeSchedule(current, rechecked, accepted));
      });
    } finally {
      if (mounted) setState(() => reviewing = false);
    }
  }

  Future<void> _complete(AppRecord bake, int index, {required bool finalStep, DateTime? occurredAt}) async {
    if (recording) return;
    setState(() => recording = true);
    try {
      await _run(context, () => widget.store.completeStep(bake.id, expectedIndex: index, occurredAt: occurredAt));
    } finally {
      if (mounted) setState(() => recording = false);
    }
    if (mounted && !finalStep && widget.store.find(bake.id)?.number('stepIndex') == index + 1) {
      _goTo(index + 1);
    }
    if (!mounted || !finalStep || widget.store.find(bake.id)?.text('state') != 'complete') return;
    final photo = await showModalBottomSheet<bool>(context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Save a photo of your bake?', style: Theme.of(sheet).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Keep a photo in your journal to see how this bake turned out.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Add photo')),
          TextButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('Later')),
        ]),
      )));
    if (photo == true && mounted) _open(context, ObservationCaptureScreen(
      store: widget.store, objectId: bake.id, starter: false, outcomePhoto: true));
  }
  Future<void> _finish(AppRecord bake) async {
    final fields = await _form(context, 'Bake notes', [
      _Field('rating', 'Rating (1–5, optional)', numeric: true, required: false, initial: bake.text('rating')),
      _Field('notes', 'What would you do next time?', multiline: true, required: false, initial: bake.text('notes')),
    ], submit: 'Save note');
    if (fields == null || !mounted) return;
    await _run(context, () async {
      final rating = double.tryParse(fields['rating']!);
      if (rating != null && (!rating.isFinite || rating < 1 || rating > 5)) {
        throw const FormatException('Enter a rating between 1 and 5.');
      }
      final latest = widget.store.find(bake.id);
      if (latest == null) return;
      await widget.store.save('bake', {...latest.fields, 'rating': rating, 'notes': fields['notes']}, id: bake.id);
    }, success: 'Note saved.');
  }

  void _repeat(AppRecord bake) {
    final snapshot = bake.fields['recipeSnapshot'];
    if (snapshot is Map) {
      _open(context, PlanScreen(store: widget.store, initialRecipe: Map<String, dynamic>.from(snapshot),
        initialScale: bake.number('scale', 1).toDouble(), standalone: true));
    }
  }

  late final PageController pages;
  late int visible;
  late final Timer _clock;
  bool recording = false;

  @override
  void initState() {
    super.initState();
    final bake = widget.store.find(widget.id);
    final steps = _maps(bake?.fields['steps']);
    visible = steps.isEmpty ? 0 : (bake?.number('stepIndex').toInt() ?? 0).clamp(0, steps.length - 1);
    pages = PageController(initialPage: visible);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    pages.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (!pages.hasClients) return;
    unawaited(pages.animateToPage(page, duration: const Duration(milliseconds: 220), curve: Curves.easeOut));
  }

  Future<void> _settings(AppRecord bake, List<Map<String, dynamic>> steps, int current) async {
    final isPinned = _isPinned(widget.store, bake);
    final choice = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(leading: const Icon(Icons.event_note_outlined), title: const Text('Bake timeline'),
          onTap: () => Navigator.pop(sheet, 'timeline')),
        ListTile(leading: const Icon(Icons.scale_outlined), title: const Text('Ingredients'),
          onTap: () => Navigator.pop(sheet, 'ingredients')),
        ListTile(leading: const Icon(Icons.event_busy_outlined), title: const Text('Add time away'),
          onTap: reviewing ? null : () => Navigator.pop(sheet, 'away')),
        ListTile(leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
          title: Text(isPinned ? 'Unpin bake' : 'Pin bake'), onTap: () => Navigator.pop(sheet, 'pin')),
        ListTile(leading: const Icon(Icons.history), title: const Text('I finished this step earlier'),
          onTap: current >= steps.length ? null : () => Navigator.pop(sheet, 'earlier')),
      ])));
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'away':
        await _adjust(bake, DateTime.now().add(const Duration(hours: 1)));
      case 'pin':
        await _run(context, () => widget.store.setPreference('todayPin.${bake.id}', !isPinned));
      case 'earlier':
        final at = await _pickLocalTime(context, DateTime.now(), allowPast: true);
        if (at != null && mounted) await _complete(bake, current,
          finalStep: current == steps.length - 1, occurredAt: at);
      case 'timeline':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Bake timeline')),
          body: KitchenPage(children: [
            for (final (i, step) in steps.indexed) KitchenTimelineEntry(
              at: _stepDue(bake, step, i), title: _str(step['title'], 'Step ${i+1}'),
              done: i < current, detail: i == current ? 'Current step' : null,
              last: i == steps.length - 1,
            ),
          ]),
        )));
      case 'ingredients':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Ingredients')),
          body: KitchenPage(children: [
            if (bake.text('starterName').isNotEmpty)
              ListTile(contentPadding: EdgeInsets.zero, title: const Text('Selected starter'),
                subtitle: Text(bake.text('starterName'))),
            for (final item in _maps(bake.fields['ingredients']))
              ListTile(contentPadding: EdgeInsets.zero,
                title: Text(_str(item['name'], _str(item['ingredientId']))),
                trailing: Text(_grams(_ingredientGrams(item)))),
          ]),
        )));
    }
  }

  void _photo(AppRecord bake) => _open(context, ObservationCaptureScreen(
    store: widget.store, objectId: bake.id, starter: false, outcomePhoto: true));

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) {
    final bake = widget.store.find(widget.id);
    if (bake == null) return Scaffold(appBar: AppBar(title: const Text('Bake')),
      body: const Center(child: Text('This bake is unavailable.')));
    final steps = _maps(bake.fields['steps']);
    final current = bake.number('stepIndex').toInt().clamp(0, steps.length);
    final observations = widget.store.records('observation').where((o) => o.text('objectId') == bake.id).toList();
    final complete = bake.text('state', bake.text('status')) == 'complete';
    if (complete || steps.isEmpty || current == steps.length) {
      return _journalBake(bake, steps, observations);
    }
    final view = visible.clamp(0, steps.length - 1);
    final now = DateTime.now();
    final nextDue = bake.date('nextStepDueAt');
    final plannedStart = bake.date('startAt') ?? now;
    final rawFinish = _maps(bake.fields['schedule'] is Map ? (bake.fields['schedule'] as Map)['tasks'] : null)
      .map((task) => DateTime.tryParse(_str(task['end']))).whereType<DateTime>()
      .fold<DateTime?>(null, (latest, value) => latest == null || value.isAfter(latest) ? value : latest);
    final previousPlanned = current == 0 ? null : DateTime.tryParse(_str(steps[current - 1]['plannedEnd']));
    final recorded = bake.date('progressedAt');
    final updated = bake.date('scheduleUpdatedAt');
    final progressed = recorded != null && (updated == null || !recorded.isBefore(updated)) ? recorded : null;
    final finish = rawFinish == null ? null :
      (progressed != null && previousPlanned != null ? rawFinish.add(progressed.difference(previousPlanned)) : rawFinish);
    final started = bake.date('startedAt') ?? plannedStart;
    final total = finish?.difference(started).inSeconds ?? 0;
    final fraction = total <= 0 ? 0.0 : (now.difference(started).inSeconds / total).clamp(0.0, 1.0);
    final photoCount = observations.where((observation) => observation.fields['photo'] is Map).length;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final timeLeft = finish == null ? '—' : _bakeClock(finish.difference(now));
    return Scaffold(
      appBar: AppBar(title: Text(bake.text('name', 'Your bake'), maxLines: 1, overflow: TextOverflow.ellipsis), actions: [
        IconButton(tooltip: 'Bake settings', onPressed: () => _settings(bake, steps, current),
          icon: const Icon(Icons.settings_outlined)),
      ]),
      body: SafeArea(bottom: false, child: Column(children: [
        const SizedBox(height: 6),
        Text(finish != null && !finish.isAfter(now) ? 'Past estimated finish' : 'Estimated time to finish',
          style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Semantics(label: 'Estimated time until ready $timeLeft', excludeSemantics: true,
          child: SizedBox.square(dimension: 96, child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: CircularProgressIndicator(value: fraction,
              strokeWidth: 7, backgroundColor: colors.outlineVariant)),
            Padding(padding: const EdgeInsets.all(13), child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(timeLeft, style: theme.textTheme.titleMedium))),
          ]))),
        Padding(padding: const EdgeInsets.only(top: 6), child: Text('Step ${view + 1} / ${steps.length}')),
        if (nextDue != null) Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: Card(margin: EdgeInsets.zero, child: ListTile(
            dense: true, leading: const Icon(Icons.timer_outlined),
            title: Text(nextDue.isAfter(now) ? 'Next step in ${_bakeClock(nextDue.difference(now))}' : 'Next step is due'),
            subtitle: Text(_str(steps[current]['title'], 'Current step')),
          )),
        ),
        Expanded(child: PageView.builder(
          controller: pages, itemCount: steps.length, onPageChanged: (value) => setState(() => visible = value),
          itemBuilder: (context, i) {
            final step = steps[i];
            final done = i < current;
            final future = i > current;
            final color = done
              ? (theme.brightness == Brightness.dark ? const Color(0xff29432d) : const Color(0xffd9ead9))
              : future ? colors.surfaceContainerHighest : colors.secondaryContainer;
            final cue = _str(step['readinessCue'] ?? step['cues']);
            return KitchenPage(scrollKey: PageStorageKey('bake-step-${step['id']}'), children: [
              Card(color: color, margin: EdgeInsets.zero, child: Padding(
                padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(done ? 'Completed' : future ? 'Upcoming' : 'Current step', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(_str(step['title'], _str(step['name'], 'Step ${i + 1}')), style: theme.textTheme.titleLarge),
                ]),
              )),
              const SizedBox(height: 14),
              Text('Task', style: theme.textTheme.titleSmall),
              const SizedBox(height: 5),
              Text(_str(step['instructions'], _str(step['instruction']))),
              if (cue.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('What to look for', style: theme.textTheme.titleSmall),
                const SizedBox(height: 5),
                Text(cue),
              ],
            ]);
          },
        )),
      ])),
      bottomNavigationBar: SafeArea(top: false, minimum: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(children: [
          IconButton(tooltip: 'Previous step', onPressed: view > 0 ? () => _goTo(view - 1) : null,
            icon: const Icon(Icons.arrow_back_rounded)),
          Expanded(child: _BakeAction(label: 'Help', icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => _open(context, BakeCoachScreen(
              recipe: bake.text('name', 'Your bake'), step: _str(steps[view]['title'], 'Step ${view + 1}'))))),
          Expanded(child: _BakeAction(label: 'Photo', icon: Badge(isLabelVisible: photoCount > 0,
            label: Text('$photoCount'), child: const Icon(Icons.photo_camera_outlined)),
            onPressed: () => _photo(bake))),
          Expanded(child: _BakeAction(label: 'Completed', icon: const Icon(Icons.check_circle_outline),
            onPressed: view == current && !recording && !reviewing &&
                (bake.text('state') != 'planned' || !now.isBefore(plannedStart)) ?
              () => _complete(bake, current, finalStep: current == steps.length - 1) : null)),
          IconButton(tooltip: 'Next step', onPressed: view < steps.length - 1 ? () => _goTo(view + 1) : null,
            icon: const Icon(Icons.arrow_forward_rounded)),
        ]),
      ),
    );
  });

  Widget _journalBake(AppRecord bake, List<Map<String, dynamic>> steps, List<AppRecord> observations) {
    return Scaffold(
      appBar: AppBar(title: Text(bake.text('name', 'Your bake'))),
      bottomNavigationBar: KitchenActions(children: [
        OutlinedButton(onPressed: () => _photo(bake), child: const Text('Add photo')),
        if (bake.fields['recipeSnapshot'] is Map)
          FilledButton(onPressed: () => _repeat(bake), child: const Text('Bake again')),
      ]),
      body: KitchenPage(children: [
        const ListTile(leading: CrumbArt(size: 48), title: Text('Saved to your journal')),
        if (bake.text('notes').isNotEmpty) Text(bake.text('notes')),
        TextButton(onPressed: () => _finish(bake),
          child: Text(bake.text('notes').isEmpty ? 'Add note' : 'Edit note')),
        for (final observation in observations) ...[
          if (observation.fields['photo'] case final Map photo)
            _LocalPhotoView(metadata: Map<String, dynamic>.from(photo), label: 'Your saved bake photo'),
          if (observation.text('texture').isNotEmpty) Text(observation.text('texture')),
          if (observation.fields['photo'] is Map)
            TextButton(onPressed: () => _removeObservationPhoto(context, widget.store, observation),
              child: const Text('Remove photo')),
        ],
        ExpansionTile(title: const Text('Full method'), children: [
          for (final (index, step) in steps.indexed)
            ListTile(title: Text(_str(step['title'], 'Step ${index + 1}')),
              subtitle: Text(_str(step['instructions'], _str(step['instruction'])))),
        ]),
        TextButton(onPressed: () => _open(context, TextExport(title: 'Bake record',
          text: const JsonEncoder.withIndent('  ').convert(bake.fields))), child: const Text('Export this bake')),
      ]),
    );
  }
}

class _BakeAction extends StatelessWidget {
  const _BakeAction({required this.label, required this.icon, this.onPressed});
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final text = MediaQuery.textScalerOf(context).scale(11) <= 17;
    return Tooltip(message: label, excludeFromSemantics: text, child: TextButton(
      onPressed: onPressed, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        icon,
        if (text) Text(label, maxLines: 1, style: const TextStyle(fontSize: 11)),
      ]),
    ));
  }
}

String _bakeClock(Duration time) {
  final seconds = time.inSeconds.clamp(0, 99999999);
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600 ? '${seconds ~/ 3600}:$minutes:$tail' : '$minutes:$tail';
}


DateTime _stepDue(AppRecord bake, Map<String, dynamic> step, int index) {
  final due = bake.date('nextStepDueAt');
  if (index == bake.number('stepIndex').toInt() && due != null) return due;
  final startedAt = bake.date('startedAt');
  if (index == 0 && startedAt != null) return startedAt;
  final key = ['wait', 'check'].contains(step['kind']) ? 'plannedEnd' : 'plannedStart';
  return DateTime.tryParse(_str(step[key])) ?? bake.date('startAt') ?? bake.updatedAt;
}


List<AppRecord> _activeTimers(AppStore store) =>
    store.records('timer').where((timer) => timer.text('state') == 'running').toList()
      ..sort((a, b) => (a.date('dueAt') ?? a.updatedAt).compareTo(b.date('dueAt') ?? b.updatedAt));

Future<void> _createTimer(BuildContext context, AppStore store, {AppRecord? bake, Map<String, dynamic>? step}) async {
  final form = await _form(
    context,
    step == null ? 'Set a timer' : 'Set step timer',
    [
      _Field('name', 'Timer name', initial: _str(step?['title'])),
      _Field('minutes', 'Duration (minutes)',
        initial: _num(step?['durationMinutes']) > 0 ? _str(step?['durationMinutes']) : '30',
        numeric: true),
    ],
    explanation: 'The deadline is saved on this device. Alerts depend on your notification settings.',
  );
  if (form == null || !context.mounted) return;
  await _run(context, () async {
    final seconds = double.parse(form['minutes']!) * 60;
    final startedAt = DateTime.now().toUtc();
    final latestDate = DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true);
    if (!seconds.isFinite || seconds < 1 || seconds > latestDate.difference(startedAt).inSeconds) {
      throw const FormatException('Enter a duration of at least one second that fits on the calendar.');
    }
    final duration = Duration(seconds: seconds.round());
    await store.save('timer', {
      'name': form['name'],
      if (bake != null) 'bakeId': bake.id,
      if (bake != null) 'bakeName': bake.text('name'),
      if (_str(step?['id']).isNotEmpty) 'stepId': step!['id'],
      'startedAt': startedAt.toIso8601String(),
      'durationSeconds': duration.inSeconds,
      'dueAt': startedAt.add(duration).toIso8601String(),
      'state': 'running',
    });
  }, success: 'Timer deadline saved.');
}

Future<void> _presetTimer(BuildContext context, AppStore store, String name, int minutes) async {
  await _run(context, () async {
    final start = DateTime.now().toUtc();
    await store.save('timer', {
      'name': name, 'state': 'running', 'startedAt': start.toIso8601String(),
      'durationSeconds': minutes * 60,
      'dueAt': start.add(Duration(minutes: minutes)).toIso8601String(),
    });
  }, success: 'Timer started');
}

class TimerCentreScreen extends StatelessWidget {
  const TimerCentreScreen({super.key, required this.store, this.focusedTimerId});

  final AppStore store;
  final String? focusedTimerId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Timers')),
    bottomNavigationBar: KitchenActions(children: [
      FilledButton.icon(onPressed: () => _createTimer(context, store),
        icon: const Icon(Icons.add_alarm), label: const Text('New timer')),
    ]),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final active = _activeTimers(store);
        final timers = [
          ...active.where((timer) => timer.id == focusedTimerId),
          ...active.where((timer) => timer.id != focusedTimerId),
        ];
        return KitchenPage(children: [
          for (final timer in timers)
            _TimerCard(key: ValueKey(timer.id), store: store, timer: timer),
          const _Section('Quick timers'),
          for (final (name, minutes) in const [
            ('Rest after mixing', 30), ('Between stretch and folds', 30),
            ('Bench rest before shaping', 20), ('Oven preheat', 40),
          ]) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.timer_outlined),
            title: Text(name), subtitle: Text('$minutes min'),
            trailing: IconButton(tooltip: 'Start $name timer', icon: const Icon(Icons.play_circle_outline),
              onPressed: () => _presetTimer(context, store, name, minutes))),
        ]);
      },
    ),
  );
}

class _TimerCard extends StatefulWidget {
  const _TimerCard({super.key, required this.store, required this.timer});
  final AppStore store;
  final AppRecord timer;
  @override State<_TimerCard> createState()=>_TimerCardState();
}
class _TimerCardState extends State<_TimerCard> {
  Timer? ticker;
  bool saving = false;
  @override void initState(){super.initState();ticker=Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState((){});});}
  @override void dispose(){ticker?.cancel();super.dispose();}

  Future<void> _update({Duration? snooze}) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await _run(context, () async {
        final timer = widget.store.find(widget.timer.id);
        if (timer == null || timer.text('state') != 'running' ||
            timer.revision != widget.timer.revision) {
          throw StateError('This timer changed. Review its current deadline.');
        }
        final now = DateTime.now().toUtc();
        final fields = snooze == null
            ? {'state': 'acknowledged', 'acknowledgedAt': now.toIso8601String()}
            : {
                'originalDueAt': timer.fields['originalDueAt'] ?? timer.fields['dueAt'],
                'dueAt': now.add(snooze).toIso8601String(),
                'snoozedAt': now.toIso8601String(),
              };
        await widget.store.save('timer', {...timer.fields, ...fields}, id: timer.id);
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override Widget build(BuildContext context) {
    final timer = widget.timer;
    final now = DateTime.now();
    final remaining = timer.date('dueAt')?.difference(now);
    final overdue = remaining != null && remaining <= Duration.zero;
    final seconds = remaining?.inSeconds.abs() ?? 0;
    final clock = '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final subject = timer.text('bakeName', timer.text('starterName'));
    return _Panel(children: [
      Text(timer.text('name'), style: Theme.of(context).textTheme.titleMedium),
      if (subject.isNotEmpty) Text(subject),
      Text(
        remaining == null ? 'Deadline unavailable' : overdue ? 'Check due · $clock elapsed' : 'Due in $clock',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text('Saved deadline: ${_date(timer.fields['dueAt'])}'),
      if (timer.date('originalDueAt') != null)
        Text('Original deadline: ${_date(timer.fields['originalDueAt'])}'),
      Wrap(spacing: 8, children: [
        TextButton(
          onPressed: saving ? null : () => _update(),
          child: const Text('Acknowledge timer'),
        ),
        if (overdue)
          TextButton(
            onPressed: saving ? null : () => _update(snooze: const Duration(minutes: 5)),
            child: const Text('Snooze 5 min'),
          ),
      ]),
    ]);
  }
}

class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key, required this.store, required this.bakeId});
  final AppStore store;
  final String bakeId;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Plans changed')), body: KitchenPage(children: [
    const _Notice('Completed actions stay as recorded. Refrigeration slows fermentation; it does not pause it. An unvalidated method cannot offer a tested rescue branch.'),
    FilledButton(onPressed: () async {
      final f = await _form(context, 'Record an interruption', const [_Field('change', 'What changed?', multiline: true), _Field('until', 'Unavailable until (optional ISO date)', required: false)], explanation: 'Keep a durable note against this bake. No completed step or accepted timing will be silently moved.');
      if (f != null && context.mounted) await _run(context, () async {await store.save('interruption', {'bakeId': bakeId, ...f, 'occurredAt': DateTime.now().toUtc().toIso8601String()});}, success: 'Interruption recorded; your original plan is preserved.');
    }, child: const Text('Record what changed')),
    const _Section('Choose an honest next step'),
    const Text('Check the dough and its full method. If the method’s supported range cannot fit, change your target or bake day. The draft library does not yet contain kitchen-tested recovery branches.'),
    OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Return to dough and record an observation')),
    OutlinedButton(onPressed: () => _open(context, PlanScreen(store: store, standalone: true)), child: const Text('Plan a separate bake')),
  ]));
}

class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key, required this.store});
  final AppStore store;

  Future<void> _addPhoto(BuildContext context, List<AppRecord> bakes) async {
    final target = await showModalBottomSheet<String>(context: context,
      showDragHandle: true, isScrollControlled: true,
      builder: (sheet) => SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .65),
        child: ListView(shrinkWrap: true, children: [
          ListTile(leading: const Icon(Icons.add), title: const Text('New journal entry'),
            onTap: () => Navigator.pop(sheet, 'new')),
          for (final bake in bakes)
            ListTile(leading: const Icon(Icons.bakery_dining_outlined), title: Text(bake.text('name')),
              subtitle: Text(_date(bake.fields['completedAt'])), onTap: () => Navigator.pop(sheet, bake.id)),
        ]),
      )));
    if (target == null || !context.mounted) return;
    if (target == 'new') {
      final details = await _form(context, 'New journal entry', const [
        _Field('name', 'What did you bake?'),
        _Field('note', 'Note (optional)', multiline: true, required: false),
      ], submit: 'Continue to photo');
      if (details == null || !context.mounted) return;
      await _run(context, () async {
        final now = DateTime.now().toUtc().toIso8601String();
        final bake = await store.save('bake', {
          'name': details['name'], 'notes': details['note'], 'state': 'complete',
          'status': 'complete', 'completedAt': now,
        });
        if (context.mounted) _open(context, ObservationCaptureScreen(
          store: store, objectId: bake.id, starter: false, outcomePhoto: true));
      });
    } else {
      _open(context, ObservationCaptureScreen(store: store, objectId: target, starter: false, outcomePhoto: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bakes = store.records('bake').where((b) => b.text('state', b.text('status')) == 'complete').toList()
      ..sort((a, b) => (b.date('completedAt') ?? b.updatedAt).compareTo(a.date('completedAt') ?? a.updatedAt));
    final photoRecords = store.records('observation').where((o) => o.fields['photo'] is Map).toList()
      ..sort((a, b) => (b.date('occurredAt') ?? b.updatedAt).compareTo(a.date('occurredAt') ?? a.updatedAt));
    final photos = <String, Map<String, dynamic>>{};
    for (final observation in photoRecords) {
      photos.putIfAbsent(observation.text('objectId'),
        () => Map<String, dynamic>.from(observation.fields['photo'] as Map));
    }
    return Column(children: [
      Expanded(child: KitchenPage(children: [
      if (bakes.isEmpty) const _Panel(children: [
        Row(children: [
          CrumbArt(size: 64), SizedBox(width: 12),
          Expanded(child: Text('Your finished bakes will appear here.')),
        ]),
      ]),
      for (final bake in bakes) Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: () => _open(context, BakeDetail(store: store, id: bake.id)),
          leading: photos.containsKey(bake.id)
            ? SizedBox(width: 48, child: _LocalPhotoView(metadata: photos[bake.id]!, label: 'Bake photo', thumbnail: true))
            : const Icon(Icons.bakery_dining_outlined),
          title: Text(bake.text('name')),
          subtitle: Text([
            _date(bake.date('completedAt') ?? bake.updatedAt),
            if (bake.text('notes').isNotEmpty) bake.text('notes'),
          ].join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
      ExpansionTile(title: const Text('Journal tools'), children: [
        if (bakes.length > 1) ListTile(leading: const Icon(Icons.compare_arrows), title: const Text('Compare two bakes'),
          onTap: () => _open(context, JournalInsightsScreen(store: store))),
        ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('Create a recipe book'),
          onTap: () => _open(context, JournalBookScreen(store: store))),
        ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('Export kitchen archive'),
          onTap: () => _run(context, () async {
            final archive = await store.exportArchive();
            if (context.mounted) _open(context, TextExport(title: 'Kitchen archive', text: archive));
          })),
      ]),
      ])),
      KitchenActions(children: [
        FilledButton.icon(onPressed: () => _addPhoto(context, bakes),
          icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add photo')),
      ]),
    ]);
  }
}


class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<CompareScreen> createState() => _CompareScreenState();
}
class _CompareScreenState extends State<CompareScreen> {
  String? a, b;
  @override
  Widget build(BuildContext context) {
    final all = widget.store.records('bake').where((r) => r.text('state') == 'complete').toList();
    final left = all.where((r) => r.id == a).firstOrNull, right = all.where((r) => r.id == b).firstOrNull;
    return Scaffold(appBar: AppBar(title: const Text('What changed?')), body: KitchenPage(children: [
      const _Notice('Comparison shows recorded differences, not proof of a cause. Missing observations stay unknown.'),
      for (final first in [true, false]) Padding(padding: const EdgeInsets.only(bottom: 16), child: DropdownButtonFormField<String>(initialValue: first ? a : b, isExpanded: true, decoration: InputDecoration(labelText: first ? 'Baseline bake' : 'Comparison bake'), items: all.map((r) => DropdownMenuItem(value: r.id, child: Text('${r.text('name')} · ${_date(r.fields['completedAt'])}', overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() {if (first) {a = v;} else {b = v;}}))),
      if (left != null && right != null) ...[
        _Panel(children: [Text('Formula', style: Theme.of(context).textTheme.titleLarge), for (final key in ['hydrationPercent', 'scale', 'rating']) Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [Expanded(child: Text(key)), Expanded(child: Text(left.text(key, 'Not recorded'))), Expanded(child: Text(right.text(key, 'Not recorded')))]))]),
        for (final item in [left, right]) _Panel(children: [Text(item.text('name'), style: Theme.of(context).textTheme.titleMedium), Text('Started: ${_date(item.fields['startAt'])}'), Text('Finished: ${_date(item.fields['completedAt'])}'), Text(item.text('notes', 'No outcome note')), Text('${widget.store.records('observation').where((o) => o.text('objectId') == item.id).length} observations')]),
        FilledButton(onPressed: () => _run(context, () => widget.store.setPreference('baselineBakeId', left.id), success: 'Baseline selected for future comparisons.'), child: const Text('Use the first bake as my baseline')),
        OutlinedButton(onPressed: () async {final f = await _form(context, 'Try one change', const [_Field('variable', 'One variable to change'), _Field('hypothesis', 'What would you like to learn?', multiline: true)], explanation: 'Other conditions may still differ. Record them rather than claiming a controlled result.'); if (f != null && context.mounted) await _run(context, () async {await widget.store.save('experiment', {'baselineBakeId': left.id, 'comparisonBakeId': right.id, ...f, 'name': f['variable']});}, success: 'Experiment record saved.');}, child: const Text('Record an experiment')),
      ],
    ]));
  }
}

class KitchenScreen extends StatelessWidget {
  const KitchenScreen({super.key, required this.store, this.servicesBuilder});
  final AppStore store;
  final WidgetBuilder? servicesBuilder;

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<(IconData, String, WidgetBuilder)>)>[
      ('Baking tools', [
        (Icons.timer_outlined, 'Timers', (_) => TimerCentreScreen(store: store)),
        (Icons.water_drop_outlined, 'Feed calculator', (_) => const KitchenCalculatorScreen(KitchenCalculator.feed)),
        (Icons.show_chart, 'Rise forecast', (_) => const KitchenCalculatorScreen(KitchenCalculator.rise)),
        (Icons.calculate_outlined, 'Hydration calculator', (_) => const KitchenCalculatorScreen(KitchenCalculator.hydration)),
        (Icons.school_outlined, 'Guides', (_) => LearnScreen(store: store)),
      ]),
      ('Kitchen management', [
        (Icons.shopping_basket_outlined, 'Pantry & shopping', (_) => CollectionScreen(store: store, kind: 'pantry', title: 'Pantry & shopping')),
      ]),
      ('Account & sharing', [
        if (servicesBuilder != null) (Icons.cloud_outlined, 'Connected services', servicesBuilder!),
        (Icons.group_outlined, 'Shared kitchen', (_) => ServiceStatusScreen(store: store, service: 'Shared kitchen')),
        (Icons.forum_outlined, 'Community', (_) => ServiceStatusScreen(store: store, service: 'Community')),
        (Icons.chat_bubble_outline, 'Coach', (_) => ServiceStatusScreen(store: store, service: 'Coach')),
        (Icons.privacy_tip_outlined, 'Data & privacy', (_) => PrivacyScreen(store: store)),
        (Icons.settings_outlined, 'Settings', (_) => SettingsScreen(store: store)),
      ]),
    ];
    return KitchenPage(children: [
      for (final (group, items) in groups) ...[
        _Section(group),
        Card(margin: EdgeInsets.zero, child: Column(children: [
          for (final (icon, title, builder) in items)
            ListTile(leading: Icon(icon), title: Text(title), trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: builder))),
        ])),
      ],
    ]);
  }
}


class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.store, required this.kind, required this.title});
  final AppStore store;
  final String kind, title;
  Future<void> _add(BuildContext context, {AppRecord? original}) async {
    final f = await _form(context, original == null ? 'Add ${kind == 'discard' ? 'discard lot' : 'ingredient lot'}' : 'Edit lot details', [
      _Field('name', 'Ingredient / lot name', initial: original?.text('name') ?? ''),
      if (original == null) const _Field('grams', 'Recorded amount (g)', numeric: true),
      _Field('price', 'Pack price (optional)', initial: original?.text('price') ?? '', numeric: true, required: false),
      _Field('currency', 'Currency', initial: original?.text('currency') ?? '', required: false),
      _Field('note', 'Storage, date, flour or allergy notes', initial: original?.text('note') ?? '', multiline: true, required: false),
    ], explanation: 'Enter your own measured stock and prices. Amount or age does not certify that an ingredient or discard is safe.');
    if (f != null && context.mounted) await _run(context, () async {
      final current = original == null ? null : store.find(original.id);
      if (original != null && current == null) throw StateError('This lot has been removed.');
      await store.save(kind, {
        ...?current?.fields, ...f,
        if (original == null) 'grams': double.parse(f['grams']!),
        'price': double.tryParse(f['price']!),
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      }, id: original?.id);
    }, success: 'Lot saved.');
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: store, builder: (context, _) => Scaffold(appBar: AppBar(title: Text(title)), body: KitchenPage(children: [
    FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add), label: Text(kind == 'discard' ? 'Add discard lot' : 'Add ingredient lot')),
    const _Notice('Planned demand and actual consumption are separate. Stock changes only when you record it; planning does not mean an ingredient has been used.'),
    for (final lot in store.records(kind)) _Panel(children: [Text(lot.text('name'), style: Theme.of(context).textTheme.titleLarge), Text(_grams(lot.fields['grams']??lot.fields['quantity'])), if (lot.fields['price'] != null) Text('Recorded price ${lot.text('currency')} ${lot.fields['price']}'), if (lot.text('note').isNotEmpty) Text(lot.text('note')), Wrap(spacing: 8, children: [
      TextButton(onPressed: () => _changeStock(context, store, lot), child: const Text('Correct stock weight')),
      TextButton(onPressed: () => _changeStock(context, store, lot, withdrawal: true), child: const Text('Record stock used')),
      TextButton(onPressed: () => _add(context, original: lot), child: const Text('Edit lot details')),
      TextButton(onPressed: () => _run(context, () async {await store.save('shopping', {'name': lot.text('name'), 'checked': false});}, success: 'Added to shopping list.'), child: const Text('Add to shopping')),
    ])]),
    const _Section('Shopping list'),
    OutlinedButton(onPressed: () async {final f = await _form(context, 'Add shopping item', const [_Field('name', 'Ingredient and amount')]); if (f != null && context.mounted) await _run(context, () async {await store.save('shopping', {'name': f['name'], 'checked': false});});}, child: const Text('Add an item')),
    for (final item in store.records('shopping')) CheckboxListTile(contentPadding: EdgeInsets.zero,
      title: Text(item.text('name')),
      subtitle: item.fields['grams'] == null ? null : Text('${_grams(item.fields['grams'])} · ${item.text('bakeName')}'),
      value: item.flag('checked'), onChanged: (v) => _run(context, () async {
        await store.save('shopping', {...item.fields, 'checked': v}, id: item.id);
      })),
    if (store.records('shopping').isNotEmpty) TextButton(onPressed: () async {final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Remove checked shopping items?'), content: const Text('Unchecked items and pantry lots will stay.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep them')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove checked'))])); if (yes == true && context.mounted) await _run(context, () async {for (final item in store.records('shopping').where((i) => i.flag('checked')).toList()) {await store.remove(item.id);}});}, child: const Text('Remove checked items')),
  ])));
}

const _learningPaths = {
  'First starter': ['L01', 'L02', 'L04', 'L17'],
  'First loaf': ['L02', 'L03', 'L04', 'L05', 'L06', 'L07', 'L15', 'L16'],
};

Set<String> _practisedLessons(AppStore store) => {
  for (final record in [
    ...store.records('lesson_progress'),
    ...store.records('lessonProgress'),
  ])
    if (record.date('practisedAt') != null) record.text('lessonId'),
};

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key, required this.store, this.starterFirst = false});
  final AppStore store;
  final bool starterFirst;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(starterFirst ? 'Starter guides' : 'Guides')),
    body: ListenableBuilder(listenable: store, builder: (context, _) {
      final practised = _practisedLessons(store);
      final byId = {for (final lesson in store.lessons) lesson['id']: lesson};
      return KitchenPage(children: [
    const _Notice('Written lessons and exercises are available offline. Editorial review is pending.'),
    for (final path in _learningPaths.entries.where((path) => !starterFirst || path.key == 'First starter'))
      if (path.value.every(byId.containsKey))
        _Panel(children: [
          Text(path.key, style: Theme.of(context).textTheme.titleLarge),
          Text('${path.value.where(practised.contains).length} of ${path.value.length} exercises practised'),
          OutlinedButton(
            onPressed: () => _open(context, _LearningPathScreen(
              store: store,
              title: path.key,
              lessons: [for (final id in path.value) byId[id]!],
            )),
            child: Text('Open ${path.key.toLowerCase()} course'),
          ),
        ]),
    const _Section('Practical techniques'),
    for (final lesson in store.lessons.where((lesson) => !starterFirst || _learningPaths['First starter']!.contains(lesson['id']))) _Panel(children: [Text(_str(lesson['title']), style: Theme.of(context).textTheme.titleLarge), Text(_str(lesson['summary'])), const SizedBox(height: 12), OutlinedButton(onPressed: () => _open(context, LessonDetail(store: store, lesson: lesson)), child: const Text('Read and practise'))]),
    const _Section('Guidance and source references'),
    for (final g in store.guidance) _Panel(children: [Text(_str(g['title']), style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 10), for (final line in (g['body'] is List ? g['body'] as List : [_str(g['body'])])) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_str(line))), for (final source in _maps(g['sources'])) SelectableText('${_str(source['title'])}\n${_str(source['url'])}'), const Text('Source-linked guidance; editorial review pending.')]),
      ]);
    }),
  );
}

class _LearningPathScreen extends StatelessWidget {
  const _LearningPathScreen({required this.store, required this.title, required this.lessons});

  final AppStore store;
  final String title;
  final List<Map<String, dynamic>> lessons;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListenableBuilder(listenable: store, builder: (context, _) {
      final practised = _practisedLessons(store);
      final next = lessons.where((lesson) => !practised.contains(lesson['id'])).firstOrNull;
      return KitchenPage(children: [
        if (next != null)
          FilledButton(
            onPressed: () => _open(context, LessonDetail(store: store, lesson: next)),
            child: Text('Continue with ${next['title']}'),
          )
        else
          const _Notice('You’ve recorded practice for every exercise in this course.'),
        for (final lesson in lessons)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_str(lesson['title'])),
            subtitle: practised.contains(lesson['id']) ? const Text('Practice recorded') : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, LessonDetail(store: store, lesson: lesson)),
          ),
      ]);
    }),
  );
}
class LessonDetail extends StatelessWidget {
  const LessonDetail({super.key, required this.store, required this.lesson});
  final AppStore store;
  final Map<String, dynamic> lesson;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(_str(lesson['title']))), body: KitchenPage(children: [
    Text(_str(lesson['summary']), style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 20),
    for (final instruction in lesson['instructions'] is List ? lesson['instructions'] as List : const []) Padding(padding: const EdgeInsets.only(bottom: 18), child: Text(_str(instruction))),
    const _Section('Try it in your kitchen'),
    Text(_str(lesson['exercise'])),
    const SizedBox(height: 12),
    FilledButton(onPressed: () => _run(context, () async {await store.save('lesson_progress', {'lessonId': lesson['id'], 'name': lesson['title'], 'practisedAt': DateTime.now().toUtc().toIso8601String()});}, success: 'Practice recorded.'), child: const Text('Record that I practised')),
    const _Section('Sources'),
    for (final source in lesson['sourceUrls'] is List ? lesson['sourceUrls'] as List : const []) SelectableText(_str(source)),
    const _Notice('This lesson has written guidance. A genuine technique video and captions have not yet been produced.'),
  ]));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final AppStore store;

  Future<void> _quietHours(BuildContext context) async {
    final current = store.preference('routineQuietHours');
    final start = current is Map ? current['start'] : null;
    final end = current is Map ? current['end'] : null;
    TimeOfDay time(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    final from = await showTimePicker(context: context, initialTime: time(start is int && start >= 0 && start < 1440 ? start : 22 * 60), helpText: 'Quiet hours start');
    if (from == null || !context.mounted) return;
    final until = await showTimePicker(context: context, initialTime: time(end is int && end >= 0 && end < 1440 ? end : 7 * 60), helpText: 'Quiet hours end');
    if (until == null || !context.mounted) return;
    final startMinute = from.hour * 60 + from.minute;
    final endMinute = until.hour * 60 + until.minute;
    await _run(context, () => store.setPreference('routineQuietHours',
      startMinute == endMinute ? null : {'start': startMinute, 'end': endMinute}));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: store, builder: (context, _) => Scaffold(appBar: AppBar(title: const Text('Kitchen & preferences')), body: KitchenPage(children: [
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Dark appearance'), subtitle: const Text('Keeps the same accessible status meanings.'), value: store.darkMode, onChanged: (v) => _run(context, () => store.setPreference('darkMode', v))),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('First Loaf guidance'), subtitle: const Text('More explanations. Your recipe and actual progress stay the same.'), value: store.beginnerMode, onChanged: (v) => _run(context, () => store.setPreference('beginnerMode', v))),
    const _Section('Kitchen assumptions'),
    ListTile(contentPadding: EdgeInsets.zero, title: const Text('Room temperature'), subtitle: Text('${store.preference('roomTemperature', 23)} °C · an assumption, not a measurement'), trailing: const Icon(Icons.edit_outlined), onTap: () async {final f = await _form(context, 'Room temperature assumption', [_Field('value', 'Temperature (°C)', initial: _str(store.preference('roomTemperature', 23)), numeric: true)]); if (f != null && context.mounted) await _run(context, () => store.setPreference('roomTemperature', double.parse(f['value']!)));}),
    ListTile(contentPadding: EdgeInsets.zero, title: const Text('Oven batch capacity'), subtitle: Text('${store.preference('ovenCapacity', 1)} batch at once'), trailing: const Icon(Icons.edit_outlined), onTap: () async {final f = await _form(context, 'Oven capacity', [_Field('value', 'Concurrent batch slots', initial: _str(store.preference('ovenCapacity', 1)), numeric: true)], explanation: 'One Dutch oven means one batch slot unless you have validated a different setup.'); if (f == null || !context.mounted) return; final n = double.parse(f['value']!); if (n < 1 || n > 20 || n != n.roundToDouble()) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use a whole number from 1 to 20.'))); return;} await _run(context, () => store.setPreference('ovenCapacity', n.toInt()));}),
    const _Section('Reminder preferences'),
    ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Quiet hours for routine starter checks'),
      subtitle: const Text('Uses this device’s time. Quiet checks still appear on Today. Independent timers keep their alerts.'),
      onTap: () => _quietHours(context),
    ),
    if (store.preference('routineQuietHours') != null)
      TextButton(onPressed: () => _run(context, () => store.setPreference('routineQuietHours', null)),
        child: const Text('Turn quiet hours off')),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Starter care reminders'), subtitle: const Text('Preference only. Actual OS permission and scheduled reminders are shown in Connected services.'), value: store.preference('starterReminders', false) == true, onChanged: (v) => _run(context, () => store.setPreference('starterReminders', v))),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Social prompts'), subtitle: const Text('Social prompts are off by default and never cover a live-bake action.'), value: store.preference('socialPrompts', false) == true, onChanged: (v) => _run(context, () => store.setPreference('socialPrompts', v))),
    const _Notice('System text size is respected. No appearance setting can turn a timing estimate into proof of readiness. Grams and Celsius are currently the precise entry/display units.'),
    OutlinedButton(onPressed: () => _open(context, PrivacyScreen(store: store)), child: const Text('Data, consent and local storage')),
  ])));
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Data & privacy')), body: KitchenPage(children: [
    if (AppAnalytics.isConfigured) ListenableBuilder(
      listenable: store,
      builder: (context, _) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Share app usage analytics'),
        subtitle: const Text('Sends basic app and screen usage to PostHog with a random device identifier. Your account, baking records and photos stay out of these events.'),
        value: store.preference(analyticsConsentKey, false) == true,
        onChanged: (value) => _run(context, () => store.setPreference(analyticsConsentKey, value)),
      ),
    ),
    _Panel(children: [Text('Stored on this phone', style: Theme.of(context).textTheme.titleLarge), Text(store.storageDescription), const SizedBox(height: 10), const Text('Local-only data may be lost if this app is removed or your phone is lost. Export an archive if you need a portable copy. Creating an account never automatically uploads your kitchen.')]),
    FilledButton.icon(onPressed: () => _run(context, () async {final archive = await store.exportArchive(); if (context.mounted) _open(context, TextExport(title: 'Your portable kitchen archive', text: archive));}), icon: const Icon(Icons.file_download_outlined), label: const Text('Export all my local records')),
    OutlinedButton.icon(onPressed: () async {final f = await _form(context, 'Import kitchen archive', const [_Field('archive', 'Paste archive JSON', multiline: true)], explanation: 'The archive is validated before import. Keep your current export as a backup. Invalid data must not erase existing records.', submit: 'Validate and import'); if (f != null && context.mounted) await _run(context, () => store.importArchive(f['archive']!), success: 'Archive import completed.');}, icon: const Icon(Icons.file_upload_outlined), label: const Text('Import an archive')),
    const _Section('Consent is purpose-specific'),
    const _Notice('Photo analysis, microphone, Bluetooth, calendars, public sharing and cloud backup are separate choices. This screen does not request any OS permission or send your journal to a server.'),
    const _Section('Delete local kitchen'),
    const Text('Deletes starter, recipe, bake, journal and other locally stored records. An export is your own responsibility. This does not cancel a store subscription or delete an independently configured cloud account.'),
    const SizedBox(height: 12),
    OutlinedButton(onPressed: () async {final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Delete all local kitchen records?'), content: const Text('This removes the records on this device. Export your archive first. This action cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep my kitchen')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete local records'))])); if (yes == true && context.mounted) await _run(context, store.resetLocalData, success: 'Local kitchen records deleted.');}, child: const Text('Delete local records')),
    const _Section('Cloud account data'),
    const Text('Cloud export/deletion and membership changes belong to the authenticated account service. Local deletion is not a claim that remote data has been deleted.'),
  ]));
}

class ServiceStatusScreen extends StatelessWidget {
  const ServiceStatusScreen({super.key, required this.store, required this.service});
  final AppStore store;
  final String service;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(service)), body: KitchenPage(children: [
    _Panel(children: [Text('A connected service is required', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 10), Text(service == 'Coach' ? 'A coach request needs an authenticated account, configured provider and quota, and a preview of the selected recipe/observations. No whole-library upload or automatic plan mutation is allowed.' : service == 'Community' ? 'Public posting needs authenticated accounts, privacy controls and a staffed moderation/reporting service. Your local journal stays private; nothing has been published.' : 'Shared kitchens need an authenticated backend and explicit member roles. Local records are not silently shared, and an invitation cannot grant access until redeemed.'), const SizedBox(height: 14), const Text('Open Connected services in the Kitchen menu to check actual configuration and account capabilities. This screen does not pretend a remote operation succeeded.')]),
    if (service == 'Coach') OutlinedButton(onPressed: () => _open(context, LearnScreen(store: store)), child: const Text('Use offline written guidance')),
    OutlinedButton(onPressed: () => _open(context, PrivacyScreen(store: store)), child: const Text('Review data and privacy')),
  ]));
}

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Devices & reminders')), body: KitchenPage(children: [
    const _Notice('The phone remains the complete manual path. Native capability checks and permissions live in Connected services; a saved preference alone never means permission is granted.'),
    const _Section('Probe readings'),
    const Text('Only physically tested probe models can be described as supported. No compatible retail model has yet passed this release’s device matrix. Manual readings remain available below.'),
    OutlinedButton(onPressed: () async {final f = await _form(context, 'Record manual temperature', const [_Field('name', 'Sensor role: dough, room or fridge'), _Field('temperature', 'Temperature (°C)', numeric: true), _Field('note', 'Reading note', required: false)], explanation: 'A manual reading is not a live sensor stream. Old readings keep their original timestamp.'); if (f != null && context.mounted) await _run(context, () async {await store.save('sensorReading', {...f, 'source': 'manual', 'occurredAt': DateTime.now().toUtc().toIso8601String()});}, success: 'Manual reading recorded.');}, child: const Text('Record a manual reading')),
    for (final r in store.records('sensorReading')) ListTile(title: Text('${r.text('name')} · ${r.text('temperature')} °C'), subtitle: Text('${_date(r.fields['occurredAt'])} · manual, not live')),
    const _Section('Camera rise sequences'),
    const Text('A rise sequence needs a fixed marked container, baseline and user-confirmed measurements. A suspended phone cannot promise uninterrupted overnight capture. A photo cannot certify starter safety.'),
    const _Section('Watch, widget and lock screen'),
    const Text('Native extensions require signing, entitlements and real-device validation. No universal watch compatibility or guaranteed alarm delivery is claimed.'),
  ]));
}

class RecordHistoryScreen extends StatelessWidget {
  const RecordHistoryScreen({super.key, required this.store, required this.record});
  final AppStore store;
  final AppRecord record;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Recorded event')), body: KitchenPage(children: [
    SelectableText(const JsonEncoder.withIndent('  ').convert(record.fields)),
    const _Notice('History is retained. A correction note records what was wrong; it does not pretend that a later physical feed or consumed quantity can be undone.'),
    FilledButton(onPressed: () async {final f = await _form(context, 'Record a correction', const [_Field('correction', 'What should this event say?', multiline: true)], explanation: 'Keep the original event and correction together for audit. If later ingredient usage conflicts, review those physical actions before recalculating stock.'); if (f != null && context.mounted) await _run(context, () async {await store.save('correction', {'correctsId': record.id, 'name': 'Correction to ${record.kind}', ...f, 'occurredAt': DateTime.now().toUtc().toIso8601String()});}, success: 'Correction note saved alongside the original.');}, child: const Text('Add a correction note')),
    for (final c in store.records('correction').where((r) => r.text('correctsId') == record.id)) _Panel(children: [Text(_date(c.fields['occurredAt'])), Text(c.text('correction'))]),
  ]));
}

class TextExport extends StatelessWidget {
  const TextExport({super.key, required this.title, required this.text});
  final String title, text;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: KitchenPage(children: [
    const _Notice('Review the data before sharing. An exported copy can be retained by its recipient and cannot be recalled by revoking a later app link.'),
    FilledButton.icon(onPressed: () => _run(context, () async {final result = await ExportShareService().shareTextFile(fileName: 'crispy-crust-export.json', content: text, mimeType: 'application/json'); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));}), icon: const Icon(Icons.ios_share), label: const Text('Save or share this file')),
    OutlinedButton.icon(onPressed: () async {await Clipboard.setData(ClipboardData(text: text)); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard. Clear your clipboard if the data is private.')));}, icon: const Icon(Icons.copy), label: const Text('Copy text')),
    const SizedBox(height: 20),
    SelectableText(text, style: Theme.of(context).textTheme.bodySmall),
  ]));
}

class ObservationCaptureScreen extends StatefulWidget {
  const ObservationCaptureScreen({super.key, required this.store, required this.objectId, required this.starter, this.media, this.outcomePhoto = false, this.starterCover = false});
  final AppStore store;
  final String objectId;
  final bool starter;
  final bool outcomePhoto, starterCover;
  final LocalMediaService? media;
  @override State<ObservationCaptureScreen> createState() => _ObservationCaptureScreenState();
}
class _ObservationCaptureScreenState extends State<ObservationCaptureScreen> {
  late final media = widget.media ?? LocalMediaService();
  final formKey = GlobalKey<FormState>();
  final temperature = TextEditingController(), height = TextEditingController(), baseline = TextEditingController(), rise = TextEditingController(), notes = TextEditingController();
  String peak = 'unknown', error = '';
  LocalPhoto? photo;
  bool busy = false, saved = false;
  Future<void> pick(bool camera) async {
    if (busy) return;
    setState(() {busy = true; error = '';});
    try {
      final selected = await media.pickPhoto(camera: camera);
      if (!mounted) {if(selected != null) await media.delete(selected); return;}
      if (selected != null) {
        final previous = photo;
        setState(() => photo = selected);
        if (previous != null) {try {await media.delete(previous);} catch(e) {if(mounted)setState(()=>error='New photo attached. The previous unsaved file could not be cleaned up: $e');}}
      }
    } catch (e) {if(mounted)setState(() => error = 'Photo was not attached: $e. Your entered observations are still here.');}
    finally {if(mounted)setState(() => busy = false);}
  }
  Future<void> save() async {
    if(busy || !formKey.currentState!.validate()) return;
    if(temperature.text.trim().isEmpty && height.text.trim().isEmpty && rise.text.trim().isEmpty && notes.text.trim().isEmpty && photo == null && peak == 'unknown') {
      setState(() => error = 'Record at least one observation or attach a photo. Unknown values can stay empty.');return;
    }
    setState(() {busy=true;error='';});
    try {
      final metadata=photo?.toJson();
      final observation = await widget.store.save('observation',{'objectId':widget.objectId,'temperature':temperature.text.trim(),if(widget.starter)'height':height.text.trim(),if(widget.starter)'baseline':baseline.text.trim(),if(!widget.starter)'rise':rise.text.trim(),if(widget.starter)'peak':peak,widget.starter?'note':'texture':notes.text.trim(),'occurredAt':DateTime.now().toUtc().toIso8601String(),if(metadata!=null)'photo':metadata,if(photo!=null)'photoId':photo!.id});
      saved=true;
      final jar = widget.store.find(widget.objectId);
      if (widget.starterCover && jar != null) {
        try {
          await widget.store.save('starter', {...jar.fields, 'coverObservationId': observation.id}, id: jar.id);
        } catch (_) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo saved to History. The starter cover could not be set.')));
        }
      }
      if(mounted)Navigator.pop(context);
    }catch(e){if(mounted)setState(()=>error='Could not save: $e. The observation draft is still here.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override void dispose(){
    for(final c in [temperature,height,baseline,rise,notes]){c.dispose();}
    if(!saved && photo!=null)unawaited(media.delete(photo!).catchError((Object _) {}));
    super.dispose();
  }
  Widget numberField(TextEditingController controller,String label,{bool positive=false}) => Padding(padding:const EdgeInsets.only(bottom:16),child:TextFormField(controller:controller,decoration:InputDecoration(labelText:label),keyboardType:const TextInputType.numberWithOptions(decimal:true,signed:true),validator:(v){if(v==null||v.trim().isEmpty)return null;final number=double.tryParse(v);if(number==null||!number.isFinite)return 'Enter a finite number or leave unknown.';if(positive&&number<=0)return 'A measured height must be greater than zero.';if(controller==rise&&number<0)return 'Rise cannot be negative; describe falling dough in your note.';return null;}));
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.outcomePhoto ? (widget.starter ? 'Add starter photo' : 'Add bake photo') : widget.starter?'Record starter observation':'Record dough observation')),body:Form(key:formKey,child:KitchenPage(scrollKey: const ValueKey('observation-scroll'), children:[
    if (!widget.outcomePhoto) ...[
    const _Notice('Log what you can see. Time and photos cannot certify readiness or food safety. Unknown measurements stay empty.'),
    numberField(temperature,'Temperature (°C, optional)'),
    if(widget.starter)...[numberField(height,'Measured height (mm, optional)',positive:true),numberField(baseline,'Starting height (mm, optional)',positive:true),DropdownButtonFormField<String>(initialValue:peak,isExpanded:true,itemHeight:null,decoration:const InputDecoration(labelText:'Peak observation',helperText:'Choose Unknown if the peak was missed. No exact peak is inferred.',helperMaxLines:3),items:const [DropdownMenuItem(value:'unknown',child:Text('Unknown / missed')),DropdownMenuItem(value:'not_yet',child:Text('Not yet peaked')),DropdownMenuItem(value:'observed',child:Text('Observed peak')),DropdownMenuItem(value:'falling',child:Text('Falling'))],onChanged:busy?null:(v)=>setState(()=>peak=v??'unknown')),const SizedBox(height:16)]else numberField(rise,'Measured rise (%, optional)'),
    TextFormField(controller:notes,decoration:const InputDecoration(labelText:'What can you see or feel? (optional)'),minLines:3,maxLines:7),
    const _Section('Optional private photo'),
    ],
    const KitchenInfo(title: 'Photo privacy', text: 'A resized copy is kept locally with photo metadata removed.'),
    const SizedBox(height:12),
    Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:busy?null:()=>pick(true),icon:const Icon(Icons.camera_alt_outlined),label:const Text('Take a photo')),OutlinedButton.icon(onPressed:busy?null:()=>pick(false),icon:const Icon(Icons.photo_library_outlined),label:const Text('Choose a photo'))]),
    if(photo!=null)...[_LocalPhotoView(metadata:photo!.toJson(),label:'Private observation photo selected for this record'),TextButton(onPressed:busy?null:()async{final previous=photo;if(previous==null)return;setState(()=>busy=true);try{await media.delete(previous);if(mounted)setState(()=>photo=null);}catch(e){if(mounted)setState(()=>error='The attachment could not be removed: $e');}finally{if(mounted)setState(()=>busy=false);}},child:const Text('Remove this attachment'))],
    if(error.isNotEmpty)Semantics(liveRegion:true,child:_Notice(error,icon:Icons.error_outline)),
    if(busy)const LinearProgressIndicator(),
    const SizedBox(height:16),FilledButton(onPressed:busy || (widget.outcomePhoto && photo == null) ? null : save,child:Text(widget.outcomePhoto ? 'Save photo' : 'Save actual observation')),
  ])));
}
class _LocalPhotoView extends StatelessWidget {
  const _LocalPhotoView({required this.metadata,required this.label,this.thumbnail = false});
  final Map<String,dynamic> metadata;
  final String label;
  final bool thumbnail;
  @override Widget build(BuildContext context){
    final Future<File> file;
    try{file=LocalMediaService().resolve(LocalPhoto.fromJson(metadata));}
    catch(_){return thumbnail ? const Icon(Icons.image_not_supported_outlined) : const _Notice('This saved photo is unavailable.');}
    return Padding(padding:EdgeInsets.symmetric(vertical:thumbnail ? 0 : 12),child:FutureBuilder<File>(future:file,builder:(context,snapshot){
      if(snapshot.hasError)return thumbnail ? const Icon(Icons.image_not_supported_outlined) : const _Notice('This saved photo is unavailable.');
      if(!snapshot.hasData)return thumbnail ? const Icon(Icons.image_outlined) : const SizedBox(height:48,child:Center(child:CircularProgressIndicator()));
      return ClipRRect(borderRadius:BorderRadius.circular(10),child:Image.file(snapshot.data!,height:thumbnail ? 48 : 260,width:double.infinity,fit:thumbnail ? BoxFit.cover : BoxFit.contain,semanticLabel:label,errorBuilder:(_,error,stack)=>thumbnail ? const Icon(Icons.image_not_supported_outlined) : const _Notice('This saved photo is unavailable.')));
    }));
  }
}

Future<void> _removeObservationPhoto(BuildContext context,AppStore store,AppRecord observation)async{
  final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Remove this private photo?'),content:const Text('The observation measurements and notes stay saved. This removes the local attachment; exported copies cannot be recalled.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Keep photo')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Remove photo'))]));
  if(yes!=true||!context.mounted)return;
  final metadata=observation.fields['photo'];if(metadata is! Map)return;
  final fields=Map<String,dynamic>.from(observation.fields)..remove('photo')..remove('photoId');
  try{await store.save(observation.kind,fields,id:observation.id);}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Photo was not removed: $e')));return;}
  try{await LocalMediaService().delete(LocalPhoto.fromJson(Map<String,dynamic>.from(metadata)));if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Local photo removed. Observation text retained.')));}
  catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Attachment removed from the record, but local file cleanup needs attention: $e')));}
}
