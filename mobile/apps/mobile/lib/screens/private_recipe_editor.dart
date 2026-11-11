import 'package:baking_domain/baking_domain.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/app_store.dart';

const privateRecipeResources = <String, String>{
  'oven': 'Oven', 'vessel': 'Mixing vessel', 'fridgeSlot': 'Fridge slot',
  'bakingSurface': 'Baking surface', 'boilingPan': 'Boiling pan',
  'coolingRack': 'Cooling rack', 'hob': 'Hob', 'tin': 'Tin',
  'tray': 'Tray', 'waffleIron': 'Waffle iron',
};

/// A private formula keeps physical weights separate from their flour/water
/// components. Unknown inclusion water is never silently counted as zero.
Map<String, dynamic> buildPrivateRecipe({
  required String title,
  required String source,
  required String notes,
  required List<Map<String, dynamic>> ingredients,
  required List<Map<String, dynamic>> steps,
  required bool runnable,
  Map<String, dynamic>? original,
}) {
  if (title.trim().isEmpty) throw const FormatException('Give the recipe a name.');
  if (title.length > 200 || source.length > 4000 || notes.length > 20000 || ingredients.length > 100 || steps.length > 100) throw const FormatException('This recipe exceeds the supported editing limits.');
  final result = <String, dynamic>{
    'title': title.trim(), 'family': 'Own recipe', 'source': source.trim(),
    'notes': notes.trim(), 'version': 1, 'private': true,
    'status': runnable ? 'user_confirmed' : 'draft',
    'schedulable': runnable, 'experimental': true, 'kitchenValidated': false,
    'requiresExplicitAcceptance': true,
    if (original?['id'] != null) 'derivedFromRecipeId': original!['id'],
    if (original?['version'] != null) 'derivedFromVersion': original!['version'],
    if (original?['sourceUrls'] != null) 'sourceUrls': original!['sourceUrls'],
    if (original?['author'] != null) 'sourceAuthor': original!['author'],
    if (original?['rights'] != null) 'sourceRights': original!['rights'],
  };
  // Incomplete drafts retain editable inputs, but expose no executable graph.
  if (!runnable) return {...result, 'ingredients': <dynamic>[], 'steps': <dynamic>[],
    'draftIngredients': ingredients, 'draftSteps': steps};
  if (ingredients.isEmpty) throw const FormatException('Add the physical ingredients.');
  if (steps.isEmpty) throw const FormatException('Add at least one method step.');
  Rational amount(dynamic value, String label) {
    final text = '$value';
    if (text.length > 40) throw FormatException('$label is too long.');
    Rational valueParsed;
    try { valueParsed = Rational.parse(text); } on Object {
      throw FormatException('Enter a finite weight for $label.');
    }
    if (valueParsed.isNegative || !valueParsed.toDouble().isFinite || valueParsed > Rational.fromNum(1000000)) {
      throw FormatException('$label must be from 0 to 1,000,000.');
    }
    return valueParsed;
  }
  var totalFlour = Rational.zero, totalWater = Rational.zero, totalMass = Rational.zero;
  var knownComposition = true;
  final rows = <Map<String, dynamic>>[];
  final ingredientIds = <String>{};
  for (final ingredient in ingredients) {
    final id = '${ingredient['id'] ?? ''}', name = '${ingredient['name'] ?? ''}'.trim();
    if (id.isEmpty || !ingredientIds.add(id) || name.isEmpty) throw const FormatException('Each ingredient needs a name and a distinct identity.');
    final mass = amount(ingredient['grams'], '$name weight');
    if (mass <= Rational.zero) throw FormatException('$name needs a weight greater than zero.');
    final role = '${ingredient['role'] ?? ''}';
    var flour = Rational.zero, water = Rational.zero;
    var compositionKnown = true;
    switch (role) {
      case 'flour': flour = mass;
      case 'water': water = mass;
      case 'starter':
        final hydration = amount(ingredient['starterHydration'], '$name hydration') / Rational.fromNum(100);
        flour = mass / (Rational.one + hydration); water = mass - flour;
      case 'salt': break;
      case 'other':
        final flourInput = '${ingredient['flourGrams'] ?? ''}'.trim(), waterInput = '${ingredient['waterGrams'] ?? ''}'.trim();
        compositionKnown = flourInput.isNotEmpty && waterInput.isNotEmpty;
        if (compositionKnown) {
          flour = amount(flourInput, '$name flour component'); water = amount(waterInput, '$name water component');
          if (flour + water > mass) throw FormatException('$name flour and water components exceed its physical weight.');
        }
      default: throw FormatException('Choose the ingredient type for $name.');
    }
    knownComposition = knownComposition && compositionKnown;
    totalFlour = totalFlour + flour; totalWater = totalWater + water; totalMass = totalMass + mass;
    rows.add({...ingredient, 'name': name, 'grams': mass.toDouble(), 'gramsExact': mass.toJson(),
      'flourGrams': compositionKnown ? flour.toDouble() : null,
      'waterGrams': compositionKnown ? water.toDouble() : null,
      'flourGramsExact': compositionKnown ? flour.toJson() : null,
      'waterGramsExact': compositionKnown ? water.toJson() : null,
      'compositionKnown': compositionKnown,
      if (role == 'starter') 'hydration': amount(ingredient['starterHydration'], '$name hydration').toDouble()});
  }
  if (totalFlour <= Rational.zero) throw const FormatException('Record at least one flour or starter flour component.');
  final graph = <Map<String, dynamic>>[];
  final stepIds = <String>{};
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i], id = '${steps[i]['id'] ?? ''}';
    final name = '${step['title'] ?? ''}'.trim(), instructions = '${step['instructions'] ?? ''}'.trim();
    final kind = '${step['kind'] ?? ''}';
    if (id.isEmpty || !stepIds.add(id) || name.isEmpty || instructions.isEmpty) throw FormatException('Step ${i + 1} needs a title and instructions.');
    final minutes = int.tryParse('${step['durationMinutes']}');
    if (minutes == null || minutes < 1 || minutes > 43200) throw FormatException('Step ${i + 1} needs a whole duration from 1 to 43,200 minutes.');
    if (!{'handsOn', 'wait', 'check'}.contains(kind)) throw FormatException('Choose the type of step ${i + 1}.');
    final cue = '${step['readinessCue'] ?? ''}'.trim();
    if (kind == 'check' && cue.isEmpty) throw FormatException('Step ${i + 1} needs an observable readiness cue.');
    final resources = List<String>.from(step['resources'] as List? ?? []);
    if (resources.any((r) => !privateRecipeResources.containsKey(r))) throw FormatException('Step ${i + 1} has an unknown resource.');
    graph.add({...step, 'title': name, 'instructions': instructions, 'durationMinutes': minutes,
      'kind': kind, 'readinessGate': kind == 'check', 'readinessCue': cue,
      'resources': resources.toSet().toList(), 'after': i == 0 ? <String>[] : [graph.last['id']],
      'timingStatus': 'user_entered_experimental'});
  }
  return {...result, 'ingredients': rows, 'steps': graph,
    'doughMassGrams': totalMass.toDouble(), 'doughMassExact': totalMass.toJson(),
    'totalFlourGrams': knownComposition ? totalFlour.toDouble() : null,
    'totalWaterGrams': knownComposition ? totalWater.toDouble() : null,
    'totalFlourExact': knownComposition ? totalFlour.toJson() : null,
    'totalWaterExact': knownComposition ? totalWater.toJson() : null,
    'hydrationPercent': knownComposition ? (totalWater / totalFlour * Rational.fromNum(100)).toDouble() : null,
    'hydrationExact': knownComposition ? (totalWater / totalFlour).toJson() : null,
    'hydrationBasis': knownComposition ? 'Physical flour and water, including each starter exactly once. Stored exact fractions are not display rounding.' : 'Unknown: an ingredient has unquantified flour or water. No effective hydration is asserted.'};
}

