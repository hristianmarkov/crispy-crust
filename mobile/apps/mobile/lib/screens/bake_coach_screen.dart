import 'package:flutter/material.dart';
import '../platform/cloud_session.dart';
import 'account_sign_in.dart';
import 'cloud_workspace_screen.dart';
import 'kitchen_design.dart';
import 'subscription_screen.dart';
import 'app_policy_links.dart';

class BakeCoachScreen extends StatefulWidget {
  const BakeCoachScreen({super.key, required this.recipe, required this.step});
  final String recipe, step;

  @override
  State<BakeCoachScreen> createState() => _BakeCoachScreenState();
}

class _BakeCoachScreenState extends State<BakeCoachScreen> {
  final cloud = CloudSessionService.shared;
  final input = TextEditingController();
  final messages = <(bool, String, String?)>[];
  AuthenticatedCloudWorkspaceApi? api;
  String? pending, error;
  bool busy = false;
  Map<String, dynamic>? usage;

  @override
  void initState() {
    super.initState();
    if (cloud.signedIn) _loadUsage();
  }

  Future<void> _loadUsage() async {
    try {
      final result = await _api().request('/coach/usage');
      if (mounted && result is Map) setState(() => usage = Map<String, dynamic>.from(result));
    } catch (_) { /* Sending is always checked by the server, even while usage is unavailable. */ }
  }

  Future<void> _plans() async {
    const config = CloudConfiguration.fromEnvironment();
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => SubscriptionScreen(
      client: cloud.client, apiBase: config.isConfigured ? Uri.parse('${config.url}/functions/v1/app-api/v1') : null)));
    await _loadUsage();
  }

  @override
  void dispose() {
    input.dispose();
    api?.httpClient.close();
    super.dispose();
  }

  AuthenticatedCloudWorkspaceApi _api() {
    const config = CloudConfiguration.fromEnvironment();
    final client = cloud.client;
    if (client == null || !config.isConfigured) {
      throw const CloudWorkspaceException('UNAVAILABLE', 'The baking coach isn’t available in this build.');
    }
    return api ??= AuthenticatedCloudWorkspaceApi(client: client,
      apiBase: Uri.parse('${config.url}/functions/v1/app-api/v1'));
  }

  Future<void> _send() async {
    final question = input.text.trim();
    if (busy || question.isEmpty) return;
    final contextText = 'Recipe: ${widget.recipe}\nStep: ${widget.step}';
    final agree = await showDialog<bool>(context: context, builder: (sheet) => AlertDialog(
      title: const Text('Send to the baking coach?'),
      content: Text('Your question, recipe name and current step will be sent through Crispy Crust to OpenAI to generate guidance. The request and answer are saved with your cloud account.\n\n$contextText\n\n$question'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Send')),
      ],
    ));
    if (agree != true || !mounted || busy) return;
    await _run(() async {
      final api = _api();
      await api.request('/consents', method: 'POST',
        body: {'purpose': 'coach', 'version': '1', 'granted': true});
      final job = await api.request('/coach/requests', method: 'POST',
        body: {'question': '$contextText\n\n$question', 'consent_version': '1'});
      await _loadUsage();
      final id = job is Map ? job['job_id'] ?? job['id'] : null;
      if (id is! String) throw StateError('The coach didn’t return a request ID.');
      if (!mounted) return;
      setState(() {
        pending = id;
        messages.add((true, question, null));
        input.clear();
      });
      await _check();
    });
  }

  Future<void> _check() async {
    final id = pending;
    if (id == null) return;
    for (var attempt = 0; attempt < 8 && mounted; attempt++) {
      final result = await _api().request('/jobs/${Uri.encodeComponent(id)}');
      if (!mounted) return;
      if (result is! Map) throw StateError('The coach returned an unreadable response.');
      if (result['status'] == 'complete') {
        final answer = result['result'];
        final lines = <String>[];
        if (answer is Map) {
          for (final key in ['observations', 'possibilities', 'next_check', 'uncertainty']) {
            final detail = answer[key];
            if (detail is String && detail.trim().isNotEmpty) lines.add(detail);
            if (detail is List) lines.addAll(detail.whereType<String>());
          }
        }
        setState(() {
          pending = null;
          messages.add((false, lines.isEmpty ? 'The coach returned no guidance for this question.' : lines.join('\n\n'), id));
        });
        return;
      }
      if (['failed', 'canceled'].contains(result['status'])) {
        pending = null;
        throw const CloudWorkspaceException('COACH_FAILED', 'The coach couldn’t answer this question.');
      }
      if (attempt < 7) await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await action();
    } on CloudWorkspaceException catch (failure) {
      if (mounted) setState(() => error = failure.code == 'AI_PROVIDER_NOT_CONFIGURED'
        ? 'The baking coach hasn’t been enabled on the server yet.'
        : failure.code == 'COACH_MONTHLY_LIMIT'
          ? 'You’ve used your coach questions for this calendar month. Your allowance resets on the first of next month (UTC).'
          : failure.code == 'QUOTA_EXHAUSTED'
            ? 'You’ve reached today’s request limit. Please try again tomorrow.' : failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Couldn’t reach the baking coach. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _report(String jobId) async {
    final reason = await showDialog<String>(context: context, builder: (dialog) => SimpleDialog(
      title: const Text('Report this guidance'), children: [
        for (final reason in ['Unsafe advice', 'Offensive content', 'Incorrect or misleading advice'])
          SimpleDialogOption(onPressed: () => Navigator.pop(dialog, reason), child: Text(reason)),
        SimpleDialogOption(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
      ]));
    if (reason == null || !mounted) return;
    await _run(() async {
      await _api().request('/reports', method: 'POST', body: {
        'target_type': 'coach', 'target_id': jobId, 'reason': reason,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report sent. Thank you for flagging this guidance.')));
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = cloud.signedIn;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Baking coach')),
      body: KitchenPage(children: [
        Text(widget.step, style: Theme.of(context).textTheme.titleMedium),
        const AppPolicyLinks(),
        const SizedBox(height: 12),
        if (!signedIn) ...[
          const Text('Sign in to ask the baking coach.'),
          const SizedBox(height: 12),
          AccountSignIn(cloud: cloud, onSignedIn: () { setState(() {}); _loadUsage(); }),
        ] else ...[
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(usage == null ? '3 questions per calendar month, free'
                : '${usage!['remaining']} of ${usage!['limit']} questions left this month'),
              const SizedBox(height: 6),
              const Text('Each submitted question counts once. Follow-ups count too. Allowances reset on the first of each month (UTC), with up to 20 questions in 24 hours.'),
              if (usage?['is_pro'] != true)
                TextButton(onPressed: busy ? null : _plans, child: const Text('Get 60 questions with Pro')),
            ]))),
          for (final (mine, message, jobId) in messages) Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Card(color: mine ? colors.secondaryContainer : colors.surface,
              child: Padding(padding: const EdgeInsets.all(14), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText(message),
                  if (!mine && jobId != null) Align(alignment: Alignment.centerRight,
                    child: IconButton(tooltip: 'Report guidance', onPressed: busy ? null : () => _report(jobId),
                      icon: const Icon(Icons.flag_outlined))),
                ]))),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!)),
          if (pending != null)
            TextButton(onPressed: busy ? null : () => _run(_check), child: const Text('Check for reply'))
          else
            TextField(controller: input, enabled: !busy, maxLines: 3, maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Ask about this step')),
        ],
      ]),
      bottomNavigationBar: signedIn && pending == null ? KitchenActions(children: [
        FilledButton(onPressed: busy ? null : _send, child: const Text('Review question')),
      ]) : null,
    );
  }
}
