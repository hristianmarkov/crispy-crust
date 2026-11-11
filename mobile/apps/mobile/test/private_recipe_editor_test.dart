import 'package:baking_domain/baking_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/app_store.dart';
import 'package:crispy_crust/data/planning_adapter.dart';
import 'package:crispy_crust/screens/private_recipe_editor.dart';

List<Map<String, dynamic>> formula() => [
  {'id': 'f', 'name': 'Flour', 'role': 'flour', 'grams': '450'},
  {'id': 'w', 'name': 'Water', 'role': 'water', 'grams': '275'},
  {'id': 's', 'name': 'Starter', 'role': 'starter', 'grams': '100', 'starterHydration': '100'},
  {'id': 'salt', 'name': 'Salt', 'role': 'salt', 'grams': '10'},
];
List<Map<String, dynamic>> method() => [
  {'id': 'mix', 'title': 'Mix', 'instructions': 'Combine weighed ingredients.', 'durationMinutes': '10', 'kind': 'handsOn', 'resources': ['vessel']},
  {'id': 'bulk', 'title': 'Inspect dough', 'instructions': 'Observe the dough.', 'durationMinutes': '180', 'kind': 'check', 'readinessCue': 'Observe aeration and strength.', 'resources': ['vessel']},
  {'id': 'bake', 'title': 'Bake', 'instructions': 'Use your reviewed oven method.', 'durationMinutes': '45', 'kind': 'wait', 'resources': ['oven']},
  {'id': 'cool', 'title': 'Cool', 'instructions': 'Leave on a cooling rack.', 'durationMinutes': '90', 'kind': 'wait', 'resources': ['coolingRack']},
];
Map<String, dynamic> build({List<Map<String, dynamic>>? ingredients, List<Map<String, dynamic>>? steps, bool runnable = true, Map<String, dynamic>? original}) => buildPrivateRecipe(
  title: 'My loaf', source: 'My notes', notes: '', ingredients: ingredients ?? formula(), steps: steps ?? method(), runnable: runnable, original: original);

class RecipeEditorStore extends AppStore {
  final saved = <AppRecord>[];
  @override Future<AppRecord> save(String kind, Map<String, dynamic> fields, {String? id}) async {
    final record = AppRecord(id: id ?? 'new-private-recipe', kind: kind, fields: fields, updatedAt: DateTime.utc(2026, 11, 11));
    saved.add(record); return record;
  }
  @override dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName} was not expected in this editor test.');
}

