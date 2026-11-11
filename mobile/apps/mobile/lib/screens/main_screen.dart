import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_store.dart';
import '../data/planning_adapter.dart';
import 'plan_review_screen.dart';
import 'production_screen.dart' as production;
import 'starter_insights_screen.dart';
import 'journal_book_screen.dart';
import 'private_recipe_editor.dart';
import 'formula_tools_screen.dart';
import '../platform/export_share.dart';
import '../platform/local_media.dart';

// Screen state is deliberately separate from persisted kitchen records.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.store, this.servicesBuilder});
  final AppStore store;
  final WidgetBuilder? servicesBuilder;
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int tab = 0;
  final labels = const ['Today', 'Plan', 'Recipes', 'Starters', 'Journal'];
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(labels[tab]), actions: [
        TextButton.icon(onPressed: () => _open(context, KitchenScreen(store: widget.store, servicesBuilder: widget.servicesBuilder)), icon: const Icon(Icons.kitchen_outlined), label: const Text('Kitchen')),
      ]),
      body: IndexedStack(index: tab, children: [
        TodayScreen(store: widget.store, plan: () => setState(() => tab = 1)),
        PlanScreen(store: widget.store),
        RecipesScreen(store: widget.store),
        StartersScreen(store: widget.store),
        JournalScreen(store: widget.store),
      ]),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
        NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
        NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Plan'),
        NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Recipes'),
        NavigationDestination(icon: Icon(Icons.science_outlined), selectedIcon: Icon(Icons.science), label: 'Starters'),
        NavigationDestination(icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories), label: 'Journal'),
      ]),
    ),
  );
}

void _open(BuildContext context, Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
Future<void> _run(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e'), duration: const Duration(seconds: 6)));
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

class _Page extends StatelessWidget {
  const _Page({required this.children, this.scrollKey});
  final List<Widget> children;
  final Key? scrollKey;
  @override
  Widget build(BuildContext context) => ListView(key: scrollKey, padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: children);
}
class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 24, bottom: 12), child: Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)), ]));
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
  const _Empty(this.icon, this.title, this.body, {this.action});
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => _Panel(children: [Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 18), Text(title, style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 10), Text(body), if (action != null) ...[const SizedBox(height: 20), action!]]);
}

class _Field {
  const _Field(this.key, this.label, {this.initial = '', this.numeric = false, this.multiline = false, this.required = true});
  final String key, label, initial;
  final bool numeric, multiline, required;
}
Future<Map<String, String>?> _form(BuildContext context, String title, List<_Field> fields, {String? explanation, String submit = 'Save'}) => Navigator.of(context).push<Map<String, String>>(MaterialPageRoute(builder: (_) => _FormScreen(title: title, fields: fields, explanation: explanation, submit: submit)));
class _FormScreen extends StatefulWidget {
  const _FormScreen({required this.title, required this.fields, this.explanation, required this.submit});
  final String title, submit;
  final List<_Field> fields;
  final String? explanation;
  @override
  State<_FormScreen> createState() => _FormScreenState();
}
class _FormScreenState extends State<_FormScreen> {
  final key = GlobalKey<FormState>();
  late final values = {for (final f in widget.fields) f.key: TextEditingController(text: f.initial)};
  @override
  void dispose() {for (final c in values.values) {c.dispose();} super.dispose();}
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.title)), body: Form(key: key, child: _Page(children: [
    if (widget.explanation != null) _Notice(widget.explanation!),
    for (final f in widget.fields) Padding(padding: const EdgeInsets.only(bottom: 18), child: TextFormField(controller: values[f.key], decoration: InputDecoration(labelText: f.label, alignLabelWithHint: true), minLines: f.multiline ? 3 : 1, maxLines: f.multiline ? 8 : 1, keyboardType: f.numeric ? const TextInputType.numberWithOptions(decimal: true) : f.multiline ? TextInputType.multiline : TextInputType.text, validator: (v) {
      if (f.required && (v == null || v.trim().isEmpty)) return 'Enter ${f.label.toLowerCase()}';
      if (!f.required && (v == null || v.trim().isEmpty)) return null;
      if (f.numeric && (double.tryParse(v ?? '') == null || !double.parse(v!).isFinite || double.parse(v) < 0)) return 'Enter a finite non-negative number';
      return null;
    })),
    FilledButton(onPressed: () {if (key.currentState!.validate()) Navigator.pop(context, {for (final e in values.entries) e.key: e.value.text.trim()});}, child: Text(widget.submit)),
  ])));
}

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.store, required this.plan});
  final AppStore store;
  final VoidCallback plan;
  @override
  Widget build(BuildContext context) {
    final bakes = store.records('bake').where((b) => !['complete', 'abandoned'].contains(b.fields['state'])).toList();
    final starters = store.records('starter');
    final timers = store.records('timer').where((t)=>t.text('state')=='running').toList()..sort((a,b)=>(a.date('dueAt')??a.updatedAt).compareTo(b.date('dueAt')??b.updatedAt));
    return _Page(children: [
      Text('Your kitchen, at a glance.', style: Theme.of(context).textTheme.headlineSmall),
      const _Notice('Saved on this device. Local records are not a cloud backup.', icon: Icons.phone_android_outlined),
      if (bakes.isEmpty && starters.isEmpty) _Empty(Icons.bakery_dining_outlined, 'Make room for your first bake', 'Add an established starter or choose a recipe. No account, camera or calendar is needed to begin.', action: FilledButton(onPressed: plan, child: const Text('Plan a bake'))),
      if(timers.isNotEmpty)const _Section('Saved checks and timers'),
      for(final timer in timers)_TimerCard(store:store,timer:timer),
      if (bakes.isNotEmpty) const _Section('Needs your attention'),
      for (final b in bakes) _BakeCard(store: store, bake: b),
      if (starters.isNotEmpty) const _Section('Your starters'),
      for (final s in starters) _Panel(children: [Text(_str(s.fields['name']), style: Theme.of(context).textTheme.titleLarge), Text('${_str(s.fields['storage'], 'counter')} care · last feed ${_date(s.fields['lastFeedAt'])}'), const SizedBox(height: 12), OutlinedButton(onPressed: () => _open(context, StarterDetail(store: store, id: s.id)), child: const Text('Open starter'))]),
      if (bakes.isNotEmpty || starters.isNotEmpty) FilledButton.icon(onPressed: plan, icon: const Icon(Icons.add), label: const Text('Plan another bake')),
      const _Section('Explore more'),
      Wrap(spacing: 8, runSpacing: 8, children: [ActionChip(label: const Text('Learn a technique'), avatar: const Icon(Icons.school_outlined), onPressed: () => _open(context, LearnScreen(store: store))), ActionChip(label: const Text('Pantry & shopping'), avatar: const Icon(Icons.shopping_basket_outlined), onPressed: () => _open(context, CollectionScreen(store: store, kind: 'pantry', title: 'Pantry & shopping')))]),
    ]);
  }
}
class _BakeCard extends StatelessWidget {
  const _BakeCard({required this.store, required this.bake});
  final AppStore store;
  final AppRecord bake;
  @override
  Widget build(BuildContext context) {
    final steps = _maps(bake.fields['steps']);
    final index = _num(bake.fields['stepIndex']).toInt();
    return _Panel(children: [Text(_str(bake.fields['name'], 'Bake'), style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8), Text(index < steps.length ? _str(steps[index]['title'], 'Check your dough') : 'Review your bake'), Text('State: ${_str(bake.fields['state'], 'planned')} · ${_date(bake.fields['startAt'])}'), const SizedBox(height: 12), FilledButton(onPressed: () => _open(context, BakeDetail(store: store, id: bake.id)), child: const Text('Open this bake'))]);
  }
}