class PrivateRecipeEditor extends StatefulWidget {
  const PrivateRecipeEditor({super.key, required this.store, this.original});
  final AppStore store;
  final Map<String, dynamic>? original;
  @override State<PrivateRecipeEditor> createState() => _PrivateRecipeEditorState();
}

class _IngredientInput {
  _IngredientInput(Map<String, dynamic> row) : id = '${row['id'] ?? const Uuid().v4()}',
    name = TextEditingController(text: '${row['name'] ?? ''}'),
    grams = TextEditingController(text: '${row['grams'] ?? ''}'),
    hydration = TextEditingController(text: '${row['starterHydration'] ?? row['hydration'] ?? _hydration(row) ?? ''}'),
    flour = TextEditingController(text: '${row['flourGrams'] ?? ''}'), water = TextEditingController(text: '${row['waterGrams'] ?? ''}'),
    role = {'flour', 'water', 'starter', 'salt', 'other'}.contains(row['role']) ? '${row['role']}' : 'other',
    metadata = Map<String, dynamic>.from(row);
  static num? _hydration(Map<String, dynamic> row) => row['flourGrams'] is num && row['waterGrams'] is num && (row['flourGrams'] as num) > 0 ? (row['waterGrams'] as num) / (row['flourGrams'] as num) * 100 : null;
  final String id;
  final Map<String, dynamic> metadata;
  final TextEditingController name, grams, hydration, flour, water;
  String role;
  List<TextEditingController> get controllers => [name, grams, hydration, flour, water];
  Map<String, dynamic> toJson() => {...metadata, 'id': id, 'name': name.text, 'grams': grams.text, 'role': role, 'starterHydration': hydration.text, 'flourGrams': flour.text, 'waterGrams': water.text};
  void dispose() { for (final c in controllers) { c.dispose(); } }
}

