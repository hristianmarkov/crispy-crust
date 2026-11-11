import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../data/local_store.dart';

/// Transport is injectable so cloud UX can be tested without credentials.
abstract interface class CloudWorkspaceApi {
  Future<dynamic> request(String path, {String method = 'GET', Map<String, dynamic>? body});
}
class CloudWorkspaceException implements Exception {
  const CloudWorkspaceException(this.code, this.message);
  final String code, message;
  @override String toString() => '$message ($code)';
}
class AuthenticatedCloudWorkspaceApi implements CloudWorkspaceApi {
  AuthenticatedCloudWorkspaceApi({required this.client, required this.apiBase, http.Client? httpClient}) : httpClient = httpClient ?? http.Client() {
    if (apiBase.scheme != 'https' || apiBase.host.isEmpty || apiBase.userInfo.isNotEmpty || apiBase.hasQuery || apiBase.hasFragment) {
      throw ArgumentError('A trusted HTTPS app API base is required.');
    }
  }
  final SupabaseClient client;
  final Uri apiBase;
  final http.Client httpClient;
  @override Future<dynamic> request(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null) throw const CloudWorkspaceException('AUTH_REQUIRED', 'Sign in before using cloud services.');
    if (!path.startsWith('/') || path.startsWith('//') || path.contains('://')) throw ArgumentError('Only app API paths are allowed.');
    final uri = Uri.parse('${apiBase.toString().replaceFirst(RegExp(r'/+$'), '')}$path');
    if (uri.origin != apiBase.origin) throw ArgumentError('API origin cannot change.');
    final req = http.Request(method, uri)..followRedirects = false;
    req.headers.addAll({'Authorization': 'Bearer $token', 'Content-Type': 'application/json', if (method != 'GET') 'Idempotency-Key': const Uuid().v4()});
    if (body != null) req.body = jsonEncode(body);
    final streamed = await httpClient.send(req).timeout(const Duration(seconds: 20));
    if ((streamed.contentLength ?? 0) > 1024 * 1024) throw const CloudWorkspaceException('RESPONSE_TOO_LARGE', 'The service response was too large.');
    final bytes = <int>[];
    await for (final chunk in streamed.stream.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) throw const CloudWorkspaceException('RESPONSE_TOO_LARGE', 'The service response was too large.');
    }
    final dynamic result;
    try {result = jsonDecode(utf8.decode(bytes));} catch (_) {throw const CloudWorkspaceException('INVALID_RESPONSE', 'The service returned an unreadable response.');}
    if (result is! Map) throw const CloudWorkspaceException('INVALID_RESPONSE', 'The service response was not an object.');
    if (streamed.statusCode < 200 || streamed.statusCode >= 300 || result['error'] != null) {
      final error = result['error'];
      throw CloudWorkspaceException(error is Map ? '${error['code'] ?? 'REQUEST_FAILED'}' : 'REQUEST_FAILED', error is Map ? '${error['message'] ?? 'The request was not completed.'}' : 'The request was not completed.');
    }
    return result['data'];
  }
}