class StartersScreen extends StatelessWidget {
  const StartersScreen({super.key, required this.store});
  final AppStore store;
  Future<void> _add(BuildContext context) async {
    final f = await _form(context, 'Add a starter', const [_Field('name', 'Jar name'), _Field('hydration', 'Hydration (%)', initial: '100', numeric: true), _Field('flour', 'Flour blend', initial: 'Bread flour'), _Field('origin', 'Origin or age (unknown is fine)', required: false)], explanation: 'Bring an established starter or start a new culture. The app cannot judge maturity by age alone.');
    if (f == null || !context.mounted) return;
    await _run(context, () async {final s = await store.save('starter', {...f, 'hydration': double.parse(f['hydration']!), 'storage': 'counter'}); if (context.mounted) _open(context, StarterDetail(store: store, id: s.id));});
  }
  @override
  Widget build(BuildContext context) => _Page(children: [
    FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('Add a starter')),
    const SizedBox(height: 16),
    if (store.records('starter').isEmpty) const _Empty(Icons.science_outlined, 'Every jar has its own story', 'Name a starter, record actual feeds and observe its rise. There is no required feeding streak.'),
    for (final s in store.records('starter')) _Panel(children: [Text(s.text('name'), style: Theme.of(context).textTheme.titleLarge), Text('${s.text('hydration', 'Unknown')}% hydration · ${s.text('storage', 'counter')}'), Text('Last actual feed: ${_date(s.fields['lastFeedAt'])}'), const SizedBox(height: 10), OutlinedButton(onPressed: () => _open(context, StarterDetail(store: store, id: s.id)), child: const Text('Open jar'))]),
    const _Section('Starting from scratch?'),
    const _Notice('A new culture progresses through observations, not a fixed day count. Use clean equipment and open reviewed guidance if you notice mould or pink/orange changes.'),
    OutlinedButton(onPressed: () => _open(context, LearnScreen(store: store)), child: const Text('Open starter and baking guides')),
  ]);
}

class StarterDetail extends StatelessWidget {
  const StarterDetail({super.key, required this.store, required this.id});
  final AppStore store;
  final String id;
  Future<void> _feed(BuildContext context, AppRecord s) async {
    final feeds = store.records('feed').where((f) => f.text('starterId') == id).toList();
    final last = feeds.isEmpty ? null : feeds.first;
    final f = await _form(context, 'Log actual feed', [
      _Field('seed', 'Starter retained / seed (g)', initial: _str(last?.fields['seed'], '20'), numeric: true),
      _Field('flour', 'Flour added (g)', initial: _str(last?.fields['flour'], '40'), numeric: true),
      _Field('water', 'Water added (g)', initial: _str(last?.fields['water'], '40'), numeric: true),
      _Field('at', 'Actual time (ISO date, optional)', required: false),
    ], explanation: 'Log what you actually used. Seed + flour + water is the final build. A feed reminder does not record a feed for you.', submit: 'Record feed');
    if (f == null || !context.mounted) return;
    final at = f['at']!.isEmpty ? DateTime.now() : DateTime.tryParse(f['at']!);
    if (at == null) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use an ISO date such as 2026-11-11T08:30.'))); return;}
    await _run(context, () => store.logFeed(id, seed: double.parse(f['seed']!), flour: double.parse(f['flour']!), water: double.parse(f['water']!), occurredAt: at), success: 'Actual feed saved on this phone.');
  }
  Future<void> _observe(BuildContext context) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ObservationCaptureScreen(store: store, objectId: id, starter: true)));
  }
  Future<void> _mode(BuildContext context, AppRecord s) async {
    final selected = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [for (final mode in ['counter', 'fridge', 'travel', 'paused', 'revival']) ListTile(title: Text(mode[0].toUpperCase() + mode.substring(1)), leading: Icon(mode == s.text('storage') ? Icons.check_circle : Icons.circle_outlined), onTap: () => Navigator.pop(c, mode))])));
    if (selected != null && context.mounted) await _run(context, () async {await setStarterCareMode(store, id, selected);});
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: store, builder: (context, _) {
    final s = store.find(id);
    if (s == null) return Scaffold(appBar: AppBar(title: const Text('Starter')), body: const Center(child: Text('This jar is no longer available.')));
    final feeds = store.records('feed').where((f) => f.text('starterId') == id).toList();
    final observations = store.records('observation').where((o) => o.text('objectId') == id).toList();
    return Scaffold(appBar: AppBar(title: Text(s.text('name'))), body: _Page(children: [
      OutlinedButton.icon(onPressed:()=>_open(context,StarterInsightsScreen(store:store,starterId:id)),icon:const Icon(Icons.insights_outlined),label:const Text('Rise history, care and reminders')),
      _Panel(children: [Text('${s.text('hydration')}% hydration · ${s.text('storage', 'counter')} care', style: Theme.of(context).textTheme.titleMedium), Text(s.text('flour')), const SizedBox(height: 12), Text('Last actual feed: ${_date(s.fields['lastFeedAt'])}'), if (s.fields['mass'] != null) Text('Recorded build: ${_grams(s.fields['mass'])}'), const SizedBox(height: 16), FilledButton(onPressed: () => _feed(context, s), child: const Text('Log a feed')), OutlinedButton(onPressed: () => _observe(context), child: const Text('Record rise or temperature')), TextButton(onPressed: () => _mode(context, s), child: const Text('Storage, travel or pause'))]),
      const _Notice('No personalised peak prediction is shown until enough comparable confirmed peaks are available. Use observations and reviewed guidance; a timer cannot certify starter safety.'),
      const _Section('Observations'),
      if (observations.isEmpty) const Text('No observations yet. Record what you can measure; leave unknowns empty.'),
      for (final o in observations) _Panel(children: [Text(_date(o.fields['occurredAt']), style: Theme.of(context).textTheme.labelLarge), Text('Peak: ${o.text('peak', 'unknown')}'), if (o.text('height').isNotEmpty) Text('Height ${o.text('height')} mm · baseline ${o.text('baseline', 'unknown')} mm'), if (o.text('temperature').isNotEmpty) Text('${o.text('temperature')} °C'), if (o.text('note').isNotEmpty) Text(o.text('note')), if(o.fields['photo'] is Map) _LocalPhotoView(metadata: Map<String,dynamic>.from(o.fields['photo'] as Map), label: 'Your saved starter observation photo'), if(o.fields['photo'] is Map) TextButton(onPressed:()=>_removeObservationPhoto(context,store,o),child:const Text('Remove this private photo'))]),
      const _Section('Actual feed history'),
      if (feeds.isEmpty) const Text('No feeds recorded. Logging an earlier feed is supported.'),
      for (final f in feeds) _Panel(children: [Text(_date(f.fields['occurredAt']), style: Theme.of(context).textTheme.labelLarge), Text('${_grams(f.fields['seed'])} starter + ${_grams(f.fields['flour'])} flour + ${_grams(f.fields['water'])} water'), Text('Total build: ${_grams(_num(f.fields['seed']) + _num(f.fields['flour']) + _num(f.fields['water']))}'), TextButton(onPressed: () => _open(context, RecordHistoryScreen(store: store, record: f)), child: const Text('View / correct this record'))]),
      const _Section('Care and lineage'),
      OutlinedButton(onPressed: () => _open(context, LearnScreen(store: store)), child: const Text('Troubleshoot with reviewed guidance')),
      OutlinedButton(onPressed: () async {final f = await _form(context, 'Split a starter', const [_Field('name', 'New jar name')], explanation: 'Creates a linked jar. Record the actual split weights separately; no amount is assumed.'); if (f != null && context.mounted) await _run(context, () async {await store.save('starter', {...s.fields, 'name': f['name'], 'parentId': id, 'lastFeedAt': null, 'mass': null});}, success: 'Linked jar saved.');}, child: const Text('Create an offshoot jar')),
      TextButton(onPressed: () => _confirmDelete(context, store, s), child: const Text('Delete this jar')),
    ]));
  });
}

