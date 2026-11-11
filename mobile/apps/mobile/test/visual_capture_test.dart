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
import 'dart:convert';

void main(){
  testWidgets('capture actual Flutter screens for visual review',(tester)async{
    tester.view.physicalSize=const Size(430,932);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font=FontLoader('DM Sans')..addFont(rootBundle.load('assets/brand/DMSans-Variable.ttf'));await font.load();
    });
    final db=LocalDatabase.memory();
    final catalogue=jsonDecode(await rootBundle.loadString('assets/catalogue.json')) as Map<String,dynamic>;
    final store=LocalAppStore(db,catalogue);await store.load();
    final boundary=GlobalKey();
    await tester.pumpWidget(MaterialApp(theme:buildTheme(false),home:RepaintBoundary(key:boundary,child:MainScreen(store:store))));
    await tester.pumpAndSettle();
    for(final title in ['Today','Recipes','Starters','Journal']) {
      if(title!='Today'){await tester.tap(find.text(title).last);await tester.pumpAndSettle();}
      expect(tester.takeException(),isNull);
      final render=boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image=await render.toImage(pixelRatio:2);
      final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
      await tester.runAsync(()async{final folder=await Directory('build/screenshots').create(recursive:true);await File('${folder.path}/${title.toLowerCase()}.png').writeAsBytes(bytes!.buffer.asUint8List());});
      image.dispose();
    }
    await tester.pumpWidget(const SizedBox());await db.close();
  });
}
