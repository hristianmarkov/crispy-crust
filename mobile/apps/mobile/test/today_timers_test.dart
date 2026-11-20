import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/screens/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main(){
  testWidgets('Home merges a step only with its own timer', (tester) async {
    final db = LocalDatabase.memory();
    final store = LocalAppStore(db, {});
    await tester.runAsync(() async {
      final due = DateTime.now().subtract(const Duration(minutes: 2)).toIso8601String();
      await store.load();
      await store.save('bake', {
        'name': 'Weekend loaf', 'state': 'active', 'steps': [
          {'id': 'fold', 'title': 'Fold dough', 'plannedStart': due},
        ],
      }, id: 'loaf');
      for (final (id, step) in [('matching', 'fold'), ('different', 'proof')]) {
        await store.save('timer', {
          'name': 'Fold dough', 'bakeId': 'loaf', 'stepId': step, 'dueAt': due, 'state': 'running',
        }, id: id);
      }
    });
    await tester.pumpWidget(MaterialApp(home: MainScreen(store: store)));
    expect(find.widgetWithText(ListTile, 'Fold dough'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
    store.dispose();
  });

  testWidgets('timer centre snoozes an overdue check without completing it', (tester) async {
    final db = LocalDatabase.memory();
    final store = LocalAppStore(db, {});
    final deadline = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
    await tester.runAsync(() async {
      await store.load();
      await store.save('timer', {
        'name': 'Check dough',
        'state': 'running',
        'dueAt': deadline.toIso8601String(),
      }, id: 'dough-check');
    });
    await tester.pumpWidget(MaterialApp(home: TimerCentreScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check due'), findsOneWidget);

    await tester.tap(find.text('Snooze 5 min'));
    await tester.pumpAndSettle();

    final timer = store.find('dough-check')!;
    expect(timer.text('state'), 'running');
    expect(timer.date('originalDueAt'), deadline);
    expect(timer.date('dueAt')!.difference(timer.date('snoozedAt')!), const Duration(minutes: 5));
    expect(find.textContaining('Due in'), findsOneWidget);
    expect(find.text('Snooze 5 min'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
    store.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('outstanding timer remains on Home after its bake completes', (tester)async{
    final db=LocalDatabase.memory();
    final store=LocalAppStore(db,{});
    await tester.runAsync(()async{
      await store.load();
      await store.save('bake',{'name':'Finished loaf','state':'complete','status':'complete'},id:'done-bake');
      await store.save('timer',{'name':'Check cooling loaf','bakeId':'done-bake','bakeName':'Finished loaf','state':'running','dueAt':DateTime.now().toUtc().subtract(const Duration(minutes:2)).toIso8601String()},id:'cooling-check');
    });
    await tester.pumpWidget(MaterialApp(home:MainScreen(store:store)));
    await tester.pumpAndSettle();
    expect(find.text('Kitchen timeline'),findsOneWidget);
    expect(find.text('Check cooling loaf'),findsOneWidget);
    await tester.tap(find.text('Check cooling loaf'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check due'),findsOneWidget);
    await Scrollable.ensureVisible(tester.element(find.text('Acknowledge timer')),alignment:.5);
    await tester.pumpAndSettle();
    expect(find.text('Acknowledge timer').hitTestable(),findsOneWidget);
    await tester.tap(find.text('Acknowledge timer'));
    await tester.pumpAndSettle();
    expect(store.find('cooling-check')!.text('state'),'acknowledged');
    expect(find.text('Check cooling loaf'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
    store.dispose();
  },timeout:const Timeout(Duration(seconds:60)));
}
