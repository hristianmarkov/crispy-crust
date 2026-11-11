import 'dart:async';
import 'package:flutter/material.dart';
import 'data/local_store.dart';
import 'data/sync_client.dart';
import 'screens/cloud_workspace_screen.dart';
import 'screens/probe_screen.dart';
import 'platform/cloud_session.dart';
import 'platform/local_notifications.dart';
import 'platform/reminders.dart';
import 'platform/kitchen_platform.dart';
import 'platform/export_share.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key,required this.store});
  final LocalAppStore store;
  @override State<ServicesScreen> createState()=>_ServicesScreenState();
}
class _ServicesScreenState extends State<ServicesScreen> {
  static final cloud=CloudSessionService();
  static const configuration=CloudConfiguration.fromEnvironment();
  final email=TextEditingController(),code=TextEditingController();
  final notifications=LocalNotificationGateway();
  final kitchen=KitchenPlatform();
  CloudSyncClient? sync;
  CloudSyncClient get syncClient=>sync??=CloudSyncClient(db:widget.store.db,session:cloud,baseUri:Uri.parse('${configuration.url}/functions/v1/app-api/v1'));
  bool busy=false;
  String message='Local baking works without connecting an account.';
  Future<void> run(Future<String> Function() action) async {
    if(busy)return;
    setState(()=>busy=true);
    try { final result=await action(); if(mounted)setState(()=>message=result); }
    catch(e){if(mounted)setState(()=>message='The action was not completed: $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override void dispose(){email.dispose();code.dispose();unawaited(kitchen.stopSpeaking());unawaited(kitchen.setKeepAwake(false));super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Connected services')),body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
    Text('You choose what connects',style:Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height:12),const Text('An account does not automatically upload your library. Reminders, calendars and cloud requests are separate choices.'),
    const SizedBox(height:20),Semantics(liveRegion:true,child:Text(message)),if(busy)const LinearProgressIndicator(),
    const SizedBox(height:24),Text('Reminders',style:Theme.of(context).textTheme.titleLarge),
    const Text('Enable native alerts for deadlines saved on this device. OS quiet modes and battery settings can delay alerts; a timer is not a safety interlock.'),
    FilledButton(onPressed:busy?null:()=>run(() async {
      final result=await notifications.requestPermission();
      if(!result.isAvailable)return result.message;
      await widget.store.setPreference('nativeReminders',true);
      final report=await reconcileReminders(widget.store,notifications);
      return 'Reminders enabled. ${report.scheduled} upcoming alerts scheduled. ${report.overdue.length} checks already due.';
    }),child:const Text('Allow and schedule reminders')),
    OutlinedButton(onPressed:busy?null:()=>run(()async{
      await widget.store.setPreference('nativeReminders',false);
      await ReminderCoordinator(notifications).reconcile([],now:DateTime.now().toUtc());
      return 'Crispy Crust alerts disabled. Your in-app deadlines remain.';
    }),child:const Text('Turn off native reminders')),
    SwitchListTile(title:const Text('Share the next task with widgets and watch'),subtitle:const Text('Publishes only the named current task. Watch pairing and platform capabilities are required.'),value:widget.store.preference('companionSnapshots',false)==true,onChanged:busy?null:(v)=>run(()async{await widget.store.setPreference('companionSnapshots',v);return v?'Task snapshots enabled for supported connected surfaces.':'Task snapshots disabled.';})),
    SwitchListTile(title:const Text('Use iOS Live Activity'),value:widget.store.preference('liveActivity',false)==true,onChanged:busy?null:(v)=>run(()async{await widget.store.setPreference('liveActivity',v);return 'Live Activity preference saved; platform availability still applies.';})),
    const SizedBox(height:24),Text('Calendar availability',style:Theme.of(context).textTheme.titleLarge),
    const Text('Import busy dates for the next seven days. Only start and end times are saved; event titles, attendees and notes are not copied.'),
    OutlinedButton(onPressed:busy?null:()=>run(()async{
      final start=DateTime.now(),result=await kitchen.readBusy(start,start.add(const Duration(days:7)));
      if(!result.isAvailable)return result.message;
      var count=0;
      for(final block in result.value!) {
        final id='calendar-${block.start.millisecondsSinceEpoch}-${block.end.millisecondsSinceEpoch}';
        await widget.store.save('availability',{'name':'Calendar busy time','source':'calendar','startAt':block.start.toUtc().toIso8601String(),'endAt':block.end.toUtc().toIso8601String()},id:id);count++;
      }
      return '$count busy intervals saved. Review them in Plan before accepting a schedule.';
    }),child:const Text('Choose calendar access and import busy times')),
    const SizedBox(height:24),Text('Cloud account',style:Theme.of(context).textTheme.titleLarge),
    const Text('Cloud services need the separate app backend configured in this build. Never enter a server secret in the app. Library sync remains off until explicitly selected.'),
    OutlinedButton(onPressed:busy?null:()=>run(()async{final result=await cloud.connect(const CloudConfiguration.fromEnvironment());return result.message;}),child:const Text('Connect configured app backend')),
    if(cloud.client!=null)...[
      TextField(controller:email,keyboardType:TextInputType.emailAddress,autofillHints:const [AutofillHints.email],decoration:const InputDecoration(labelText:'Email')),
      const SizedBox(height:8),OutlinedButton(onPressed:busy?null:()=>run(()async{await cloud.sendEmailCode(email.text);return 'If delivery is available, check your email for the sign-in code.';}),child:const Text('Send sign-in code')),
      TextField(controller:code,keyboardType:TextInputType.number,autofillHints:const [AutofillHints.oneTimeCode],decoration:const InputDecoration(labelText:'Email code')),
      FilledButton(onPressed:busy?null:()=>run(()async{await cloud.verifyEmailCode(email.text,code.text);return 'Account connected. Library backup remains off.';}),child:const Text('Verify code')),
      OutlinedButton(onPressed:busy?null:()=>run(()async{await cloud.signInWithApple();return 'Continue in the secure Apple sign-in window.';}),child:const Text('Sign in with Apple')),
      OutlinedButton(onPressed:busy?null:()=>run(()async{await cloud.signInWithGoogle();return 'Continue in the secure Google sign-in window.';}),child:const Text('Sign in with Google')),
      if(cloud.signedIn)...[
      FilledButton(onPressed:busy?null:()=>Navigator.of(context).push(MaterialPageRoute(builder:(context)=>CloudWorkspaceScreen(store:widget.store,client:cloud.client!,apiBase:Uri.parse('${configuration.url}/functions/v1/app-api/v1')))),child:const Text('Open shared kitchens, community and coach')),
      FilledButton(onPressed:busy?null:()async{
        final accepted=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Upload this local library?'),content:Text('This will upload your saved starters, recipes, bakes, journal, observations and other supported records to your personal cloud kitchen. ${widget.store.records('bake').length} bakes and ${widget.store.records('starter').length} starters are currently saved. Cloud storage is not end-to-end encrypted. Individual photos are not uploaded by this text sync. Continue?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Keep local')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Enable library sync'))]));
        if(accepted==true)await run(()async{final account=await syncClient.bootstrapAccount();await syncClient.enable(kitchenId:account['kitchen_id'] as String,userOptIn:true,uploadExistingRecords:true);final result=await syncClient.syncOnce();await widget.store.load();return 'Uploaded ${result.pushed}; received ${result.pulled}; ${result.conflicts} need review; ${result.skipped} unsupported records remain local.';});
      },child:const Text('Review and enable library sync')),
      OutlinedButton(onPressed:busy?null:()=>run(()async{final result=await syncClient.syncOnce();await widget.store.load();return 'Uploaded ${result.pushed}; received ${result.pulled}; ${result.conflicts} conflicts need review.';}),child:const Text('Sync now')),
      OutlinedButton(onPressed:busy?null:()=>run(()async{await syncClient.disable();return 'Sync disabled. Existing cloud copies remain until you delete them.';}),child:const Text('Disable library sync')),
      OutlinedButton(onPressed:busy?null:()=>run(()async{await syncClient.disable();await cloud.signOut();return 'Cloud account signed out. Your local library remains on this device.';}),child:const Text('Sign out of cloud services')),
      ],
    ],
    const SizedBox(height:24),Text('Read-aloud and kitchen screen',style:Theme.of(context).textTheme.titleLarge),
    OutlinedButton(onPressed:busy?null:()=>run(()async=> (await kitchen.speak('Check the dough. Timing is a guide; record what you observe.')).message),child:const Text('Try spoken guidance')),
    OutlinedButton(onPressed:busy?null:()=>run(()async=> (await kitchen.setKeepAwake(true)).message),child:const Text('Keep this screen awake')),
    OutlinedButton(onPressed:busy?null:()=>run(()async=> (await kitchen.setKeepAwake(false)).message),child:const Text('Allow the screen to sleep')),
    const SizedBox(height:24),Text('Back up your local data',style:Theme.of(context).textTheme.titleLarge),
    const Text('Uninstalling the app or losing the phone can lose a local-only library. Export your data and store it somewhere you control.'),
    FilledButton(onPressed:busy?null:()=>run(()async{final result=await ExportShareService().shareTextFile(fileName:'crispy-crust-backup.json',content:await widget.store.exportArchive(),mimeType:'application/json');return result.message;}),child:const Text('Export and share my archive')),
    const SizedBox(height:24),OutlinedButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>ProbeScreen(store:widget.store))),child:const Text('Connect a temperature probe')),
    const SizedBox(height:24),const Text('Probe and watch compatibility requires named physical-device tests. Manual observations and phone controls remain available. This build does not claim universal probe or watch support.'),
  ])));
}
Future<ReminderReconciliation> reconcileReminders(LocalAppStore store,LocalNotificationGateway gateway) {
  final intents=store.records('timer').where((t)=>t.text('state')=='running'&&t.date('dueAt')!=null).map((t)=>ReminderIntent(id:t.id,aggregateId:t.text('bakeId',t.id),revision:t.updatedAt.millisecondsSinceEpoch,title:t.text('bakeName','Crispy Crust'),action:t.text('name','Check the bake'),dueAt:t.date('dueAt')!.toUtc(),isCheck:true)).toList();
  return ReminderCoordinator(gateway).reconcile(intents,now:DateTime.now().toUtc());
}