Future<void> _confirmDelete(BuildContext context, AppStore store, AppRecord record) async {
  final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text('Delete ${record.text('name', record.kind)}?'), content: const Text('This removes the local record. Existing bake snapshots stay independent. Export your data first if you need a copy.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete record'))]));
  if (yes == true && context.mounted) await _run(context, () async {await store.remove(record.id); if (context.mounted) Navigator.pop(context);});
}

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}
class _RecipesScreenState extends State<RecipesScreen> {
  String query = '', family = 'All';
  @override
  Widget build(BuildContext context) {
    final all = [...widget.store.recipes, ...widget.store.records('recipe').map((r) => {...r.fields, 'id': r.id})];
    final families = {'All', ...all.map((r) => _str(r['family'], 'Own recipe'))}.toList();
    final list = all.where((r) => _str(r['title']).toLowerCase().contains(query.toLowerCase()) && (family == 'All' || _str(r['family'], 'Own recipe') == family)).toList();
    return _Page(children: [
      TextField(decoration: const InputDecoration(labelText: 'Search your recipes', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: family, decoration: const InputDecoration(labelText: 'Recipe family'), items: families.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(), onChanged: (v) => setState(() => family = v ?? 'All')),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () => _open(context, RecipeEditor(store: widget.store)), icon: const Icon(Icons.add), label: const Text('Add your recipe / paste a recipe')),
      const _Notice('Authored recipes are experimental drafts until kitchen trials are recorded. Their quantities are useful; their timing is not a tested guarantee.'),
      if (list.isEmpty) const _Empty(Icons.search_off, 'No matching recipes', 'Try clearing a filter or add your own formula.'),
      for (final r in list) _Panel(children: [Text(_str(r['title']), style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 6), Text('${_str(r['family'], 'Own recipe')} · experimental'), if ((r['hydrationPercent'] ?? r['hydration']) != null) Text('${r['hydrationPercent'] ?? r['hydration']}% hydration'), const SizedBox(height: 10), OutlinedButton(onPressed: () => _open(context, RecipeDetail(store: widget.store, recipe: r)), child: const Text('View formula and method'))]),
    ]);
  }
}

class RecipeDetail extends StatefulWidget {
  const RecipeDetail({super.key, required this.store, required this.recipe});
  final AppStore store;
  final Map<String, dynamic> recipe;
  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}
class _RecipeDetailState extends State<RecipeDetail> {
  double scale = 1;
  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    final ingredients = _maps(r['ingredients']);
    final steps = _maps(r['steps']);
    return Scaffold(appBar: AppBar(title: const Text('Recipe')), body: _Page(children: [
      Text(_str(r['title']), style: Theme.of(context).textTheme.headlineMedium),
      Text('${_str(r['family'], 'Own recipe')} · ${_str(r['id'])} · draft / experimental'),
      const _Notice('This method has not completed documented kitchen validation. Review ingredients, allergens, equipment and timing before starting.'),
      Row(children: [const Expanded(child: Text('Scale the entire formula')), IconButton(tooltip: 'Decrease scale', onPressed: scale > .25 ? () => setState(() => scale -= .25) : null, icon: const Icon(Icons.remove_circle_outline)), Text('${scale.toStringAsFixed(2)}×'), IconButton(tooltip: 'Increase scale', onPressed: () => setState(() => scale += .25), icon: const Icon(Icons.add_circle_outline))]),
      const _Section('What you will weigh'),
      for (final i in ingredients) ListTile(contentPadding: EdgeInsets.zero, title: Text(_str(i['name'], _str(i['ingredientId'], 'Ingredient'))), trailing: Text(_grams(_ingredientGrams(i) * scale), style: Theme.of(context).textTheme.titleMedium)),
      if (ingredients.isEmpty) const Text('No structured ingredients. Edit the formula before planning.'),
      if ((r['hydrationPercent'] ?? r['hydration']) != null) _Notice('Total hydration: ${r['hydrationPercent'] ?? r['hydration']}%. Starter flour and water must be included in this calculation. Scaling changes quantity, not proof readiness.'),
      const _Section('Method and observation cues'),
      for (var i = 0; i < steps.length; i++) _Panel(children: [Text('${i + 1}. ${_str(steps[i]['title'], _str(steps[i]['name'], 'Step'))}', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8), Text(_str(steps[i]['instructions'], _str(steps[i]['instruction']))), if ((steps[i]['readinessCue'] ?? steps[i]['cues']) != null) Text(_str(steps[i]['readinessCue'] ?? steps[i]['cues']))]),
      if (r['notes'] != null) _Notice(_str(r['notes'])),
      if (r['allergens'] != null) _Notice('Ingredient flags: ${_str(r['allergens'])}. Absence of a flag does not establish allergy safety.'),
      const SizedBox(height: 12),
      FilledButton(onPressed: ingredients.isEmpty || steps.isEmpty ? null : () => _open(context, PlanScreen(store: widget.store, initialRecipe: r, initialScale: scale, standalone: true)), child: const Text('Plan this bake')),
      OutlinedButton(onPressed: () => _open(context, RecipeEditor(store: widget.store, original: r)), child: const Text('Create a private variation')),
      TextButton(onPressed: () => _open(context, TextExport(title: 'Recipe formula', text: const JsonEncoder.withIndent('  ').convert({...r, 'displayScale': scale}))), child: const Text('Export this formula')),
    ]));
  }
}
double _ingredientGrams(Map<String, dynamic> i) => _num(i['grams'] ?? i['massG'] ?? i['quantityG'] ?? i['weightG']);

