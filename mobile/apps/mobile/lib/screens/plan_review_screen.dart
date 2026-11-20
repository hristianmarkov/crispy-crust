import 'package:baking_domain/baking_domain.dart';
import 'package:flutter/material.dart';
import 'kitchen_design.dart';

String _stamp(DateTime value) {
  final local = value.toLocal();
  return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} ${local.timeZoneName}';
}

Future<ScheduleCandidate?> reviewScheduleOptions(
  BuildContext context,
  Map<String, dynamic> recipe,
  List<ScheduleCandidate> candidates, {
  required double scale,
  DateTime? immediateAnchor,
  bool replan = false,
  String? warning,
}) async {
  if (candidates.isEmpty) return null;
  final candidate = candidates.length == 1 ? candidates.first
      : await showDialog<ScheduleCandidate>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Compare schedules'),
            children: [
              for (final (index, option) in candidates.indexed)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, option),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Schedule ${index + 1}', style: Theme.of(context).textTheme.titleMedium),
                      Text('Mix from ${_stamp(option.startsAt)}'),
                      Text('Finish ${_stamp(option.finishesAt)}'),
                      for (final task in option.tasks.where((task) => task.readinessGate))
                        Text('Check ${_stamp(task.end)}'),
                    ],
                  ),
                ),
            ],
          ),
        );
  if (candidate == null || !context.mounted) return null;
  final accepted = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => PlanReviewScreen(recipe: recipe, candidate: candidate, scale: scale,
      replan: replan, warning: warning,
      immediate: immediateAnchor != null && candidate.startsAt.isAtSameMomentAs(immediateAnchor)),
  ));
  return accepted == true ? candidate : null;
}

/// Read-only preview. The caller rechecks constraints before persisting acceptance.
class PlanReviewScreen extends StatelessWidget {
  const PlanReviewScreen({super.key, required this.recipe, required this.candidate,
    required this.scale, this.immediate = false, this.replan = false, this.warning});
  final Map<String, dynamic> recipe;
  final ScheduleCandidate candidate;
  final double scale;
  final bool immediate, replan;
  final String? warning;
  @override
  Widget build(BuildContext context) {
    final steps = (recipe['steps'] as List).whereType<Map>().toList();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Review this schedule')),
      bottomNavigationBar: KitchenActions(children: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Change my inputs')),
        FilledButton(onPressed: () => Navigator.pop(context, true),
          child: Text(replan ? 'Apply schedule' : immediate ? 'Start guided bake' : 'Save bake')),
      ]),
      body: KitchenPage(children: [
        Text('${recipe['title'] ?? 'Your bake'} · ${scale.toStringAsFixed(2)}× batch',
          style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.secondaryContainer,
          child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(replan ? 'Resume ${_stamp(candidate.startsAt)}' : immediate ? 'Start now' : 'Mix ${_stamp(candidate.startsAt)}',
                style: theme.textTheme.titleMedium),
              Text('Estimated finish ${_stamp(candidate.finishesAt)}'),
            ],
          )),
        ),
        const SizedBox(height: 10),
        if (warning != null)
          Card(margin: const EdgeInsets.symmetric(vertical: 8), child: ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: const Text('Schedule adjustment'),
            subtitle: Text(warning!),
          )),
        const SizedBox(height: 12),
        for (final (index, task) in candidate.tasks.indexed)
          Builder(builder: (context) {
            final step = steps.where((s) => s['id'] == task.stepId).firstOrNull;
            final passive = const ['check', 'wait'].contains(step?['kind']);
            return KitchenTimelineEntry(at: passive ? task.end : task.start,
              title: '${step?['title'] ?? task.stepId}',
              detail: task.readinessGate ? 'Readiness check' : null,
              last: index == candidate.tasks.length - 1,
              onTap: () => showModalBottomSheet<void>(context: context, showDragHandle: true,
                isScrollControlled: true, builder: (sheet) => SafeArea(child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('${step?['title'] ?? task.stepId}', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('${_stamp(task.start)} – ${_stamp(task.end)}'),
                    if (step?['instructions'] case final String instructions)
                      Padding(padding: const EdgeInsets.only(top: 12), child: Text(instructions)),
                    if (step?['readinessCue'] case final String cue when cue.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 12), child: Text(cue)),
                  ]),
                )),
              ));
          }),
      ]),
    );
  }
}
