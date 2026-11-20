import 'package:baking_domain/baking_domain.dart';

import 'app_store.dart';
import 'planning_adapter.dart';

typedef RemainingPlan = ({
  Map<String, dynamic> recipe,
  List<ScheduleCandidate> candidates,
  List<Map<String, dynamic>> finished,
  List<ScheduleTask> previousTasks,
  List<Map<String, dynamic>> away,
  String? warning,
});

RemainingPlan reviewRemainingBake(AppStore store, AppRecord bake, DateTime anchor,
  (DateTime, DateTime) away) {
  final frozen = bake.fields['recipeSnapshot'];
  final previous = bake.fields['schedule'];
  if (frozen is! Map || previous is! Map) {
    throw StateError('This older bake has no schedule to adjust.');
  }
  final allSteps = (bake.fields['steps'] as List).whereType<Map>()
    .map((step) => Map<String, dynamic>.from(step)).toList();
  final index = bake.number('stepIndex').toInt().clamp(0, allSteps.length);
  if (index == allSteps.length) throw StateError('This bake has no remaining steps.');
  final finished = allSteps.take(index).toList();
  final remaining = allSteps.skip(index).toList();
  final remainingIds = remaining.map((step) => step['id']).toSet();
  final recipe = <String, dynamic>{
    ...Map<String, dynamic>.from(frozen),
    if (allSteps.any((step) => step['id'] == 'chill-dough')) 'coldBulkMinutes': true,
    'steps': [
      for (final step in remaining) {
        ...step,
        'after': (step['after'] as List? ?? []).where(remainingIds.contains).toList(),
      },
    ],
  };
  final block = AppRecord(id: 'this-bake-time-away', kind: 'availability', updatedAt: anchor,
    fields: {'startAt': away.$1.toUtc().toIso8601String(), 'endAt': away.$2.toUtc().toIso8601String()});
  final awayRecords = [
    for (final entry in (bake.fields['timeAway'] as List? ?? []).whereType<Map>())
      AppRecord(id: 'saved-bake-time-away', kind: 'availability', updatedAt: anchor,
        fields: Map<String, dynamic>.from(entry)),
    block,
  ];
  final options = prepareBakeSchedule(recipe, [...store.records('availability'), ...awayRecords],
    [...store.records('bake').where((r) => r.id != bake.id), ...store.records('production')],
    {'oven': (store.preference('ovenCapacity', 1) as num).toInt()}, startAt: anchor,
    shiftAnchor: bake.text('state') == 'planned');
  final previousTasks = ScheduleCandidate.fromJson(Map<String, dynamic>.from(previous)).tasks
    .where((task) => !remainingIds.contains(task.stepId)).toList();
  return (recipe: options.recipe, candidates: options.candidates, finished: finished,
    previousTasks: previousTasks, away: awayRecords.map((row) => row.fields).toList(),
    warning: options.warning);
}

Map<String, dynamic> updatedBakeSchedule(AppRecord bake, RemainingPlan plan, ScheduleCandidate candidate) {
  if (!plan.candidates.any((option) => canonicalJson(option.toJson()) == canonicalJson(candidate.toJson()))) {
    throw BakeScheduleChanged();
  }
  final remaining = (plan.recipe['steps'] as List).whereType<Map>().toList();
  final previousSteps = (bake.fields['steps'] as List).whereType<Map>().toList();
  final finishedIds = plan.finished.map((step) => step['id']).toSet();
  final currentBefore = previousSteps.skip(plan.finished.length).firstOrNull;
  return {
    ...bake.fields,
    'timeAway': plan.away,
    'scheduleUpdatedAt': DateTime.now().toUtc().toIso8601String(),
    if (currentBefore?['id'] != remaining.firstOrNull?['id']) 'nextStepDueAt': null,
    if (bake.text('state') == 'planned') 'startAt': candidate.startsAt.toIso8601String(),
    'steps': [
      ...plan.finished,
      for (final step in remaining)
        () {
          final task = candidate.task(step['id'] as String);
          final oldDeps = (previousSteps.where((previous) => previous['id'] == step['id'])
            .firstOrNull?['after'] as List? ?? []).where(finishedIds.contains);
          return {
            ...step, 'after': {...(step['after'] as List), ...oldDeps}.toList(),
            'plannedStart': task.start.toIso8601String(),
            'plannedEnd': task.end.toIso8601String(),
          };
        }(),
    ],
    'schedule': {...candidate.toJson(),
      'tasks': [...plan.previousTasks, ...candidate.tasks].map((task) => task.toJson()).toList()},
  };
}