void main() {
  test('physical starter flour and water are counted exactly once', () {
    final recipe = build();
    expect(recipe['doughMassGrams'], 835);
    expect(recipe['totalFlourGrams'], 500);
    expect(recipe['totalWaterGrams'], 325);
    expect(recipe['hydrationPercent'], 65);
    expect(Rational.fromJson(recipe['hydrationExact']), Rational.parse('0.65'));
    final ingredients = recipe['ingredients'] as List;
    expect(ingredients, hasLength(4));
    expect(ingredients[2]['flourGrams'], 50);
    expect(ingredients[2]['waterGrams'], 50);
  });
  test('multiple starters with different hydration retain exact composition', () {
    final recipe = build(ingredients: [
      {'id': 'f', 'name': 'Flour', 'role': 'flour', 'grams': '400'},
      {'id': 'w', 'name': 'Water', 'role': 'water', 'grams': '250'},
      {'id': 'stiff', 'name': 'Stiff starter', 'role': 'starter', 'grams': '40', 'starterHydration': '50'},
      {'id': 'liquid', 'name': 'Liquid starter', 'role': 'starter', 'grams': '60', 'starterHydration': '125'},
    ]);
    expect(Rational.fromJson(recipe['totalFlourExact']), Rational.parse('1360/3'));
    expect(Rational.fromJson(recipe['totalWaterExact']), Rational.parse('890/3'));
    expect(Rational.fromJson(recipe['hydrationExact']), Rational.parse('89/136'));
    expect(recipe['doughMassGrams'], 750);
  });
  test('unquantified ingredient water stays unknown; impossible composition rejects', () {
    final recipe = build(ingredients: [...formula(), {'id': 'milk', 'name': 'Milk', 'role': 'other', 'grams': '100', 'flourGrams': '', 'waterGrams': ''}]);
    expect(recipe['hydrationPercent'], isNull);
    expect(recipe['totalWaterGrams'], isNull);
    expect(recipe['doughMassGrams'], 935);
    expect(() => build(ingredients: [...formula(), {'id': 'milk', 'name': 'Milk', 'role': 'other', 'grams': '100', 'flourGrams': '30', 'waterGrams': '80'}]), throwsFormatException);
  });
  test('incomplete drafts never expose a runnable graph or fabricate quantities', () {
    final recipe = build(ingredients: [{'id': 'f', 'name': 'Unknown flour', 'grams': ''}], steps: [{'id': 'unknown', 'title': 'Unfinished'}], runnable: false);
    expect(recipe['status'], 'draft'); expect(recipe['schedulable'], isFalse);
    expect(recipe['steps'], isEmpty); expect(recipe['ingredients'], isEmpty);
    expect(recipe['draftIngredients'], hasLength(1)); expect(recipe['draftSteps'], hasLength(1));
    expect(recipe.containsKey('hydrationPercent'), isFalse);
  });
  test('complete method creates sequential resource-aware graph with real active checks', () {
    final recipe = build();
    recipe['id'] = 'private-copy';
    final graph = graphForRecipe(recipe);
    expect(graph.topologicalOrder().map((s) => s.id), ['mix', 'bulk', 'bake', 'cool']);
    expect(graph.steps[1].dependencies, ['mix']);
    expect(graph.steps[1].readinessGate, isTrue);
    expect(graph.steps[1].handsOn.single.offset, const Duration(minutes: 179));
    expect(graph.steps[2].resources, {'oven': 1});
    expect(graph.steps[3].resources, {'coolingRack': 1});
    expect(graph.steps[3].nominalDuration, const Duration(minutes: 90));
  });
  test('zero duration and missing readiness cue block planning; provenance never grants validation', () {
    expect(() => build(steps: [{...method().first, 'durationMinutes': '0'}]), throwsFormatException);
    expect(() => build(steps: [{...method()[1], 'readinessCue': ''}]), throwsFormatException);
    expect(() => build(ingredients: [{...formula().first, 'grams': 'NaN'}]), throwsFormatException);
    final recipe = build(original: {'id': 'source', 'version': 3, 'kitchenValidated': true, 'reviewed_by': 'somebody', 'author': 'Original author'});
    expect(recipe['derivedFromRecipeId'], 'source'); expect(recipe['derivedFromVersion'], 3);
    expect(recipe['sourceAuthor'], 'Original author'); expect(recipe['kitchenValidated'], isFalse);
    expect(recipe.containsKey('reviewed_by'), isFalse); expect(recipe.containsKey('id'), isFalse);
  });
  testWidgets('save incomplete draft preserves edits and never creates a bake', (tester) async {
    final store = RecipeEditorStore(); addTearDown(store.dispose);
    await tester.binding.setSurfaceSize(const Size(430, 920)); addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PrivateRecipeEditor(store: store))), child: const Text('Open editor'))))));
    await tester.tap(find.text('Open editor')); await tester.pumpAndSettle();
    final name = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Recipe name');
    await tester.enterText(name, 'Still working this out');
    final scroll = find.descendant(of: find.byKey(const ValueKey('private-recipe-scroll')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Save incomplete draft'), 400, scrollable: scroll);
    await tester.tap(find.text('Save incomplete draft')); await tester.pumpAndSettle();
    expect(store.saved, hasLength(1));
    expect(store.saved.single.kind, 'recipe'); expect(store.saved.single.text('title'), 'Still working this out');
    expect(store.saved.single.fields['steps'], isEmpty); expect(store.saved.single.flag('schedulable'), isFalse);
    expect(find.text('Open editor'), findsOneWidget); expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
