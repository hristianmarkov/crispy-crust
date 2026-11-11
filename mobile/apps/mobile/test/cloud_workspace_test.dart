import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/screens/cloud_workspace_screen.dart';

class FakeCloudApi implements CloudWorkspaceApi {
  final calls=<Map<String,dynamic>>[];
  String? failPath;
  @override Future<dynamic> request(String path,{String method='GET',Map<String,dynamic>? body})async{
    calls.add({'path':path,'method':method,'body':body});
    if(path==failPath)throw const CloudWorkspaceException('PROVIDER_UNAVAILABLE','The provider is unavailable.');
    if(path=='/kitchens')return [{'id':'11111111-1111-4111-8111-111111111111','name':'Home','kind':'personal'}];
    if(path=='/coach/requests')return {'job_id':'22222222-2222-4222-8222-222222222222','status':'queued'};
    if(path.startsWith('/jobs/'))return [{'id':path.split('/').last,'status':'failed','error_code':'PROVIDER_NOT_CONFIGURED'}];
    if(path=='/community/feed')return [];
    return {'ok':true};
  }
}
void main(){
  late LocalDatabase db;late LocalAppStore store;late FakeCloudApi api;
  setUp(()async{db=LocalDatabase.memory();store=LocalAppStore(db,{'recipes':[],'lessons':[],'guidance':[]});await store.load();api=FakeCloudApi();});
  tearDown(()async{store.dispose();await db.close();});
  Future<void> mount(WidgetTester tester)async{await tester.binding.setSurfaceSize(const Size(500,1000));addTearDown(()=>tester.binding.setSurfaceSize(null));await tester.pumpWidget(MaterialApp(home:CloudWorkspaceScreen.withApi(store:store,api:api)));await tester.pumpAndSettle();}
  Future<void> settleDialog(WidgetTester tester)async{await tester.pumpAndSettle();await tester.pump(const Duration(milliseconds:300));await tester.pumpAndSettle();}
  testWidgets('opening cloud workspace reads membership but never uploads local records', (tester)async{
    await tester.runAsync(()=>store.save('starter',{'name':'Private starter','hydration':100}));
    await mount(tester);
    expect(api.calls.map((c)=>c['path']),['/kitchens']);
    expect(find.text('Cloud kitchen'),findsOneWidget);
    expect(find.textContaining('Local library backup remains unchanged'),findsOneWidget);
    expect(store.records('starter'),hasLength(1));
  }, timeout: const Timeout(Duration(seconds:60)));
  testWidgets('coach preview excludes unrelated private observation text and cancelling uploads nothing',(tester)async{
    await tester.runAsync(()=>store.save('observation',{'objectId':'local-bake','temperature':'23','rise':'30','note':'PRIVATE-NOTE-DO-NOT-UPLOAD','occurredAt':'2026-11-11T12:00:00Z'}));
    await mount(tester);
    await tester.tap(find.text('Help & jobs'));await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);await tester.pumpAndSettle();
    await tester.tap(find.text('Preview and request coach help'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'What should I check next?');
    await tester.tap(find.text('Continue'));await settleDialog(tester);
    expect(find.text('Send only this context to the coach?'),findsOneWidget);
    expect(find.textContaining('PRIVATE-NOTE-DO-NOT-UPLOAD'),findsNothing);
    expect(find.textContaining('temperature_c'),findsOneWidget);
    await tester.tap(find.text('Cancel'));await settleDialog(tester);
    expect(api.calls.where((c)=>c['method']=='POST'),isEmpty);
    expect(find.text('No context uploaded.'),findsOneWidget);
  }, timeout: const Timeout(Duration(seconds:60)));
  testWidgets('confirmed coach request grants exact consent before queueing and shows no invented answer',(tester)async{
    await mount(tester);await tester.tap(find.text('Help & jobs'));await tester.pumpAndSettle();
    await tester.tap(find.text('Preview and request coach help'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'How do I record an unknown peak?');
    await tester.tap(find.text('Continue'));await settleDialog(tester);
    await tester.tap(find.text('Confirm selected action'));await settleDialog(tester);
    final writes=api.calls.where((c)=>c['method']=='POST').toList();
    expect(writes.map((c)=>c['path']),['/consents','/coach/requests']);
    expect(writes.first['body'],{'purpose':'coach','version':'1','granted':true});
    expect((writes.last['body'] as Map)['context'],{'observations':[]});
    expect(find.textContaining('no guidance has been invented'),findsOneWidget);
    expect(store.records('bake'),isEmpty);
  }, timeout: const Timeout(Duration(seconds:60)));
  testWidgets('a failed cloud request is visible and does not claim success',(tester)async{
    api.failPath='/kitchens';await mount(tester);
    expect(find.textContaining('Not completed:'),findsOneWidget);
    expect(find.textContaining('PROVIDER_UNAVAILABLE'),findsOneWidget);
    expect(api.calls,hasLength(1));
  }, timeout: const Timeout(Duration(seconds:60)));
}
