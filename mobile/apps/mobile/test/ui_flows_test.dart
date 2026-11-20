import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/main.dart' show CrispyCrustApp, buildTheme;
import 'package:crispy_crust/screens/main_screen.dart';
import 'package:crispy_crust/platform/local_media.dart';
import 'package:crispy_crust/screens/welcome_screen.dart';

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

  testWidgets('fresh install can continue locally and keeps that choice on reopen', (tester) async {
    await tester.pumpWidget(CrispyCrustApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    final local = find.text('Continue locally');
    await tester.ensureVisible(local);
    await tester.runAsync(() async {
      await tester.tap(local);
      // Drain the preference write and initial database connection.
      await store.db.customSelect('SELECT 1').get();
    });
    await tester.pumpAndSettle();
    expect(find.byType(MainScreen), findsOneWidget);
    expect(store.preference('welcomeCompleted'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(CrispyCrustApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('existing local library opens without first-run onboarding', (tester) async {
    await tester.runAsync(() => store.save('starter', {'name': 'Existing starter', 'mass': 50}));
    await tester.pumpWidget(CrispyCrustApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('starter course resumes after legacy and newly recorded practice', (tester) async {
    await tester.runAsync(() => store.save('lessonProgress', {
      'lessonId': 'L01',
      'practisedAt': DateTime.now().toUtc().toIso8601String(),
    }));
    await mount(tester, screen: LearnScreen(store: store));
    await tester.tap(find.text('Open first starter course'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Feed and measure a starter'));
    await tester.pumpAndSettle();
    final recordPractice = find.text('Record that I practised');
    await tester.scrollUntilVisible(recordPractice, 200);
    await tester.tap(recordPractice);
    await tester.pumpAndSettle();
    expect(store.records('lesson_progress').single.text('lessonId'), 'L02');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Continue with Observe temperature and rise'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('fresh local kitchen shows value without forced account and five navigation tabs', (tester) async {
    await mount(tester);
    expect(find.text('Your next bake'), findsOneWidget);
    final tabs = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination));
    expect(tabs.map((tab) => tab.label), ['Starters', 'Recipes', 'Home', 'Features', 'Journal']);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Bake now'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Recipes'));
    await tester.pumpAndSettle();
    expect(find.text('Search recipes'), findsOneWidget);
    await tester.tap(find.text('Sweets'));
    await tester.pumpAndSettle();
    expect(find.text('Cinnamon rolls'), findsOneWidget);
    expect(find.text('Dinner rolls'), findsNothing);
    expect(store.recipes, hasLength(30));
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
    expect(find.text('Log feed'), findsNothing);
    final jar = store.records('starter').single;
    await tester.runAsync(() => store.save('starter', {...jar.fields, 'mass': 60}, id: jar.id));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matilda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('Starter retained (g)')).controller!.text, '60');
    expect(tester.widget<TextField>(field('Starter removed (g)')).controller!.text, '0');
    await tester.enterText(field('Starter removed (g)'), '40');
    expect(tester.widget<TextField>(field('Starter retained (g)')).controller!.text, '20');
    await tester.enterText(field('Flour added (g)'), '40');
    await tester.enterText(field('Water added (g)'), '40');
    await tester.ensureVisible(find.text('Record feed'));
    await tester.tap(find.text('Record feed'));
    await tester.pumpAndSettle();
    expect(store.records('feed'), hasLength(1));
    expect(store.records('starter').single.number('mass'), 100);
    final history=find.text('Feed history');
    await tester.pumpAndSettle();
    expect(history, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds:60)));

  testWidgets('start now only opens a guided bake after confirmation', (tester) async {
    final recipe = store.recipes.first;
    await mount(tester, screen: PlanScreen(store: store, initialRecipe: recipe, standalone: true));
    expect(find.text('Start now'), findsOneWidget);
    await tester.tap(find.text('Review bake'));
    await tester.pumpAndSettle();
    expect(find.text('Review this schedule'), findsOneWidget);
    expect(store.records('bake'), isEmpty);
    await tester.tap(find.text('Start guided bake'));
    await tester.pumpAndSettle();
    expect(store.records('bake').single.text('state'), 'active');
    expect(find.text('Completed'), findsOneWidget);
    expect(find.textContaining('Next step in'), findsNothing);
    await tester.tap(find.byTooltip('Next step'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 2 /'), findsOneWidget);
    expect(find.textContaining('Next step in'), findsNothing);
    await tester.tap(find.byTooltip('Previous step'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Completed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 2 /'), findsOneWidget);
    expect(find.textContaining('Next step in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds:60)));

  testWidgets('two hundred percent text retains usable empty kitchen without layout exception', (tester) async {
    await mount(tester, textScale: 2);
    expect(find.text('Your next bake'), findsOneWidget);
    await tester.ensureVisible(find.text('Bake now'));
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
    await mount(tester, screen: ObservationCaptureScreen(store:store,objectId:starter.id,starter:true));
    await tester.enterText(field('Temperature (°C, optional)'), '23');
    final save = find.widgetWithText(FilledButton, 'Save actual observation').hitTestable();
    await tester.scrollUntilVisible(save, 180, scrollable:pageScroll('observation-scroll'));
    await tester.pumpAndSettle();
    await tester.tap(save);
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