class RecipeEditor extends StatelessWidget {
  const RecipeEditor({super.key,required this.store,this.original});
  final AppStore store;
  final Map<String,dynamic>? original;
  @override Widget build(BuildContext context)=>PrivateRecipeEditor(store:store,original:original);
}

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.store, this.initialRecipe, this.initialScale = 1, this.standalone = false});
  final AppStore store;
  final Map<String, dynamic>? initialRecipe;
  final double initialScale;
  final bool standalone;
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}
class _PlanScreenState extends State<PlanScreen> {
  String? recipeId;
  late double scale = widget.initialScale;
  bool serveTarget = true, confirmed = false, busy = false;
  late DateTime target = DateTime.now().add(const Duration(days: 1)).copyWith(hour: 11, minute: 0);
  @override
  void initState() {super.initState(); recipeId = widget.initialRecipe==null?null:_str(widget.initialRecipe?['id'],'review-snapshot');}
  Future<void> _time() async {
    final day = await showDatePicker(context: context, initialDate: target, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (day == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(target));
    if (t != null) setState(() => target = DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }
  Future<void> _unavailable() async {
    final f = await _form(context, 'Add time away / sleep', const [_Field('start', 'From (ISO date and time)'), _Field('end', 'Until (ISO date and time)'), _Field('note', 'Label (optional)', required: false)], explanation: 'For example 2026-11-12T09:00. These blocks mean you cannot perform a hands-on task. Calendar content is not collected.');
    if (f == null || !mounted) return;
    final start = DateTime.tryParse(f['start']!), end = DateTime.tryParse(f['end']!);
    if (start == null || end == null || !end.isAfter(start)) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid dates; Until must be after From.'))); return;}
    await _run(context, () async {await widget.store.save('availability', {'startAt': start.toUtc().toIso8601String(), 'endAt': end.toUtc().toIso8601String(), 'name': f['note']});});
  }
  @override
  Widget build(BuildContext context) {
    final initial=widget.initialRecipe;
    final all = [if(initial!=null){...initial,'id':initial['id']??'review-snapshot'}, ...[...widget.store.recipes, ...widget.store.records('recipe').map((r) => {...r.fields, 'id': r.id})].where((r)=>initial==null||r['id']!=initial['id'])].where((r) => _maps(r['steps']).isNotEmpty).toList();
    final selected = all.where((r) => _str(r['id']) == recipeId).firstOrNull;
    final body = _Page(scrollKey: const ValueKey('plan-scroll'), children: [
      Text('Fit the hands-on moments.', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(initialValue: all.any((r) => _str(r['id']) == recipeId) ? recipeId : null, isExpanded: true, decoration: const InputDecoration(labelText: 'Recipe'), items: all.map((r) => DropdownMenuItem(value: _str(r['id']), child: Text(_str(r['title']), overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() {recipeId = v; confirmed = false;})),
      if (all.isEmpty) const _Notice('No executable recipes are available. Add a private formula with ingredients and steps first.'),
      const _Section('What time matters?'),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ready to slice / serve by'), subtitle: const Text('Includes cooling. Turn off to start from now.'), value: serveTarget, onChanged: (v) => setState(() => serveTarget = v)),
      if (serveTarget) OutlinedButton.icon(onPressed: _time, icon: const Icon(Icons.event), label: Text(_date(target))),
      Row(children: [const Expanded(child: Text('Batch scale')), IconButton(tooltip: 'Smaller batch', onPressed: scale > .25 ? () => setState(() => scale -= .25) : null, icon: const Icon(Icons.remove_circle_outline)), Text('${scale.toStringAsFixed(2)}×'), IconButton(tooltip: 'Larger batch', onPressed: () => setState(() => scale += .25), icon: const Icon(Icons.add_circle_outline))]),
      if (scale > 1) const _Notice('This quantity exceeds the draft method’s original yield. Reduce scale to 1× or plan separate named batches; larger pan and oven-load adaptations need validation.'),
      const _Section('When can you be there?'),
      for (final b in widget.store.records('availability')) ListTile(contentPadding: EdgeInsets.zero, title: Text(b.text('name', 'Unavailable')), subtitle: Text('${_date(b.fields['startAt'])} → ${_date(b.fields['endAt'])}'), trailing: IconButton(tooltip: 'Remove unavailable block', icon: const Icon(Icons.delete_outline), onPressed: () => _run(context, () => widget.store.remove(b.id)))),
      OutlinedButton.icon(onPressed: _unavailable, icon: const Icon(Icons.add), label: const Text('Add time away or sleep')),
      const _Section('Your kitchen assumptions'),
      _Panel(children: [Text('Oven capacity: ${widget.store.preference('ovenCapacity', 1)} batch at a time'), Text('Room temperature: ${widget.store.preference('roomTemperature', 23)} °C (assumed)'), const _Notice('The planner must respect your recipe bounds and equipment. Fermentation follows observations; a countdown is never proof of readiness.'), OutlinedButton(onPressed: () => _open(context, SettingsScreen(store: widget.store)), child: const Text('Edit kitchen and preferences'))]),
      CheckboxListTile(contentPadding: EdgeInsets.zero, value: confirmed, onChanged: selected == null ? null : (v) => setState(() => confirmed = v ?? false), title: const Text('I have reviewed this experimental recipe'), subtitle: const Text('The bundled methods are not yet kitchen-validated. Timing is guidance; I will use the method’s readiness cues.')),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: !confirmed || selected == null || busy || scale > 1 ? null : () async {
        setState(() => busy = true);
        await _run(context, () async {
          final start=serveTarget?null:DateTime.now().toUtc().add(const Duration(minutes:2));
          final candidate=planRecipe(selected,widget.store.records('availability'),[...widget.store.records('bake'),...widget.store.records('production')],{'oven':(widget.store.preference('ovenCapacity',1) as num).toInt()},serveAt:serveTarget?target:null,startAt:start);
          if(!context.mounted)return;
          setState(()=>busy=false);
          final accepted=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>PlanReviewScreen(recipe:selected,candidate:candidate,scale:scale)));
          if(accepted!=true||!mounted)return;
          setState(()=>busy=true);
          final bake = await widget.store.createBake(selected, scale: scale, serveAt: serveTarget ? target : null,startAt:start,expectedSchedule:candidate.toJson());
          if (context.mounted) _open(context, BakeDetail(store: widget.store, id: bake.id));
        });
        if (mounted) setState(() => busy = false);
      }, icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.fact_check_outlined), label: Text(busy ? 'Checking constraints…' : 'Create and review bake plan')),
      const _Section('Your saved plans and active bakes'),
      for (final bake in widget.store.records('bake').where((b) => b.text('state') != 'complete')) _BakeCard(store: widget.store, bake: bake),
    ]);
    return widget.standalone ? Scaffold(appBar: AppBar(title: const Text('Plan this bake')), body: body) : body;
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
  Timer? ticker;
  @override
  void initState() {super.initState(); ticker = Timer.periodic(const Duration(seconds: 1), (_) {if (mounted) setState(() {});});}
  @override
  void dispose() {ticker?.cancel(); super.dispose();}
  Future<void> _observe() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ObservationCaptureScreen(store: widget.store, objectId: widget.id, starter: false)));
  }
  Future<void> _timer(AppRecord bake) async {
    final f = await _form(context, 'Set an independent timer', const [_Field('name', 'Check or task name'), _Field('minutes', 'Duration (minutes)', initial: '30', numeric: true)], explanation: 'The due time is saved on this phone. Notification delivery depends on platform permission and device state; do not rely on an app as an oven safety control.');
    if (f == null || !mounted) return;
    await _run(context, () async {await widget.store.save('timer', {'name': f['name'], 'bakeId': widget.id, 'bakeName': bake.text('name'), 'dueAt': DateTime.now().add(Duration(seconds: (double.parse(f['minutes']!) * 60).round())).toUtc().toIso8601String(), 'state': 'running'});}, success: 'Timer deadline saved.');
  }
  Future<void> _finish(AppRecord bake) async {
    final f = await _form(context, 'Finish and save your bake', const [_Field('rating', 'Your rating (1–5, optional)', numeric: true, required: false), _Field('notes', 'What worked? What would you change?', multiline: true, required: false)], explanation: 'Your formula, actual steps and observations are already recorded. A photo and rating are optional.', submit: 'Save to journal');
    if (f == null || !mounted) return;
    final rating = double.tryParse(f['rating']!);
    if (rating != null && (rating < 1 || rating > 5)) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use a rating between 1 and 5, or leave it empty.'))); return;}
    await _run(context, () async {await widget.store.save('bake', {...bake.fields, 'state': 'complete', 'status': 'complete', 'completedAt': bake.fields['completedAt'] ?? DateTime.now().toUtc().toIso8601String(), 'rating': rating, 'notes': f['notes']}, id: bake.id);}, success: 'Bake saved to your journal.');
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.store, builder: (context, _) {
    final b = widget.store.find(widget.id);
    if (b == null) return Scaffold(appBar: AppBar(title: const Text('Bake')), body: const Center(child: Text('This bake is not available.')));
    final steps = _maps(b.fields['steps']);
    final index = b.number('stepIndex').toInt();
    final current = index < steps.length ? steps[index] : null;
    final observations = widget.store.records('observation').where((o) => o.text('objectId') == b.id).toList();
    final timers = widget.store.records('timer').where((t) => t.text('bakeId') == b.id && t.text('state') == 'running').toList();
    return Scaffold(appBar: AppBar(title: Text(b.text('name', 'Your bake'))), body: _Page(children: [
      Text('${b.text('state', 'planned')} · step ${index + 1 > steps.length ? steps.length : index + 1} of ${steps.length}', style: Theme.of(context).textTheme.labelLarge),
      if (b.text('state') == 'complete') _Panel(tone: true, children: [Text('You made this.', style: Theme.of(context).textTheme.headlineSmall), Text('Saved ${_date(b.fields['completedAt'])}'), if (b.text('notes').isNotEmpty) Text(b.text('notes'))]),
      if (current != null && b.text('state') != 'complete') _Panel(tone: true, children: [Text(_str(current['title'], _str(current['name'], 'Next step')), style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 10), Text(_str(current['instructions'], _str(current['instruction']))), if ((current['readinessCue'] ?? current['cues']) != null) _Notice(_str(current['readinessCue'] ?? current['cues'])), const _Notice('Time is an estimate. Use the recipe’s observations before moving on.'), FilledButton(onPressed: () => _run(context, () => widget.store.completeStep(b.id, expectedIndex: index), success: 'Actual step completion recorded.'), child: const Text('Record this step complete')), TextButton(onPressed: () async {final f = await _form(context, 'Record an earlier completion', const [_Field('at', 'Actual date/time (ISO)')]); if (f == null || !context.mounted) return; final at = DateTime.tryParse(f['at']!); if (at == null) return; await _run(context, () => widget.store.completeStep(b.id, occurredAt: at, expectedIndex: index));}, child: const Text('I did this earlier'))]),
      if (current == null && b.text('state') != 'complete') const _Notice('All method steps are recorded. Check your recorded outcome and cooling requirements.'),
      if (b.text('state') != 'complete') Wrap(spacing: 8, runSpacing: 8, children: [OutlinedButton.icon(onPressed: _observe, icon: const Icon(Icons.thermostat), label: const Text('Log observation')), OutlinedButton.icon(onPressed: () => _timer(b), icon: const Icon(Icons.timer_outlined), label: const Text('Set timer')), OutlinedButton(onPressed: () => _open(context, RecoveryScreen(store: widget.store, bakeId: b.id)), child: const Text('Plans changed')), OutlinedButton(onPressed: () => _open(context, LearnScreen(store: widget.store)), child: const Text('Help with this step'))]),
      if (timers.isNotEmpty) const _Section('Independent timers'),
      for (final t in timers) _TimerCard(store: widget.store, timer: t),
      const _Section('This bake’s ingredients'),
      for (final i in _maps(b.fields['ingredients'])) ListTile(contentPadding: EdgeInsets.zero, title: Text(_str(i['name'], _str(i['ingredientId']))), trailing: Text(_grams(_ingredientGrams(i)))),
      const _Section('Full method'),
      for (var n = 0; n < steps.length; n++) ListTile(contentPadding: EdgeInsets.zero, leading: Icon(n < index ? Icons.check_circle : n == index ? Icons.radio_button_checked : Icons.circle_outlined), title: Text(_str(steps[n]['title'], _str(steps[n]['name'], 'Step ${n + 1}'))), subtitle: Text('${_str(steps[n]['instructions'], _str(steps[n]['instruction']))}\nPlanned: ${_date(steps[n]['plannedStart'])} → ${_date(steps[n]['plannedEnd'])}')),
      const _Section('Actual observations'),
      if (observations.isEmpty) const Text('No observations recorded. Unmeasured values remain unknown.'),
      for (final o in observations) _Panel(children: [Text(_date(o.fields['occurredAt'])), if (o.text('temperature').isNotEmpty) Text('Dough ${o.text('temperature')} °C'), if (o.text('rise').isNotEmpty) Text('Rise ${o.text('rise')}%'), Text(o.text('texture')), if(o.fields['photo'] is Map) _LocalPhotoView(metadata: Map<String,dynamic>.from(o.fields['photo'] as Map), label: 'Your saved dough observation photo'), if(o.fields['photo'] is Map) TextButton(onPressed:()=>_removeObservationPhoto(context,widget.store,o),child:const Text('Remove this private photo'))]),
      if (b.text('state') == 'complete') FilledButton(onPressed: () => _finish(b), child: const Text('Add outcome / next-time note')),
      if (b.text('state') == 'complete') FilledButton(onPressed: () async {final pinned = b.fields['recipeSnapshot']; if (pinned is! Map) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This bake has no pinned recipe snapshot. Export it and review a private formula first.'))); return;} final recipe = Map<String,dynamic>.from(pinned); _open(context,PlanScreen(store:widget.store,initialRecipe:recipe,initialScale:b.number('scale',1).toDouble(),standalone:true));}, child: const Text('Bake again from this formula')),
      TextButton(onPressed: () => _open(context, TextExport(title: 'Bake record', text: const JsonEncoder.withIndent('  ').convert(b.fields))), child: const Text('Export this bake')),
    ]));
  });
}
class _TimerCard extends StatefulWidget {
  const _TimerCard({required this.store, required this.timer});
  final AppStore store;
  final AppRecord timer;
  @override State<_TimerCard> createState()=>_TimerCardState();
}
class _TimerCardState extends State<_TimerCard> {
  Timer? ticker;
  @override void initState(){super.initState();ticker=Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState((){});});}
  @override void dispose(){ticker?.cancel();super.dispose();}
  @override Widget build(BuildContext context) {
    final timer=widget.timer;
    final remaining = (timer.date('dueAt') ?? DateTime.now()).difference(DateTime.now());
    final seconds = remaining.inSeconds.abs();
    return _Panel(children: [Text(timer.text('name'), style: Theme.of(context).textTheme.titleMedium), Text('${timer.text('bakeName')} · ${remaining.isNegative ? 'Check due' : 'Due in'} ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}', style: Theme.of(context).textTheme.titleLarge), Text('Saved deadline: ${_date(timer.fields['dueAt'])}'), TextButton(onPressed: () => _run(context, () async {await widget.store.save('timer', {...timer.fields, 'state': 'acknowledged'}, id: timer.id);}), child: const Text('Acknowledge timer'))]);
  }
}