class _StepInput {
  _StepInput(Map<String, dynamic> row) : id = '${row['id'] ?? const Uuid().v4()}',
    title = TextEditingController(text: '${row['title'] ?? ''}'), instructions = TextEditingController(text: '${row['instructions'] ?? ''}'),
    minutes = TextEditingController(text: '${row['durationMinutes'] ?? ''}'), cue = TextEditingController(text: '${row['readinessCue'] ?? ''}'),
    kind = {'handsOn', 'wait', 'check'}.contains(row['kind']) ? '${row['kind']}' : 'handsOn',
    resources = Set<String>.from(row['resources'] as List? ?? []), metadata = Map<String, dynamic>.from(row);
  final String id;
  final Map<String, dynamic> metadata;
  final TextEditingController title, instructions, minutes, cue;
  String kind;
  final Set<String> resources;
  List<TextEditingController> get controllers => [title, instructions, minutes, cue];
  Map<String, dynamic> toJson() => {...metadata, 'id': id, 'title': title.text, 'instructions': instructions.text, 'durationMinutes': minutes.text, 'kind': kind, 'readinessCue': cue.text, 'resources': resources.toList()};
  void dispose() { for (final c in controllers) { c.dispose(); } }
}

class _PrivateRecipeEditorState extends State<PrivateRecipeEditor> {
  late final title = TextEditingController(text: '${widget.original?['title'] ?? ''}');
  late final source = TextEditingController(text: '${widget.original?['source'] ?? ''}');
  late final notes = TextEditingController(text: '${widget.original?['notes'] ?? ''}');
  final ingredients = <_IngredientInput>[], steps = <_StepInput>[];
  final retiredIngredients = <_IngredientInput>[], retiredSteps = <_StepInput>[];
  bool dirty = false, allowLeave = false, busy = false, confirmed = false;
  String? error;
  @override void initState() {
    super.initState();
    final original = widget.original;
    for (final row in (original?['draftIngredients'] ?? original?['ingredients'] ?? <dynamic>[]) as List) { ingredients.add(_IngredientInput(Map<String, dynamic>.from(row as Map))); }
    for (final row in (original?['draftSteps'] ?? original?['steps'] ?? <dynamic>[]) as List) { steps.add(_StepInput(Map<String, dynamic>.from(row as Map))); }
    if (ingredients.isEmpty) { ingredients.add(_IngredientInput({'name': 'Flour', 'role': 'flour'})); }
    if (steps.isEmpty) { steps.add(_StepInput({})); }
    for (final c in [title, source, notes, ...ingredients.expand((i) => i.controllers), ...steps.expand((s) => s.controllers)]) { c.addListener(changed); }
  }
  void changed() { if (mounted) setState(() { dirty = true; confirmed = false; error = null; }); }
  @override void dispose() {
    title.dispose(); source.dispose(); notes.dispose();
    for (final row in [...ingredients, ...retiredIngredients]) { row.dispose(); }
    for (final row in [...steps, ...retiredSteps]) { row.dispose(); }
    super.dispose();
  }
  Future<void> save(bool runnable) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      if (runnable && !confirmed) throw const FormatException('Review and confirm your experimental method first.');
      final recipe = buildPrivateRecipe(title: title.text, source: source.text, notes: notes.text,
        ingredients: ingredients.map((i) => i.toJson()).toList(), steps: steps.map((s) => s.toJson()).toList(), runnable: runnable, original: widget.original);
      final saved = await widget.store.save('recipe', recipe);
      if (mounted) { setState(() => allowLeave = true); Navigator.pop(context, saved); }
    } on Object catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> leaving(bool didPop) async {
    if (didPop || busy) return;
    final discard = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Leave this recipe draft?'),
      content: const Text('Your edits have not been saved. Keep editing to save a draft or discard these changes.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep editing')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard changes'))]));
    if (discard == true && mounted) { setState(() => allowLeave = true); Navigator.pop(context); }
  }
  Future<void> review() async {
    try {
      final recipe = buildPrivateRecipe(title: title.text, source: source.text, notes: notes.text,
        ingredients: ingredients.map((i) => i.toJson()).toList(), steps: steps.map((s) => s.toJson()).toList(), runnable: true, original: widget.original);
      await showDialog<void>(context: context, builder: (c) => AlertDialog(title: const Text('Review your formula'), content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        for (final row in recipe['ingredients'] as List) Text('${row['name']}: ${(row['grams'] as num).toStringAsFixed(2)} g'),
        const SizedBox(height: 12), Text('Physical dough: ${(recipe['doughMassGrams'] as num).toStringAsFixed(2)} g'),
        Text(recipe['hydrationPercent'] == null ? 'Hydration unknown: ingredient components are incomplete.' : 'Hydration: ${(recipe['hydrationPercent'] as num).toStringAsFixed(2)}%, including starter flour and water.'),
        const SizedBox(height: 12),
        for (final step in recipe['steps'] as List) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${step['title']}: ${step['durationMinutes']} min · ${step['kind']}\nReserves: ${(step['resources'] as List).isEmpty ? 'none' : (step['resources'] as List).join(', ')}')),
        const Text('Display weights are rounded. Exact stored fractions are preserved. A schedule will still need to fit your availability and equipment.'),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Return to editing'))]));
    } on Object catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  Widget input(TextEditingController controller, String label, {bool numeric = false, bool multiline = false}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: controller,
    decoration: InputDecoration(labelText: label), minLines: multiline ? 2 : 1, maxLines: multiline ? 5 : 1,
    keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : multiline ? TextInputType.multiline : TextInputType.text));
  Widget panel(List<Widget> children, {Key? key}) => Card(key: key, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)));
  @override Widget build(BuildContext context) => PopScope(canPop: allowLeave || (!dirty && !busy), onPopInvokedWithResult: (didPop, _) => leaving(didPop),
    child: Scaffold(appBar: AppBar(title: const Text('Your private recipe')), body: SafeArea(child: ListView(key: const ValueKey('private-recipe-scroll'), padding: const EdgeInsets.all(20), children: [
      const Text('Keep exact weights and a method you can follow. A private variation is a new copy; it never changes an existing bake.'), const SizedBox(height: 16),
      input(title, 'Recipe name'), input(source, 'Source / attribution (optional)'), input(notes, 'Private notes (optional)', multiline: true),
      Text('Physical ingredients', style: Theme.of(context).textTheme.titleLarge),
      const Text('Enter each physical ingredient once. Starter flour and water are calculated from its hydration. For other ingredients, leave unknown components blank; hydration will stay unknown.'),
      for (var i = 0; i < ingredients.length; i++) ingredientCard(ingredients[i], i),
      OutlinedButton.icon(onPressed: busy ? null : () { final row = _IngredientInput({}); for (final c in row.controllers) { c.addListener(changed); } setState(() { ingredients.add(row); dirty = true; confirmed = false; }); }, icon: const Icon(Icons.add), label: const Text('Add ingredient')),
      const SizedBox(height: 24), Text('Method in order', style: Theme.of(context).textTheme.titleLarge),
      const Text('Each step starts after the previous one. Include rests, preheating, baking and cooling. Resource selections reserve that item for the whole step. A readiness check includes a hands-on check at its end.'),
      for (var i = 0; i < steps.length; i++) stepCard(steps[i], i),
      OutlinedButton.icon(onPressed: busy ? null : () { final row = _StepInput({}); for (final c in row.controllers) { c.addListener(changed); } setState(() { steps.add(row); dirty = true; confirmed = false; }); }, icon: const Icon(Icons.add), label: const Text('Add method step')),
      const SizedBox(height: 20), OutlinedButton(onPressed: busy ? null : review, child: const Text('Review weights and method inputs')),
      CheckboxListTile(contentPadding: EdgeInsets.zero, value: confirmed, onChanged: busy ? null : (v) => setState(() => confirmed = v ?? false), title: const Text('I reviewed the full experimental method'), subtitle: const Text('Weights, timing, readiness cues and equipment are my inputs. This is not a kitchen-tested method.')),
      if (error != null) Semantics(liveRegion: true, child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      FilledButton(onPressed: busy || !confirmed ? null : () => save(true), child: Text(busy ? 'Saving…' : 'Save formula ready for planning')),
      OutlinedButton(onPressed: busy ? null : () => save(false), child: const Text('Save incomplete draft')),
    ]))));
  Widget ingredientCard(_IngredientInput row, int index) => panel([
    Text('Ingredient ${index + 1}', style: Theme.of(context).textTheme.titleMedium),
    input(row.name, 'Ingredient ${index + 1} name'), input(row.grams, 'Ingredient ${index + 1} weight (g)', numeric: true),
    DropdownButtonFormField<String>(initialValue: row.role, isExpanded: true, decoration: const InputDecoration(labelText: 'Ingredient type'),
      items: const [DropdownMenuItem(value: 'flour', child: Text('Flour')), DropdownMenuItem(value: 'water', child: Text('Water')), DropdownMenuItem(value: 'starter', child: Text('Starter / levain')), DropdownMenuItem(value: 'salt', child: Text('Salt')), DropdownMenuItem(value: 'other', child: Text('Other ingredient'))],
      onChanged: busy ? null : (v) => setState(() { row.role = v!; dirty = true; confirmed = false; })),
    const SizedBox(height: 12),
    if (row.role == 'starter') input(row.hydration, 'Starter hydration (%)', numeric: true),
    if (row.role == 'other') ...[input(row.flour, 'Known flour component (g, optional)', numeric: true), input(row.water, 'Known water component (g, optional)', numeric: true)],
    TextButton(onPressed: busy ? null : () => setState(() { retiredIngredients.add(row); ingredients.removeAt(index); dirty = true; confirmed = false; }), child: const Text('Remove ingredient')),
  ], key: ValueKey('ingredient-${row.id}'));
  Widget stepCard(_StepInput row, int index) => panel([
    Text('Step ${index + 1}', style: Theme.of(context).textTheme.titleMedium),
    input(row.title, 'Step ${index + 1} title'), input(row.instructions, 'Step ${index + 1} instructions', multiline: true), input(row.minutes, 'Step ${index + 1} duration (whole minutes)', numeric: true),
    DropdownButtonFormField<String>(initialValue: row.kind, isExpanded: true, decoration: const InputDecoration(labelText: 'Step type'),
      items: const [DropdownMenuItem(value: 'handsOn', child: Text('Hands-on task')), DropdownMenuItem(value: 'wait', child: Text('Passive wait / rest')), DropdownMenuItem(value: 'check', child: Text('Wait then readiness check'))],
      onChanged: busy ? null : (v) => setState(() { row.kind = v!; dirty = true; confirmed = false; })),
    const SizedBox(height: 12), input(row.cue, 'What should I observe before moving on?', multiline: true),
    Wrap(spacing: 8, children: [for (final resource in privateRecipeResources.entries) FilterChip(label: Text(resource.value), selected: row.resources.contains(resource.key), onSelected: busy ? null : (v) => setState(() { if (v) { row.resources.add(resource.key); } else { row.resources.remove(resource.key); } dirty = true; confirmed = false; }))]),
    Wrap(spacing: 8, children: [if (index > 0) TextButton(onPressed: busy ? null : () => setState(() { steps.removeAt(index); steps.insert(index - 1, row); dirty = true; confirmed = false; }), child: const Text('Move earlier')),
      if (index + 1 < steps.length) TextButton(onPressed: busy ? null : () => setState(() { steps.removeAt(index); steps.insert(index + 1, row); dirty = true; confirmed = false; }), child: const Text('Move later')),
      TextButton(onPressed: busy ? null : () => setState(() { retiredSteps.add(row); steps.removeAt(index); dirty = true; confirmed = false; }), child: const Text('Remove step'))]),
  ], key: ValueKey('step-${row.id}'));
}
