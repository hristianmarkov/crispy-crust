import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/screens/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main(){
  testWidgets('outstanding timer remains on Today after its bake completes', (tester)async{
    final db=LocalDatabase.memory();
    final store=LocalAppStore(db,{});
    await tester.runAsync(()async{
      await store.load();
      await store.save('bake',{'name':'Finished loaf','state':'complete','status':'complete'},id:'done-bake');
      await store.save('timer',{'name':'Check cooling loaf','bakeId':'done-bake','bakeName':'Finished loaf','state':'running','dueAt':DateTime.now().toUtc().subtract(const Duration(minutes:2)).toIso8601String()},id:'cooling-check');
    });
    await tester.pumpWidget(MaterialApp(home:MainScreen(store:store)));
    await tester.pumpAndSettle();
    expect(find.text('Saved checks and timers'),findsOneWidget);
    expect(find.text('Check cooling loaf'),findsOneWidget);
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
