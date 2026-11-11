import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/main.dart' show buildTheme;
import 'package:crispy_crust/screens/main_screen.dart';
import 'package:crispy_crust/platform/local_media.dart';

void main() {
  late LocalDatabase db;
  late LocalAppStore store;
  setUp(() async {
    db = LocalDatabase.memory();
    final catalogue = jsonDecode(File('assets/catalogue.json').readAsStringSync()) as Map<String, dynamic>;
    store = LocalAppStore(db, catalogue);
    await store.load();
  });
  tearDown(() async {store.dispose(); await db.close();});

  Future<void> mount(WidgetTester tester, {double textScale = 1, Widget? screen}) async {
    await tester.binding.setSurfaceSize(const Size(430, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(false), builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!), home: screen ?? MainScreen(store: store)));
    await tester.pumpAndSettle();
  }
  Finder pageScroll(String key) => find.descendant(of:find.byKey(ValueKey(key)),matching:find.byType(Scrollable)).first;
  Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

  testWidgets('fresh local kitchen shows value without forced account and five navigation tabs', (tester) async {
    await mount(tester);
    expect(find.text('Make room for your first bake'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Plan a bake'), findsOneWidget);
    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    expect(find.text('Search your recipes'), findsOneWidget);
    expect(store.recipes, hasLength(24));
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds:60)));

  testWidgets('add starter then record actual seed flour and water', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Starters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a starter'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Jar name'), 'Matilda');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.records('starter'), hasLength(1));
    expect(store.records('starter').single.text('name'), 'Matilda');
    await tester.tap(find.text('Log a feed'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Starter retained / seed (g)'), '20');
    await tester.enterText(field('Flour added (g)'), '40');
    await tester.enterText(field('Water added (g)'), '40');
    await tester.ensureVisible(find.text('Record feed'));
    await tester.tap(find.text('Record feed'));
    await tester.pumpAndSettle();
    expect(store.records('feed'), hasLength(1));
    expect(store.records('starter').single.number('mass'), 100);
    expect(find.text('Actual feed history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds:60)));

  testWidgets('experimental recipe cannot create a plan before explicit review acknowledgement', (tester) async {
    final recipe = store.recipes.first;
    await mount(tester, screen: PlanScreen(store: store, initialRecipe: recipe, standalone: true));
    final button = find.widgetWithText(FilledButton, 'Create and review bake plan');
    await tester.scrollUntilVisible(button,200,scrollable:pageScroll('plan-scroll'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    final consent = find.byType(CheckboxListTile);
    await tester.scrollUntilVisible(consent,-200,scrollable:pageScroll('plan-scroll'));
    await tester.tap(consent);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(store.records('bake'), isEmpty); // Acknowledging alone is not acceptance.
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds:60)));

  testWidgets('two hundred percent text retains usable empty kitchen without layout exception', (tester) async {
    await mount(tester, textScale: 2);
    expect(find.text('Make room for your first bake'), findsOneWidget);
    await tester.ensureVisible(find.text('Plan a bake'));
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds:60)));

  testWidgets('local privacy export and import controls remain accessible without a subscription', (tester) async {
    await mount(tester, screen: PrivacyScreen(store: store));
    expect(find.text('Export all my local records'), findsOneWidget);
    expect(find.text('Import an archive'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds:60)));
  testWidgets('manual observation needs no camera permission and keeps unknown photo empty', (tester) async {
    final starter = (await tester.runAsync(()=>store.save('starter', {'name':'Manual jar','hydration':100,'flour':'Bread flour','storage':'counter'})))!;
    await mount(tester, screen: StarterDetail(store:store,id:starter.id));
    await tester.tap(find.text('Record rise or temperature'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Temperature (°C, optional)'), '23');
    await tester.scrollUntilVisible(find.text('Save actual observation'), 250, scrollable:pageScroll('observation-scroll'));
    await tester.tap(find.text('Save actual observation'));
    await tester.pumpAndSettle();
    expect(store.records('observation'),hasLength(1));
    expect(store.records('observation').single.text('temperature'),'23');
    expect(store.records('observation').single.fields.containsKey('photo'),isFalse);
    expect(tester.takeException(),isNull);
  }, timeout: const Timeout(Duration(seconds:60)));

  testWidgets('cancelling photo picker preserves typed observation notes and sends nothing', (tester) async {
    var pickerCalls=0;
    final media=LocalMediaService(picker:(camera)async{pickerCalls++;return null;});
    await mount(tester,screen:ObservationCaptureScreen(store:store,objectId:'local-starter',starter:true,media:media));
    final noteField=field('What can you see or feel? (optional)');
    await tester.ensureVisible(noteField);
    await tester.enterText(noteField,'Bubbly; peak not observed');
    await tester.scrollUntilVisible(find.text('Choose a photo'),200,scrollable:pageScroll('observation-scroll'));
    await tester.tap(find.text('Choose a photo'));await tester.pumpAndSettle();
    expect(pickerCalls,1);
    expect(tester.widget<TextField>(noteField).controller!.text,'Bubbly; peak not observed');
    expect(store.records('observation'),isEmpty);
    expect(find.text('Remove this attachment'),findsNothing);
    expect(tester.takeException(),isNull);
  }, timeout: const Timeout(Duration(seconds:60)));
  testWidgets('photo permission failure preserves observation draft with a clear error', (tester) async {
    final media=LocalMediaService(picker:(camera)async{throw const LocalMediaFailure('PERMISSION_DENIED');});
    await mount(tester,screen:ObservationCaptureScreen(store:store,objectId:'local-bake',starter:false,media:media));
    final noteField=field('What can you see or feel? (optional)');
    await tester.enterText(noteField,'Dough still feels dense');
    await tester.scrollUntilVisible(find.text('Take a photo'),200,scrollable:pageScroll('observation-scroll'));
    await tester.tap(find.text('Take a photo'));await tester.pumpAndSettle();
    expect(tester.widget<TextField>(noteField).controller!.text,'Dough still feels dense');
    expect(find.textContaining('Photo was not attached:'),findsOneWidget);
    expect(store.records('observation'),isEmpty);
    expect(tester.takeException(),isNull);
  }, timeout: const Timeout(Duration(seconds:60)));

}