class CloudWorkspaceScreen extends StatefulWidget {
  CloudWorkspaceScreen({super.key, required this.store, required SupabaseClient client, required Uri apiBase}) : api = AuthenticatedCloudWorkspaceApi(client: client, apiBase: apiBase);
  const CloudWorkspaceScreen.withApi({super.key, required this.store, required this.api});
  final LocalAppStore store;
  final CloudWorkspaceApi api;
  @override State<CloudWorkspaceScreen> createState() => _CloudWorkspaceScreenState();
}
class _CloudWorkspaceScreenState extends State<CloudWorkspaceScreen> {
  bool busy = false;
  int networkRequests = 0;
  String status = 'Only explicitly selected cloud actions send data. Your local library is not uploaded automatically.';
  List<Map<String, dynamic>> kitchens = [], cloudRecords = [], feed = [], members = [];
  String? kitchenId;
  final shares = <Map<String, dynamic>>[], jobs = <String>[];
  final selectedObservations = <String>{};
  int tab = 0;
  Future<void> run(Future<String> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {final result = await action(); if (mounted) setState(() => status = result);}
    catch (e) {if (mounted) setState(() => status = 'Not completed: $e');}
    finally {if (mounted) setState(() => busy = false);}
  }
  @override void initState() {super.initState(); unawaited(run(() async {await loadKitchens(); return kitchens.isEmpty ? 'No cloud kitchen found. Initialise your personal cloud kitchen to begin.' : 'Cloud kitchens loaded. Local library backup remains unchanged.';}));}
  @override void dispose() {if(widget.api is AuthenticatedCloudWorkspaceApi){(widget.api as AuthenticatedCloudWorkspaceApi).httpClient.close();}super.dispose();}
  Future<void> loadKitchens() async {
    kitchens = rows(await request('/kitchens'));
    if (!kitchens.any((k) => k['id'] == kitchenId)) kitchenId = kitchens.isEmpty ? null : '${kitchens.first['id']}';
  }
  Future<dynamic> request(String path, {String method='GET', Map<String,dynamic>? body}) async {
    if(mounted)setState(()=>networkRequests++);
    try{return await widget.api.request(path,method:method,body:body);}
    finally{if(mounted)setState(()=>networkRequests--);}
  }
  Future<dynamic> post(String path, Map<String, dynamic> body) => request(path, method: 'POST', body: body);
  static List<Map<String, dynamic>> rows(dynamic data) => (data is List ? data : const []).whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();
  String requireKitchen() {if (kitchenId == null) throw StateError('Choose or create a cloud kitchen first.'); return kitchenId!;}
  Future<Map<String, String>?> form(String title, Map<String, String> labels, {String? explanation}) async {
    final controllers = {for (final k in labels.keys) k: TextEditingController()};
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(context: context, builder: (c) => AlertDialog(title: Text(title), content: SizedBox(width: 460, child: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [if (explanation != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(explanation)), for (final entry in labels.entries) Padding(padding: const EdgeInsets.only(bottom: 14), child: TextFormField(controller: controllers[entry.key], decoration: InputDecoration(labelText: entry.value), maxLines: entry.key == 'body' || entry.key == 'question' || entry.key == 'text' ? 4 : 1, validator: (s) => s == null || s.trim().isEmpty ? 'Enter ${entry.value.toLowerCase()}' : null))])))), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), FilledButton(onPressed: () {if (formKey.currentState!.validate()) Navigator.pop(c, {for (final e in controllers.entries) e.key: e.value.text.trim()});}, child: const Text('Continue'))]));
    // Disposal after dialog transition avoids editable-text teardown races.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final c in controllers.values) {c.dispose();}
    return result;
  }
  Future<bool> confirm(String title, String body) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(title), content: SingleChildScrollView(child: SelectableText(body)), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm selected action'))])) ?? false;
  Widget action(String label, Future<String> Function() action) => Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(onPressed: busy ? null : () => run(action), child: Text(label)));
  Widget section(String title) => Padding(padding: const EdgeInsets.only(top: 24, bottom: 12), child: Text(title, style: Theme.of(context).textTheme.titleLarge));
  Widget panel(List<Widget> children) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)));
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Cloud kitchen')), body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
    Semantics(liveRegion: true, child: Text(status)), if (networkRequests > 0) const LinearProgressIndicator(), const SizedBox(height: 16),
    Wrap(spacing: 8, runSpacing: 8, children: [for(final entry in const {0:'Kitchen',1:'Help & jobs',2:'Community'}.entries) ChoiceChip(label:Text(entry.value),selected:tab==entry.key,onSelected:busy?null:(_)=>setState(()=>tab=entry.key))]),
    if (tab == 0) ...kitchenViews(), if (tab == 1) ...helpViews(), if (tab == 2) ...communityViews(),
  ])));
  List<Widget> kitchenViews() => [
    section('Choose a cloud workspace'),
    if (kitchens.isNotEmpty) DropdownButtonFormField<String>(initialValue: kitchenId, isExpanded: true, decoration: const InputDecoration(labelText: 'Cloud kitchen'), items: kitchens.map((k) => DropdownMenuItem(value: '${k['id']}', child: Text('${k['name']} · ${k['kind']}', overflow: TextOverflow.ellipsis))).toList(), onChanged: busy ? null : (v) => setState(() {kitchenId = v; cloudRecords = []; members = [];})),
    action('Refresh cloud kitchens', () async {await loadKitchens(); return '${kitchens.length} accessible cloud kitchens loaded.';}),
    action('Initialise my personal cloud kitchen', () async {await post('/account/bootstrap', {}); await loadKitchens(); return 'Personal cloud workspace ready. No local records were uploaded.';}),
    action('Create a household', () async {final f = await form('Create household', {'name': 'Household name'}); if (f == null) return 'Household creation cancelled.'; await post('/kitchens', {'kind': 'household', 'name': f['name']}); await loadKitchens(); return 'Household created. Invite someone explicitly to grant access.';}),
    section('Invitations and access'),
    action('Read current kitchen members', () async {members=rows(await request('/kitchens/${requireKitchen()}/members'));return '${members.length} active members loaded from this kitchen.';}),
    for(final member in members)panel([Text('${member['display_name']??'Member'} · ${member['role']}'),SelectableText('${member['user_id']}'),action('Change this member’s role',()async{final f=await form('Change member permissions',{'role':'Role: viewer, editor or admin'});if(f==null)return 'Role unchanged.';if(!['viewer','editor','admin'].contains(f['role']))throw const FormatException('Choose viewer, editor or admin.');if(!await confirm('Change this member’s role?', '${member['display_name']??member['user_id']} → ${f['role']}'))return 'Role unchanged.';await post('/members/role',{'kitchen_id':requireKitchen(),'user_id':member['user_id'],'role':f['role']});members=rows(await request('/kitchens/${requireKitchen()}/members'));return 'Permissions changed by the server.';}),action('Remove this member',()async{if(!await confirm('Remove this member?', 'Revoke future access for ${member['display_name']??member['user_id']}? Already downloaded copies cannot be remotely erased.'))return 'Member access unchanged.';await post('/members/revoke',{'kitchen_id':requireKitchen(),'user_id':member['user_id']});members=rows(await request('/kitchens/${requireKitchen()}/members'));return 'Membership revoked by the server.';})]),
    action('Create viewer or editor invitation', () async {final id = requireKitchen(); final f = await form('Invite a household member', {'role': 'Role: viewer or editor'}, explanation: 'A viewer cannot edit. An editor can change this kitchen. Share the token only with the intended person.'); if (f == null) return 'Invitation cancelled.'; if (!['viewer','editor'].contains(f['role'])) throw const FormatException('Choose viewer or editor.'); final result = await post('/kitchens/$id/invite', {'role': f['role'], 'expires_in_seconds': 86400}); if (mounted) await showResult('Invitation — sensitive access token', result); return 'Invitation created with a one-day expiry. It is not sent automatically.';}),
    action('Redeem an invitation', () async {final f = await form('Join a kitchen', {'token': 'Invitation token'}, explanation: 'Accept only an invitation you recognise. Joining gives the permissions specified by its owner.'); if (f == null) return 'Invitation not accepted.'; final result = await post('/invites/redeem', {'token': f['token']}); await loadKitchens(); return 'Invitation accepted: ${jsonEncode(result)}';}),
    action('Revoke a member’s access', () async {final id = requireKitchen(); final f = await form('Revoke membership', {'user_id': 'Member user ID'}); if (f == null) return 'No membership changed.'; if (!await confirm('Remove access?', 'This member will lose future access to the selected kitchen. Already downloaded copies cannot be remotely erased.')) return 'No membership changed.'; await post('/members/revoke', {'kitchen_id': id, 'user_id': f['user_id']}); return 'Membership revoked by the server.';}),
    action('Change a member role', () async {final f=await form('Change member role',{'user_id':'Member user ID','role':'Role: viewer, editor or admin'});if(f==null)return 'Role unchanged.';if(!['viewer','editor','admin'].contains(f['role']))throw const FormatException('Choose viewer, editor or admin.');if(!await confirm('Change this member’s permissions?',jsonEncode(f)))return 'Role unchanged.';await post('/members/role',{'kitchen_id':requireKitchen(),...f});return 'Role changed by the server.';}),
    action('Transfer kitchen ownership', () async {final f=await form('Transfer ownership',{'user_id':'Existing member user ID'},explanation:'Requires a fresh sign-in. The recipient must already be an active member. You will give up ownership of this kitchen.');if(f==null)return 'Ownership unchanged.';if(!await confirm('Transfer ownership?', 'This changes who can delete or transfer the kitchen. Review the recipient ID carefully.'))return 'Ownership unchanged.';await post('/kitchens/transfer',{'kitchen_id':requireKitchen(),...f});await loadKitchens();return 'Kitchen ownership transferred by the server.';}),
    section('Cloud records and selected sharing'),
    action('Read selected kitchen records', () async {final data = await request('/sync/pull?kitchen_id=${Uri.encodeQueryComponent(requireKitchen())}&cursor=0&limit=500'); cloudRecords=projectCloudRecordChanges(data);return '${cloudRecords.length} cloud records loaded. This does not overwrite local records.';}),
    const Text('Share a cloud record already uploaded through explicit sync. The share preview includes only selected top-level fields. Nested data must also be inspected before confirmation.'),
    for (final r in cloudRecords) panel([Text('${r['kind'] ?? r['entity_type'] ?? 'Record'} · ${r['entity_id'] ?? r['id'] ?? r['aggregate_id']}'), action('Preview selected fields to share', () async {final data = r['data'] is Map ? Map<String,dynamic>.from(r['data'] as Map) : r['payload'] is Map ? Map<String,dynamic>.from((r['payload'] as Map)['data'] is Map ? (r['payload'] as Map)['data'] as Map : <String,dynamic>{}) : <String,dynamic>{}; final selected = await selectFields(data); if (selected == null || selected.isEmpty) return 'No share created.'; if (!await confirm('Publish only these selected fields?', jsonEncode({for(final k in selected) k:data[k]}))) return 'No share created.'; final response = await post('/shares', {'kitchen_id': requireKitchen(), 'source_id': r['entity_id'] ?? r['id'] ?? r['aggregate_id'], 'selected_fields': selected, 'expected_source_revision': r['revision']}); if(response is Map)shares.add(Map<String,dynamic>.from(response)); if(mounted)await showResult('Created selected-field share',response);return 'Share created. Revoke it below to stop future redemption.';})]),
    for (final s in shares) panel([SelectableText('Share ${s['share_id']}\nToken: ${s['token']}'), action('Revoke this share', () async {await request('/shares/${s['share_id']}',method:'DELETE');shares.remove(s);return 'Share revoked. Previously saved recipient copies cannot be recalled.';})]),
    action('Read an attributed shared card', () async {final f=await form('Open shared card',{'token':'Share token'});if(f==null)return 'No shared card opened.';final card=await request('/shares/${Uri.encodeComponent(f['token']!)}');if(mounted)await showResult('Shared card — inspect before copying',card);return 'Shared card loaded; no private source record was granted.';}),
    section('Account deletion'),
    action('Request cloud account deletion', () async {if(!await confirm('Initiate account deletion?', 'This requires a fresh sign-in within five minutes. Transfer owned shared kitchens first. Account deletion and subscription cancellation are separate. Processing is not complete merely because a deletion job is queued.'))return 'Account deletion not requested.';final result=await post('/account/delete',{'acknowledge_subscription_separation':true});if(mounted)await showResult('Deletion request status',result);return 'Deletion requested. Follow its job/status; no completed-erasure claim is made.';}),
  ];
  Future<List<String>?> selectFields(Map<String,dynamic> data) async {
    final selected=<String>{};
    return showDialog<List<String>>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setLocal)=>AlertDialog(title:const Text('Choose share fields'),content:SizedBox(width:460,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[for(final key in data.keys)CheckboxListTile(title:Text(key),subtitle:Text('${data[key]}',maxLines:2,overflow:TextOverflow.ellipsis),value:selected.contains(key),onChanged:(v)=>setLocal((){if(v==true){selected.add(key);}else{selected.remove(key);}}))]))),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:selected.isEmpty?null:()=>Navigator.pop(c,selected.toList()),child:const Text('Review selection'))])));
  }
  Future<void> showResult(String title,dynamic data) async {final text=const JsonEncoder.withIndent('  ').convert(data);await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text(title),content:SizedBox(width:480,child:SingleChildScrollView(child:SelectableText(text))),actions:[TextButton(onPressed:()async{await Clipboard.setData(ClipboardData(text:text));},child:const Text('Copy selected result')),TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Close'))]));}
  List<Widget> helpViews() => [
    section('Coach: choose what leaves your phone'),
    const Text('Only selected observation measurements and your question are sent. Unselected notes, photos, recipes and calendar blocks stay local. The coach cannot change a plan.'),
    for(final o in widget.store.records('observation'))CheckboxListTile(contentPadding:EdgeInsets.zero,title:Text('Observation ${o.updatedAt.toLocal()}'),subtitle:Text('Temperature ${o.text('temperature','unknown')} °C · rise ${o.text('rise','unknown')}%'),value:selectedObservations.contains(o.id),onChanged:busy?null:(v)=>setState((){if(v==true){selectedObservations.add(o.id);}else{selectedObservations.remove(o.id);}})),
    action('Preview and request coach help',()async{final f=await form('Ask about this observation',{'question':'Your question'});if(f==null)return 'Question not sent.';final obs=widget.store.records('observation').where((o)=>selectedObservations.contains(o.id)).map((o)=>{'id':o.id,'temperature_c':o.fields['temperature'],'rise_percent':o.fields['rise'],'occurred_at':o.fields['occurredAt']}).toList();final payload={'question':f['question'],'consent_version':'1','context':{'observations':obs}};if(!await confirm('Send only this context to the coach?',jsonEncode(payload)))return 'No context uploaded.';await post('/consents',{'purpose':'coach','version':'1','granted':true});final result=await post('/coach/requests',payload);trackJob(result);return 'Coach request queued if accepted. Check the job result below; no guidance has been invented.';}),
    section('Import a private draft'),
    const Text('Imports produce editable unvalidated drafts. A URL must be on the server operator’s approved host list. Text is never automatically published.'),
    action('Import pasted text',()async{final f=await form('Private text import',{'text':'Recipe text'});if(f==null)return 'Import cancelled.';if(!await confirm('Send this text for extraction?',f['text']!))return 'No text uploaded.';await post('/consents',{'purpose':'import','version':'1','granted':true});final result=await post('/imports',{'source':{'kind':'text','text':f['text']},'consent_version':'1'});trackJob(result);return 'Import job queued; review its actual result before saving a formula.';}),
    action('Import an approved HTTPS recipe URL',()async{final f=await form('URL import',{'url':'HTTPS recipe URL'});if(f==null)return 'Import cancelled.';if(!await confirm('Ask the server to fetch this public recipe?',f['url']!))return 'No URL submitted.';await post('/consents',{'purpose':'import','version':'1','granted':true});final result=await post('/imports',{'source':{'kind':'url','url':f['url']},'consent_version':'1'});trackJob(result);return 'URL import queued; unsupported hosts and extraction errors are reported by the job.';}),
    section('Your request jobs'),
    const Text('Refresh is explicit and bounded; the app does not poll indefinitely. Queued is not complete. Copy a job ID if you need support.'),
    for(final id in jobs)panel([SelectableText('Job $id'),action('Refresh this job once',()async{final result=await request('/jobs/${Uri.encodeComponent(id)}');if(mounted)await showResult('Actual job status and result',result);return 'Job refreshed. Only a server result marked complete is complete.';})]),
    action('Look up a request job',()async{final f=await form('Job status',{'id':'Job ID'});if(f==null)return 'No job requested.';final result=await request('/jobs/${Uri.encodeComponent(f['id']!)}');if(mounted)await showResult('Actual job status',result);if(!jobs.contains(f['id']))jobs.add(f['id']!);return 'Job status loaded.';}),
    action('Revoke future coach processing consent',()async{await post('/consents',{'purpose':'coach','version':'1','granted':false});return 'Future coach consent revoked. Previously processed requests require their separate retention/deletion policy.';}),
  ];
  void trackJob(dynamic result){if(result is Map){final id=result['job_id']??result['id'];if(id!=null&&!jobs.contains('$id'))jobs.add('$id');}}
  List<Widget> communityViews()=>[
    section('Opt-in community'),
    const Text('Nothing from your journal is automatically posted. A selected share must be created first; public posts and comments remain pending until moderation.'),
    action('Load public community feed',()async{feed=rows(await request('/community/feed'));return '${feed.length} public posts loaded.';}),
    action('Submit a selected share for moderation',()async{final f=await form('Publish a selected share',{'share_id':'Previously created share ID','title':'Public post title'},explanation:'Use a share whose preview you have reviewed. Submission remains pending moderation.');if(f==null)return 'Nothing submitted.';if(!await confirm('Submit this selected card for public review?',jsonEncode(f)))return 'Nothing submitted.';final result=await post('/community/posts',f);if(mounted)await showResult('Publication submission status',result);return 'Submission recorded. A pending post is not public yet.';}),
    for(final p in feed)panel([Text('${p['title']??'Shared bake'}',style:Theme.of(context).textTheme.titleLarge),SelectableText('Creator ${p['author_id']??p['creator_id']??'Not provided'}'),if(p['snapshot']!=null)SelectableText(jsonEncode(p['snapshot'])),action('Read comments',()async{final result=await request('/community/posts/${p['id']??p['post_id']}/comments');if(mounted)await showResult('Public comments',result);return 'Comments loaded.';}),action('Add comment for moderation',()async{final f=await form('Comment on this post',{'body':'Comment'});if(f==null)return 'No comment sent.';final result=await post('/community/posts/${p['id']??p['post_id']}/comments',f);if(mounted)await showResult('Comment submission',result);return 'Comment submitted for moderation.';}),action('Report this post',()=>report('post','${p['id']??p['post_id']}')),if(p['author_id']!=null||p['creator_id']!=null)action('Block this creator',()async{final creator=p['author_id']??p['creator_id'];if(!await confirm('Block this creator?', 'Restrict supported community and sharing interactions for $creator. Previously downloaded copies remain.'))return 'No creator blocked.';await post('/blocks',{'user_id':creator});feed.removeWhere((item)=>(item['author_id']??item['creator_id'])==creator);return 'Creator blocked by the service.';})]),
    action('Follow a creator',()async{final f=await form('Follow creator updates',{'creator_id':'Creator user ID'});if(f==null)return 'No follow changed.';await post('/community/follows',{'creator_id':f['creator_id'],'following':true});return 'Creator followed. Updates cannot change an active recipe snapshot.';}),
    action('Unfollow a creator',()async{final f=await form('Stop creator updates',{'creator_id':'Creator user ID'});if(f==null)return 'No follow changed.';await post('/community/follows',{'creator_id':f['creator_id'],'following':false});return 'Creator unfollowed.';}),
    action('Report an AI answer or other content',()async{final f=await form('Choose report target',{'type':'Target type: coach, post or comment','id':'Target ID'});if(f==null)return 'No report submitted.';return report(f['type']!,f['id']!);}),
    action('Block a user',()async{final f=await form('Block user',{'user_id':'User ID'});if(f==null)return 'No user blocked.';if(!await confirm('Block this user?', 'The server will restrict supported sharing/community interactions. This does not delete already downloaded copies.'))return 'No user blocked.';await post('/blocks',f);return 'User blocked by the service.';}),
  ];
  Future<String> report(String type,String id)async{final f=await form('Report selected content',{'reason':'Reason','details':'Details (describe only what is needed)'},explanation:'Only the selected target and the text below are sent. No unrelated journal notes or photos are attached.');if(f==null)return 'Report cancelled.';final payload={'target_type':type,'target_id':id,...f};if(!await confirm('Send this report?',jsonEncode(payload)))return 'Report cancelled.';await post('/reports',payload);return 'Report submitted to the restricted review queue.';}
}

/// Matches cc_sync_pull's public `id` alias. Never collapse distinct aggregates
/// into a synthetic null key; reject incomplete pages before sharing previews.
List<Map<String,dynamic>> projectCloudRecordChanges(dynamic data){
  if(data is! Map||data['changes'] is! List)throw const FormatException('Invalid sync response.');
  if(data['has_more']==true)throw StateError('This workspace needs paginated sync before selected-share previews are safe. No partial share will be created.');
  final latest=<String,Map<String,dynamic>>{};
  for(final raw in data['changes'] as List){
    if(raw is! Map)throw const FormatException('Invalid sync change.');
    final change=Map<String,dynamic>.from(raw),id=raw['id']??raw['entity_id'];
    if(id is! String||id.isEmpty)throw const FormatException('A sync change is missing its record identity.');
    final op=change['operation'];
    if(op=='upsert'){latest[id]=change;}
    else if(op=='tombstone'){latest.remove(id);}
    else if(op=='event'||op=='schedule'){if(latest.containsKey(id))latest[id]={...latest[id]!, 'revision':change['revision']};}
    else{throw const FormatException('Unknown sync change operation.');}
  }
  return latest.values.toList();
}
