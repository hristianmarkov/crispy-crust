import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/main.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/screens/main_screen.dart';
import 'package:crispy_crust/screens/welcome_screen.dart';

import 'dart:convert';

void main() {
  testWidgets('capture Google Play feature artwork', (tester) async {
    if (const String.fromEnvironment('STORE_PLATFORM') != 'android') return;
    tester.view.physicalSize = const Size(1024, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await (FontLoader('DM Sans')..addFont(rootBundle.load('assets/brand/DMSans-Variable.ttf'))).load();
      await (FontLoader('DM Serif Display')..addFont(rootBundle.load('assets/brand/DMSerifDisplay-Regular.ttf'))).load();
    });
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(false),
      home: RepaintBoundary(key: key, child: Scaffold(backgroundColor: const Color(0xfff7f3e8),
        body: Row(children: [Expanded(child: Padding(padding: const EdgeInsets.all(46),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('CRISPY CRUST BAKING', style: TextStyle(fontSize: 16, letterSpacing: 2, color: Color(0xff39452e))),
            const SizedBox(height: 22),
            const Text('Your next loaf\nstarts here.', style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 54, height: 1.05, color: Color(0xff39452e))),
            const SizedBox(height: 24),
            const Text('Plan a bake. Care for your starter.\nKeep the story of every loaf.', style: TextStyle(fontSize: 19, height: 1.5, color: Color(0xff59614f))),
          ]))),
          Expanded(child: Image.asset('assets/brand/welcome-loaf.webp', width: 512, height: 500, fit: BoxFit.cover)),
        ])))));
    await tester.runAsync(() => precacheImage(const AssetImage('assets/brand/welcome-loaf.webp'), key.currentContext!));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/store-assets/android').create(recursive: true);
      await File('build/store-assets/android/feature-graphic.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    tester.view.physicalSize = const Size(512, 512);
    final iconKey = GlobalKey();
    final iconBytes = (await tester.runAsync(() => File('assets/brand/app-icon.png').readAsBytes()))!;
    await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: iconKey,
      child: Image.memory(iconBytes, fit: BoxFit.fill))));
    await tester.runAsync(() => precacheImage(MemoryImage(iconBytes), iconKey.currentContext!));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image = await (iconKey.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/store-assets/android/app-icon.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
  testWidgets('capture actual Flutter screens for visual review', (
    tester,
  ) async {
    const storePlatform = String.fromEnvironment('STORE_PLATFORM');
    const storeCapture = storePlatform != '';
    tester.view.physicalSize = storePlatform == 'android' ? const Size(360, 640) : storePlatform == 'ipad' ? const Size(1024, 1366) : storePlatform == 'iphone' ? const Size(393, 852) : const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font = FontLoader('DM Sans')
        ..addFont(rootBundle.load('assets/brand/DMSans-Variable.ttf'));
      await font.load();
      final serif = FontLoader('DM Serif Display')
        ..addFont(rootBundle.load('assets/brand/DMSerifDisplay-Regular.ttf'));
      await serif.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final db = LocalDatabase.memory();
    late LocalAppStore store;
    await tester.runAsync(() async {
      final catalogue = jsonDecode(
        await rootBundle.loadString('assets/catalogue.json'),
      ) as Map<String, dynamic>;
      store = LocalAppStore(db, catalogue);
      await store.load();
    });
    final boundary = GlobalKey();
    Future<void> mount(
      Widget screen, {
      bool dark = false,
      double textScale = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: RepaintBoundary(key: boundary, child: screen),
        ),
      );
      final context = boundary.currentContext!;
      await tester.runAsync(
        () => Future.wait([
          for (final path in [
            'assets/brand/welcome-loaf.webp',
            'assets/editorial/loaf-mark.png',
            'assets/editorial/country-loaf.webp',
            'assets/editorial/flatbread.webp',
            'assets/editorial/starter-jar.webp',
            'assets/editorial/jar-4.webp',
            for (var n = 1; n <= 30; n++) 'assets/editorial/r${n.toString().padLeft(2, '0')}.webp',
            'assets/editorial/enriched-dough.webp',
          ])
            precacheImage(
              AssetImage(path),
              context,
              onError: (error, _) => throw error,
            ),
        ]),
      );
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: storePlatform == 'ipad' ? 2 : storeCapture ? 3 : 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = await Directory(storeCapture ? 'build/store-assets/$storePlatform' : 'build/screenshots')
            .create(recursive: true);
        await File('${folder.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    final (jar, guidedBake) = (await tester.runAsync(() async {
      final jar = await store.save('starter', {
        'name': 'Matilda', 'storage': 'counter', 'mass': 140, 'jarWeight': 280,
        'hydration': 100, 'mascot': 4,
        'createdAt': DateTime.now().subtract(const Duration(days: 90)).toIso8601String(),
      });
      final bake = await store.createBake(store.recipes.first,
        startAt: DateTime.now().add(const Duration(minutes: 2)), beginImmediately: true);
      await store.completeStep(bake.id, expectedIndex: 0);
      return (jar, bake);
    }))!;
    await mount(WelcomeScreen(onContinue: () async {}));
    await capture('welcome');
    await mount(MainScreen(store: store));
    for (final title in ['Home', 'Starters', 'Recipes', 'Features', 'Journal']) {
      if (title != 'Home') {
        await tester.tap(find.widgetWithText(NavigationDestination, title));
        await tester.pumpAndSettle();
      }
      await capture(title.toLowerCase());
      if (title == 'Recipes') {
        await tester.tap(find.text('Focaccia'));
        await tester.pumpAndSettle();
        final recipe = store.recipes.firstWhere(
          (recipe) => recipe['family'] == 'focaccia',
        );
        expect(find.text(recipe['title'] as String), findsOneWidget);
        expect(find.text(store.recipes.first['title'] as String), findsNothing);
      }
    }
    await mount(RecipeDetail(store: store, recipe: store.recipes.first));
    await capture('recipe-detail');
    await tester.tap(find.text('Step by step'));
    await tester.pumpAndSettle();
    await capture('recipe-steps');
    await mount(StarterDetail(store: store, id: jar.id));
    await capture('starter-detail');
    await mount(BakeDetail(store: store, id: guidedBake.id));
    await capture('bake-mode');
    if (storeCapture) {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => db.close());
      return;
    }
    await mount(BakeDetail(store: store, id: guidedBake.id), dark: true, textScale: 2);
    await capture('bake-mode-dark-large-text');
    await mount(MainScreen(store: store), dark: true, textScale: 2);
    await tester.ensureVisible(find.text('Bake now'));
    await tester.pumpAndSettle();
    await capture('home-dark-large-text');
    await tester.runAsync(() async {
      final start = DateTime.now()
          .add(const Duration(minutes: 30))
          .toIso8601String();
      await store.save('bake', {
        'name': 'Sunday country loaf',
        'state': 'active',
        'steps': [
          {'title': 'First set of folds', 'plannedStart': start},
        ],
      });
      await store.save('timer', {
        'name': 'Check the dough',
        'state': 'running',
        'dueAt': start,
      });
    });
    await mount(const SizedBox.shrink());
    await mount(MainScreen(store: store));
    await capture('home-active');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => db.close());
  }, timeout: const Timeout(Duration(seconds: 180)));
}
