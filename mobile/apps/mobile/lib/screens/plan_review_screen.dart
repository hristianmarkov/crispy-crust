import 'package:baking_domain/baking_domain.dart';
import 'package:flutter/material.dart';

/// Read-only preview. The caller rechecks constraints before persisting acceptance.
class PlanReviewScreen extends StatelessWidget {
  const PlanReviewScreen({super.key, required this.recipe, required this.candidate,
    required this.scale});
  final Map<String,dynamic> recipe;
  final ScheduleCandidate candidate;
  final double scale;
  String stamp(DateTime value) {
    final local=value.toLocal();
    return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2,'0')}:${local.minute.toString().padLeft(2,'0')} ${local.timeZoneName}';
  }
  @override Widget build(BuildContext context) {
    final steps=(recipe['steps'] as List).whereType<Map>().toList();
    final ingredients=(recipe['ingredients'] as List? ?? []).whereType<Map>();
    return Scaffold(appBar:AppBar(title:const Text('Review this schedule')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
        Text('${recipe['title']??'Your bake'} · ${scale.toStringAsFixed(2)}×',style:Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height:12),
        const Text('These are planned times from an experimental method. Check the dough at each readiness gate. No actions have been recorded and no oven time is reserved yet.'),
        const SizedBox(height:16),
        Text('Begins ${stamp(candidate.startsAt)}',style:Theme.of(context).textTheme.titleMedium),
        Text('Declared method finishes: ${stamp(candidate.finishesAt)}'),
        const SizedBox(height:20),
        for(final task in candidate.tasks) Card(child:Padding(padding:const EdgeInsets.all(16),child:Builder(builder:(context){
          final step=steps.where((s)=>s['id']==task.stepId).firstOrNull;
          final kind=step?['kind'];
          return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Text('${step?['title']??task.stepId}',style:Theme.of(context).textTheme.titleMedium),
            Text('${stamp(task.start)} → ${stamp(task.end)}'),
            Text(kind=='handsOn'?'Hands-on throughout this step':kind=='check'?'Check at the end of this interval':'Waiting interval'),
            if(task.readinessGate)const Text('Readiness check required; the clock does not complete this step.'),
            if(step?['readinessCue']!=null)Text('${step!['readinessCue']}'),
            if(step?['resources'] is List && (step!['resources'] as List).isNotEmpty)Text('Required equipment: ${(step['resources'] as List).join(', ')}'),
          ]);
        }))),
        const SizedBox(height:16),Text('Ingredients for this batch',style:Theme.of(context).textTheme.titleLarge),
        for(final ingredient in ingredients)ListTile(contentPadding:EdgeInsets.zero,title:Text('${ingredient['name']??ingredient['id']??'Ingredient'}'),trailing:Text('${((ingredient['grams']??ingredient['massG']??0) as num)*scale} g')),
        ExpansionTile(title:const Text('Timing assumptions and exact instants'),children:[
          for(final assumption in candidate.assumptions)ListTile(title:Text(assumption)),
          for(final task in candidate.tasks)ListTile(title:Text(task.stepId),subtitle:Text('${task.start.toIso8601String()} → ${task.end.toIso8601String()}')),
        ]),
        const SizedBox(height:16),
        const Text('Accepting rechecks your availability and equipment. If anything has changed, review a new schedule. Starting from now allows two minutes for this review; taking longer can require another check.'),
        const SizedBox(height:16),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Accept this schedule')),
        OutlinedButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Change my inputs')),
      ])));
  }
}