class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key, required this.store, required this.bakeId});
  final AppStore store;
  final String bakeId;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Plans changed')), body: _Page(children: [
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
  @override
  Widget build(BuildContext context) {
    final bakes = store.records('bake').where((b) => b.text('state') == 'complete').toList();
    return _Page(children: [
      Text('Remember what worked.', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 14),
      if (bakes.isEmpty) const _Empty(Icons.auto_stories_outlined, 'Your next loaf starts here', 'Finish a bake to save its formula and actual events. A photo or perfect result is never required.'),
      if (bakes.length > 1) OutlinedButton.icon(onPressed: () => _open(context, JournalInsightsScreen(store: store)), icon: const Icon(Icons.compare_arrows), label: const Text('Compare two bakes')),
      for (final b in bakes) _Panel(children: [Text(b.text('name'), style: Theme.of(context).textTheme.titleLarge), Text('Finished ${_date(b.fields['completedAt'])}'), if (b.fields['rating'] != null) Text('Your rating: ${b.fields['rating']} / 5'), if (b.text('notes').isNotEmpty) Text(b.text('notes')), const SizedBox(height: 10), OutlinedButton(onPressed: () => _open(context, BakeDetail(store: store, id: b.id)), child: const Text('Open actual bake and formula'))]),
      OutlinedButton.icon(onPressed:()=>_open(context,JournalBookScreen(store:store)),icon:const Icon(Icons.picture_as_pdf_outlined),label:const Text('Create a selected recipe book')),
      const _Section('Your data belongs to you'),
      OutlinedButton.icon(onPressed: () => _run(context, () async {final archive = await store.exportArchive(); if (context.mounted) _open(context, TextExport(title: 'Kitchen archive', text: archive));}), icon: const Icon(Icons.file_download_outlined), label: const Text('Export complete kitchen archive')),
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
    return Scaffold(appBar: AppBar(title: const Text('What changed?')), body: _Page(children: [
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
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Your kitchen')), body: _Page(children: [
    const _Notice('Local baking remains available without an account. Each network service requires its own consent and configuration.'),
    if (servicesBuilder != null) ListTile(leading: const Icon(Icons.cloud_outlined), title: const Text('Connected services'), subtitle: const Text('Account, sync, device capabilities and exports'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(context, servicesBuilder!(context))),
    for (final item in <(IconData, String, String, Widget)>[
      (Icons.calculate_outlined, 'Formula & feed tools', 'Exact hydration, preferments, scaling and starter builds', const FormulaToolsScreen()),
      (Icons.school_outlined, 'Learn', 'Written techniques and practical exercises', LearnScreen(store: store)),
      (Icons.shopping_basket_outlined, 'Pantry & shopping', 'Ingredient lots, prices and a reusable shopping list', CollectionScreen(store: store, kind: 'pantry', title: 'Pantry & shopping')),
      (Icons.inventory_2_outlined, 'Discard inventory', 'Track amounts, storage and uses without a safety guarantee', CollectionScreen(store: store, kind: 'discard', title: 'Discard inventory')),
      (Icons.factory_outlined, 'Production', 'Batches, equipment, exact shopping and pickup windows', production.ProductionScreen(store: store)),
      (Icons.group_outlined, 'Shared kitchen', 'Account and backend configuration required', ServiceStatusScreen(store: store, service: 'Shared kitchen')),
      (Icons.forum_outlined, 'Community', 'Opt-in sharing requires moderation and a connected account', ServiceStatusScreen(store: store, service: 'Community')),
      (Icons.chat_bubble_outline, 'Coach', 'Selected-context service; never changes your plan automatically', ServiceStatusScreen(store: store, service: 'Coach')),
      (Icons.sensors_outlined, 'Devices & reminders', 'Capabilities, manual readings and platform setup', DeviceScreen(store: store)),
      (Icons.privacy_tip_outlined, 'Data & privacy', 'Export, import, consent and local deletion', PrivacyScreen(store: store)),
      (Icons.settings_outlined, 'Settings', 'Kitchen assumptions, appearance and guidance', SettingsScreen(store: store)),
    ]) ListTile(contentPadding: const EdgeInsets.symmetric(vertical: 8), leading: Icon(item.$1), title: Text(item.$2), subtitle: Text(item.$3), trailing: const Icon(Icons.chevron_right), onTap: () => _open(context, item.$4)),
  ]));
}
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.store, required this.kind, required this.title});
  final AppStore store;
  final String kind, title;
  Future<void> _add(BuildContext context, {AppRecord? original}) async {
    final f = await _form(context, original == null ? 'Add ${kind == 'discard' ? 'discard lot' : 'ingredient lot'}' : 'Update recorded stock', [
      _Field('name', 'Ingredient / lot name', initial: original?.text('name') ?? ''),
      _Field('grams', 'Recorded amount (g)', initial: original?.text('grams', original?.text('quantity')??'') ?? '', numeric: true),
      _Field('price', 'Pack price (optional)', initial: original?.text('price') ?? '', numeric: true, required: false),
      _Field('currency', 'Currency', initial: original?.text('currency') ?? '', required: false),
      _Field('note', 'Storage, date, flour or allergy notes', initial: original?.text('note') ?? '', multiline: true, required: false),
    ], explanation: 'Enter your own measured stock and prices. Amount or age does not certify that an ingredient or discard is safe.');
    if (f != null && context.mounted) await _run(context, () async {await store.save(kind, {...?original?.fields, ...f, 'grams': double.parse(f['grams']!), 'price': double.tryParse(f['price']!), 'recordedAt': DateTime.now().toUtc().toIso8601String()}, id: original?.id);}, success: 'Recorded stock saved.');
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: store, builder: (context, _) => Scaffold(appBar: AppBar(title: Text(title)), body: _Page(children: [
    FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add), label: Text(kind == 'discard' ? 'Add discard lot' : 'Add ingredient lot')),
    const _Notice('Planned demand and actual consumption are separate. Stock changes only when you record it; planning does not mean an ingredient has been used.'),
    for (final lot in store.records(kind)) _Panel(children: [Text(lot.text('name'), style: Theme.of(context).textTheme.titleLarge), Text(_grams(lot.fields['grams']??lot.fields['quantity'])), if (lot.fields['price'] != null) Text('Recorded price ${lot.text('currency')} ${lot.fields['price']}'), if (lot.text('note').isNotEmpty) Text(lot.text('note')), Wrap(spacing: 8, children: [TextButton(onPressed: () => _add(context, original: lot), child: const Text('Update amount')), TextButton(onPressed: () => _run(context, () async {await store.save('shopping', {'name': lot.text('name'), 'checked': false});}, success: 'Added to shopping list.'), child: const Text('Add to shopping'))])]),
    const _Section('Shopping list'),
    OutlinedButton(onPressed: () async {final f = await _form(context, 'Add shopping item', const [_Field('name', 'Ingredient and amount')]); if (f != null && context.mounted) await _run(context, () async {await store.save('shopping', {'name': f['name'], 'checked': false});});}, child: const Text('Add an item')),
    for (final item in store.records('shopping')) CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(item.text('name')), value: item.flag('checked'), onChanged: (v) => _run(context, () async {await store.save('shopping', {...item.fields, 'checked': v}, id: item.id);})),
    if (store.records('shopping').isNotEmpty) TextButton(onPressed: () async {final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Remove checked shopping items?'), content: const Text('Unchecked items and pantry lots will stay.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep them')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove checked'))])); if (yes == true && context.mounted) await _run(context, () async {for (final item in store.records('shopping').where((i) => i.flag('checked')).toList()) {await store.remove(item.id);}});}, child: const Text('Remove checked items')),
  ])));
}

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Learn at your own pace')), body: _Page(children: [
    const _Notice('Written technique drafts are available offline. Filmed demonstrations and editorial review are still pending; no video or course completion is fabricated.'),
    const _Section('Practical techniques'),
    for (final lesson in store.lessons) _Panel(children: [Text(_str(lesson['title']), style: Theme.of(context).textTheme.titleLarge), Text(_str(lesson['summary'])), const SizedBox(height: 12), OutlinedButton(onPressed: () => _open(context, LessonDetail(store: store, lesson: lesson)), child: const Text('Read and practise'))]),
    const _Section('Guidance and source references'),
    for (final g in store.guidance) _Panel(children: [Text(_str(g['title']), style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 10), for (final line in (g['body'] is List ? g['body'] as List : [_str(g['body'])])) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_str(line))), for (final source in _maps(g['sources'])) SelectableText('${_str(source['title'])}\n${_str(source['url'])}'), const Text('Source-linked guidance; editorial review pending.')]),
  ]));
}
class LessonDetail extends StatelessWidget {
  const LessonDetail({super.key, required this.store, required this.lesson});
  final AppStore store;
  final Map<String, dynamic> lesson;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(_str(lesson['title']))), body: _Page(children: [
    Text(_str(lesson['summary']), style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 20),
    for (final instruction in lesson['instructions'] is List ? lesson['instructions'] as List : const []) Padding(padding: const EdgeInsets.only(bottom: 18), child: Text(_str(instruction))),
    const _Section('Try it in your kitchen'),
    Text(_str(lesson['exercise'])),
    const SizedBox(height: 12),
    FilledButton(onPressed: () => _run(context, () async {await store.save('lessonProgress', {'lessonId': lesson['id'], 'name': lesson['title'], 'practisedAt': DateTime.now().toUtc().toIso8601String()});}, success: 'Practice recorded. This does not certify mastery.'), child: const Text('Record that I practised')),
    const _Section('Sources'),
    for (final source in lesson['sourceUrls'] is List ? lesson['sourceUrls'] as List : const []) SelectableText(_str(source)),
    const _Notice('This lesson has written guidance. A genuine technique video and captions have not yet been produced.'),
  ]));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: store, builder: (context, _) => Scaffold(appBar: AppBar(title: const Text('Kitchen & preferences')), body: _Page(children: [
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Dark appearance'), subtitle: const Text('Keeps the same accessible status meanings.'), value: store.darkMode, onChanged: (v) => _run(context, () => store.setPreference('darkMode', v))),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('First Loaf guidance'), subtitle: const Text('More explanations. Your recipe and actual progress stay the same.'), value: store.beginnerMode, onChanged: (v) => _run(context, () => store.setPreference('beginnerMode', v))),
    const _Section('Kitchen assumptions'),
    ListTile(contentPadding: EdgeInsets.zero, title: const Text('Room temperature'), subtitle: Text('${store.preference('roomTemperature', 23)} °C · an assumption, not a measurement'), trailing: const Icon(Icons.edit_outlined), onTap: () async {final f = await _form(context, 'Room temperature assumption', [_Field('value', 'Temperature (°C)', initial: _str(store.preference('roomTemperature', 23)), numeric: true)]); if (f != null && context.mounted) await _run(context, () => store.setPreference('roomTemperature', double.parse(f['value']!)));}),
    ListTile(contentPadding: EdgeInsets.zero, title: const Text('Oven batch capacity'), subtitle: Text('${store.preference('ovenCapacity', 1)} batch at once'), trailing: const Icon(Icons.edit_outlined), onTap: () async {final f = await _form(context, 'Oven capacity', [_Field('value', 'Concurrent batch slots', initial: _str(store.preference('ovenCapacity', 1)), numeric: true)], explanation: 'One Dutch oven means one batch slot unless you have validated a different setup.'); if (f == null || !context.mounted) return; final n = double.parse(f['value']!); if (n < 1 || n > 20 || n != n.roundToDouble()) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use a whole number from 1 to 20.'))); return;} await _run(context, () => store.setPreference('ovenCapacity', n.toInt()));}),
    const _Section('Reminder preferences'),
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
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Data & privacy')), body: _Page(children: [
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
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(service)), body: _Page(children: [
    _Panel(children: [Text('A connected service is required', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 10), Text(service == 'Coach' ? 'A coach request needs an authenticated account, configured provider and quota, and a preview of the selected recipe/observations. No whole-library upload or automatic plan mutation is allowed.' : service == 'Community' ? 'Public posting needs authenticated accounts, privacy controls and a staffed moderation/reporting service. Your local journal stays private; nothing has been published.' : 'Shared kitchens need an authenticated backend and explicit member roles. Local records are not silently shared, and an invitation cannot grant access until redeemed.'), const SizedBox(height: 14), const Text('Open Connected services in the Kitchen menu to check actual configuration and account capabilities. This screen does not pretend a remote operation succeeded.')]),
    if (service == 'Coach') OutlinedButton(onPressed: () => _open(context, LearnScreen(store: store)), child: const Text('Use offline written guidance')),
    OutlinedButton(onPressed: () => _open(context, PrivacyScreen(store: store)), child: const Text('Review data and privacy')),
  ]));
}

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Devices & reminders')), body: _Page(children: [
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
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Recorded event')), body: _Page(children: [
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
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: _Page(children: [
    const _Notice('Review the data before sharing. An exported copy can be retained by its recipient and cannot be recalled by revoking a later app link.'),
    FilledButton.icon(onPressed: () => _run(context, () async {final result = await ExportShareService().shareTextFile(fileName: 'crispy-crust-export.json', content: text, mimeType: 'application/json'); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));}), icon: const Icon(Icons.ios_share), label: const Text('Save or share this file')),
    OutlinedButton.icon(onPressed: () async {await Clipboard.setData(ClipboardData(text: text)); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard. Clear your clipboard if the data is private.')));}, icon: const Icon(Icons.copy), label: const Text('Copy text')),
    const SizedBox(height: 20),
    SelectableText(text, style: Theme.of(context).textTheme.bodySmall),
  ]));
}

