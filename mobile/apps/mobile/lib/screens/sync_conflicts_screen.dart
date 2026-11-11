import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/local_store.dart';
import '../data/sync_client.dart';
import '../platform/export_share.dart';

class SyncConflictsScreen extends StatefulWidget {
  const SyncConflictsScreen({super.key,required this.store,required this.sync});
  final LocalAppStore store;
  final CloudSyncClient sync;
  @override State<SyncConflictsScreen> createState()=>_SyncConflictsScreenState();
}
class _SyncConflictsScreenState extends State<SyncConflictsScreen> {
  bool busy=false;
  String status='No version is overwritten automatically. Review current server data and preserve the local evidence.';
  List<SyncConflictSummary> conflicts=[];
  SyncConflictReview? review;
  Future<void> run(Future<String> Function() action)async{
    if(busy)return;setState(()=>busy=true);
    try{final message=await action();if(mounted)setState(()=>status=message);}catch(e){if(mounted)setState(()=>status='Not resolved: $e. Existing records and unresolved evidence are retained.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)run(()async{conflicts=await widget.sync.listConflicts();return '${conflicts.length} record conflicts need review.';});});}
  Future<void> apply({required bool copy})async{
    final current=review;if(current==null||!current.canUseServer)return;
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(current.remoteOperation=='tombstone'?'Accept the server deletion?':'Use the reviewed server version?'),content:Text('The server is checked again before applying. New local or server edits invalidate this review. ${copy?'A private, non-runnable conflict archive keeps your local snapshot.':'The immutable local event history still retains the replaced state.'} Pending uploads for this record are explicitly discarded; no old physical event is erased or merged.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Keep reviewing')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Use server version'))]));
    if(yes!=true||!mounted)return;
    await run(()async{final resolved=await widget.sync.useReviewedServer(current,confirmed:true,keepLocalCopy:copy);await widget.store.load();conflicts=await widget.sync.listConflicts();review=null;return 'Reviewed server projection applied; pending operations were archived, not silently retried. ${resolved.privateCopyId==null?'Original local events remain exportable.':'Private conflict copy retained as ${resolved.privateCopyId}.'}';});
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Resolve sync conflicts')),body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
    Semantics(liveRegion:true,child:Text(status)),if(busy)const LinearProgressIndicator(),
    const SizedBox(height:12),const Text('Physical feeds, step completions, inventory, changed actual history and event-only remote updates require manual reconciliation. A tombstone is never resurrected. Unsafe local-wins overwrites are not offered.'),
    OutlinedButton(onPressed:busy?null:()=>run(()async{conflicts=await widget.sync.listConflicts();return '${conflicts.length} unresolved records loaded.';}),child:const Text('Refresh conflict list')),
    for(final item in conflicts)Card(child:ListTile(title:Text(item.aggregateId),subtitle:Text(item.codes.join(', ')),trailing:const Icon(Icons.compare_arrows),onTap:busy?null:()=>run(()async{review=await widget.sync.reviewConflict(item.aggregateId);return 'Current local/server versions loaded. Choosing a button is a separate explicit decision.';}))),
    if(review!=null)...[
      const SizedBox(height:16),Text('Record ${review!.aggregateId}',style:Theme.of(context).textTheme.titleLarge),Text('Local revision ${review!.localRevision??'missing'} · server revision ${review!.remoteRevision??'not found'} · ${review!.pendingCount} pending operations'),
      const SizedBox(height:12),const Text('Local snapshot'),SelectableText(const JsonEncoder.withIndent('  ').convert(review!.localFields)),
      const SizedBox(height:12),const Text('Current server change'),SelectableText(const JsonEncoder.withIndent('  ').convert(review!.remoteChange)),
      if(!review!.canUseServer)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(review!.reason,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      OutlinedButton(onPressed:busy?null:()=>run(()async{final result=await ExportShareService().shareTextFile(fileName:'crispy-crust-conflict-review.json',content:const JsonEncoder.withIndent('  ').convert(review!.toJson()),mimeType:'application/json');return result.message;}),child:const Text('Export both versions for review')),
      FilledButton(onPressed:busy||!review!.canUseServer?null:()=>apply(copy:true),child:const Text('Keep private local copy and use server')),
      OutlinedButton(onPressed:busy||!review!.canUseServer?null:()=>apply(copy:false),child:const Text('Use server; retain immutable event history')),
    ],
    const SizedBox(height:24),Text('Retained private conflict copies',style:Theme.of(context).textTheme.titleLarge),
    for(final copy in widget.store.records('conflict_copy'))ExpansionTile(title:Text('${copy.text('sourceKind')} · ${copy.text('retainedAt')}'),subtitle:const Text('Local archive only; never auto-uploaded or treated as a second physical jar/bake.'),children:[Padding(padding:const EdgeInsets.all(12),child:SelectableText(const JsonEncoder.withIndent('  ').convert(copy.fields)))]),
  ])));
}
