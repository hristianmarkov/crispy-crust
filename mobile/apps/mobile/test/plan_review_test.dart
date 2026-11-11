import 'package:baking_domain/baking_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/screens/plan_review_screen.dart';

final recipe=<String,dynamic>{'title':'Review fixture','ingredients':[{'name':'Flour','grams':100}], 'steps':[
 {'id':'mix','title':'Mix','kind':'handsOn','resources':<String>[]},
 {'id':'cool','title':'Cool','kind':'wait','resources':['coolingRack']},
]};
ScheduleCandidate candidate()=>ScheduleCandidate(recipeVersion:'fixture-v1',profileVersion:'fixture-only',kitchenTimeZone:'UTC',requiresObservation:false,tasks:[
 ScheduleTask(stepId:'mix',start:DateTime.utc(2026,11,16,9),end:DateTime.utc(2026,11,16,9,10)),
 ScheduleTask(stepId:'cool',start:DateTime.utc(2026,11,16,9,10),end:DateTime.utc(2026,11,16,10)),
],assumptions:['Synthetic timing, not kitchen validation.']);
void main(){
 Future<void> mount(WidgetTester tester,ScheduleCandidate reviewed,List<Map<String,dynamic>> accepted)async{
  await tester.binding.setSurfaceSize(const Size(430,920));addTearDown(()=>tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:FilledButton(onPressed:()async{
   final okay=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>PlanReviewScreen(recipe:recipe,candidate:reviewed,scale:1)));
   if(okay==true)accepted.add(reviewed.toJson());
  },child:const Text('Open proposed schedule'))))));
  await tester.tap(find.text('Open proposed schedule'));await tester.pumpAndSettle();
 }
 Future<void> reveal(WidgetTester tester,String text)async{await tester.scrollUntilVisible(find.text(text),250,scrollable:find.byType(Scrollable).first);await Scrollable.ensureVisible(tester.element(find.text(text)),alignment:.5);await tester.pumpAndSettle();expect(find.text(text).hitTestable(),findsOneWidget);}
 testWidgets('review and cancellation create no accepted schedule', (tester)async{
  final accepted=<Map<String,dynamic>>[];await mount(tester,candidate(),accepted);
  expect(accepted,isEmpty);expect(find.textContaining('No actions have been recorded'),findsOneWidget);
  await reveal(tester,'Change my inputs');await tester.tap(find.text('Change my inputs'));await tester.pumpAndSettle();
  expect(accepted,isEmpty);expect(find.text('Open proposed schedule'),findsOneWidget);expect(tester.takeException(),isNull);
 });
 testWidgets('accept returns the exact candidate that was shown without editing it', (tester)async{
  final accepted=<Map<String,dynamic>>[],reviewed=candidate();await mount(tester,reviewed,accepted);
  await reveal(tester,'Accept this schedule');await tester.tap(find.text('Accept this schedule'));await tester.pumpAndSettle();
  expect(accepted,hasLength(1));expect(accepted.single,reviewed.toJson());expect(reviewed.task('mix').start,DateTime.utc(2026,11,16,9));expect(tester.takeException(),isNull);
 });
}
