import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/platform/recipe_book_export.dart';
import 'package:crispy_crust/screens/journal_book_screen.dart';
class FakeBookExporter extends RecipeBookExporter{
  int builds=0;bool? notes,photos;
  @override Future<RecipeBookResult> build(List<RecipeBookEntry> entries,{bool includeNotes=false,bool includeTimes=true,bool includePhotos=false,String title='My Crispy Crust recipe book'})async{builds++;notes=includeNotes;photos=includePhotos;return RecipeBookResult(Uint8List.fromList([37,80,68,70]),1,0,[]);}
}
void main(){
  late LocalDatabase db;late LocalAppStore store;
  setUp(()async{db=LocalDatabase.memory();store=LocalAppStore(db,{'recipes':[],'lessons':[],'guidance':[]});await store.load();});
  tearDown(()async{store.dispose();await db.close();});
  testWidgets('book selection never generates or shares automatically; notes and photos default off',(tester)async{
    await tester.runAsync(()=>store.save('bake',{'name':'My recorded bake','state':'complete','ingredients':[{'name':'Flour','grams':500}],'steps':[],'notes':'PRIVATE-NOTE'}));
    final exporter=FakeBookExporter();
    await tester.binding.setSurfaceSize(const Size(500,1000));addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:JournalBookScreen(store:store,exporter:exporter)));await tester.pumpAndSettle();
    expect(exporter.builds,0);expect(find.text('0 bakes selected · 0 photos chosen'),findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).first);await tester.pumpAndSettle();
    expect(find.text('1 bakes selected · 0 photos chosen'),findsOneWidget);
    final scroll=find.descendant(of:find.byKey(const ValueKey('recipe-book-scroll')),matching:find.byType(Scrollable)).first;
    final prepare=find.widgetWithText(FilledButton,'Prepare selected PDF locally');
    await tester.scrollUntilVisible(prepare,200,scrollable:scroll);await tester.tap(prepare);await tester.pumpAndSettle();
    expect(exporter.builds,1);expect(exporter.notes,isFalse);expect(exporter.photos,isFalse);
    final preparedStatus=find.textContaining('Prepared locally: 1 pages');
    await tester.scrollUntilVisible(preparedStatus,-250,scrollable:scroll);
    await tester.pumpAndSettle();
    expect(preparedStatus,findsOneWidget);
  },timeout:const Timeout(Duration(seconds:60)));
}