class ObservationCaptureScreen extends StatefulWidget {
  const ObservationCaptureScreen({super.key, required this.store, required this.objectId, required this.starter, this.media});
  final AppStore store;
  final String objectId;
  final bool starter;
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
      await widget.store.save('observation',{'objectId':widget.objectId,'temperature':temperature.text.trim(),if(widget.starter)'height':height.text.trim(),if(widget.starter)'baseline':baseline.text.trim(),if(!widget.starter)'rise':rise.text.trim(),if(widget.starter)'peak':peak,widget.starter?'note':'texture':notes.text.trim(),'occurredAt':DateTime.now().toUtc().toIso8601String(),if(metadata!=null)'photo':metadata,if(photo!=null)'photoId':photo!.id});
      saved=true;
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
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.starter?'Record starter observation':'Record dough observation')),body:Form(key:formKey,child:_Page(scrollKey: const ValueKey('observation-scroll'), children:[
    const _Notice('Log what you can see. Time and photos cannot certify readiness or food safety. Unknown measurements stay empty.'),
    numberField(temperature,'Temperature (°C, optional)'),
    if(widget.starter)...[numberField(height,'Measured height (mm, optional)',positive:true),numberField(baseline,'Starting height (mm, optional)',positive:true),DropdownButtonFormField<String>(initialValue:peak,isExpanded:true,itemHeight:null,decoration:const InputDecoration(labelText:'Peak observation',helperText:'Choose Unknown if the peak was missed. No exact peak is inferred.',helperMaxLines:3),items:const [DropdownMenuItem(value:'unknown',child:Text('Unknown / missed')),DropdownMenuItem(value:'not_yet',child:Text('Not yet peaked')),DropdownMenuItem(value:'observed',child:Text('Observed peak')),DropdownMenuItem(value:'falling',child:Text('Falling'))],onChanged:busy?null:(v)=>setState(()=>peak=v??'unknown')),const SizedBox(height:16)]else numberField(rise,'Measured rise (%, optional)'),
    TextFormField(controller:notes,decoration:const InputDecoration(labelText:'What can you see or feel? (optional)'),minLines:3,maxLines:7),
    const _Section('Optional private photo'),
    const Text('Only your explicit camera or library choice opens the picker. A resized copy is kept locally with photo metadata removed. It is not uploaded for analysis or sharing.'),
    const SizedBox(height:12),
    Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:busy?null:()=>pick(true),icon:const Icon(Icons.camera_alt_outlined),label:const Text('Take a photo')),OutlinedButton.icon(onPressed:busy?null:()=>pick(false),icon:const Icon(Icons.photo_library_outlined),label:const Text('Choose a photo'))]),
    if(photo!=null)...[_LocalPhotoView(metadata:photo!.toJson(),label:'Private observation photo selected for this record'),TextButton(onPressed:busy?null:()async{final previous=photo;if(previous==null)return;setState(()=>busy=true);try{await media.delete(previous);if(mounted)setState(()=>photo=null);}catch(e){if(mounted)setState(()=>error='The attachment could not be removed: $e');}finally{if(mounted)setState(()=>busy=false);}},child:const Text('Remove this attachment'))],
    if(error.isNotEmpty)Semantics(liveRegion:true,child:_Notice(error,icon:Icons.error_outline)),
    if(busy)const LinearProgressIndicator(),
    const SizedBox(height:16),FilledButton(onPressed:busy?null:save,child:const Text('Save actual observation')),
  ])));
}
class _LocalPhotoView extends StatelessWidget {
  const _LocalPhotoView({required this.metadata,required this.label});
  final Map<String,dynamic> metadata;
  final String label;
  @override Widget build(BuildContext context){
    final Future<File> file;
    try{file=LocalMediaService().resolve(LocalPhoto.fromJson(metadata));}
    catch(_){return const _Notice('This saved photo reference could not be read. The observation text remains available.');}
    return Padding(padding:const EdgeInsets.symmetric(vertical:12),child:FutureBuilder<File>(future:file,builder:(context,snapshot){
      if(snapshot.hasError)return const _Notice('The local photo is unavailable. The observation text remains saved.');
      if(!snapshot.hasData)return const SizedBox(height:48,child:Center(child:CircularProgressIndicator()));
      return ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.file(snapshot.data!,height:260,width:double.infinity,fit:BoxFit.contain,semanticLabel:label,errorBuilder:(_,error,stack)=>const _Notice('The photo could not be displayed. Your text record is still available.')));
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
