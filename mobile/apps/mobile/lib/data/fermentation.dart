import 'dart:math' as math;

/// Reference estimates for a lean country loaf followed by a cold final proof.
typedef RiseEstimate = ({int minimumMinutes, int maximumMinutes, int risePercent});

RiseEstimate? leanDoughRise(double temperatureC) {
  const rows = [
    (18.0, 720, 960, 100),
    (21.0, 480, 720, 75),
    (24.0, 300, 420, 50),
    (27.0, 210, 330, 30),
  ];
  if (!temperatureC.isFinite || temperatureC < rows.first.$1 || temperatureC > rows.last.$1) {
    return null;
  }
  final upper = rows.indexWhere((row) => row.$1 >= temperatureC).clamp(1, rows.length - 1);
  final a = rows[upper - 1], b = rows[upper];
  final position = (temperatureC - a.$1) / (b.$1 - a.$1);
  int interpolate(int start, int end) => (start + (end - start) * position).round();
  return (minimumMinutes: interpolate(a.$2, b.$2),
    maximumMinutes: interpolate(a.$3, b.$3), risePercent: interpolate(a.$4, b.$4));
}

// Working temperature adjustment for authored lean doughs only.
Map<String, dynamic> recipeAtDoughTemperature(Map<String, dynamic> recipe, double temperatureC) {
  final estimate = leanDoughRise(temperatureC);
  final steps = recipe['steps'];
  if (estimate == null || !_supportsLeanBulk(recipe) || steps is! List || temperatureC == 24) {
    return recipe;
  }
  var beforeBulk = 0.0;
  return {
    ...recipe,
    'doughTemperatureC': temperatureC,
    'steps': [
      for (final raw in steps.whereType<Map>())
        (() {
          final step = Map<String, dynamic>.from(raw);
          final minutes = (step['durationMinutes'] as num).toDouble();
          if (step['id'] != 'bulk') {
            beforeBulk += minutes;
            return step;
          }
          // The rise table targets different volume increases at different
          // temperatures before a cold proof. Its times cannot scale a recipe
          // that finishes proofing on the counter. Use a separate, explicitly
          // approximate twofold-per-10°C rate around the authored 24°C recipe.
          final relativeRate = math.pow(2, (24 - temperatureC) / 10);
          final duration = ((beforeBulk + minutes) * relativeRate - beforeBulk).round();
          return {...step, 'durationMinutes': duration.clamp(45, 900)};
        })(),
    ],
  };
}

bool _supportsLeanBulk(Map<String, dynamic> recipe) {
  const lean = {'R01', 'R02', 'R03', 'R04', 'R10', 'R14', 'R15',
    'R25', 'R26', 'R27', 'R28', 'R29', 'R30'};
  return lean.contains(recipe['id']) && {1, 2}.contains(recipe['version']);
}

/// Adds a short covered fridge hold during bulk, after the recipe's folds.
/// Cooling lag is modelled explicitly; these are planning estimates for lean dough.
Map<String, dynamic>? coldBulkOption(Map<String, dynamic> recipe, {required int coldMinutes,
  String stageId = 'bulk', double kitchenTemperatureC = 24}) {
  final isBulk = stageId == 'bulk';
  if (!_supportsLeanBulk(recipe) ||
      coldMinutes < (isBulk ? 60 : 30) || coldMinutes > (isBulk ? 480 : 120) ||
      kitchenTemperatureC < 18 || kitchenTemperatureC > 27) return null;
  final steps = (recipe['steps'] as List).whereType<Map>().toList();
  final index = steps.indexWhere((step) => step['id'] == stageId &&
    ['check', 'wait'].contains(step['kind']));
  if (index < 0 || (steps[index]['after'] as List).length > 1) return null;
  final bulk = steps[index];
  final warmMinutes = bulk['durationMinutes'] as num;
  final creditedMinutes = equivalentWarmMinutes(coldMinutes, kitchenTemperatureC);
  final wake = isBulk ? 30 : 15;
  // The centre warms gradually after refrigeration. Integrate that recovery
  // instead of crediting a cool counter rest as full room-temperature activity.
  final recovery = counterRecoveryMinutes(coldMinutes, kitchenTemperatureC,
    warmMinutes.toDouble() - creditedMinutes);
  final remaining = recovery - wake;
  if (remaining < (isBulk ? 30 : 5)) return null;
  Map<String, dynamic> stage(String id, String title, String instructions,
    String cue, int minutes, String kind, List<dynamic> after) => {
      'id': id, 'title': title, 'instructions': instructions, 'readinessCue': cue,
      'durationMinutes': minutes, 'kind': kind, 'after': after, 'resources': <String>[],
    };
  return {
    ...recipe,
    'coldBulkMinutes': coldMinutes,
    'steps': [
      ...steps.take(index),
      stage('chill-dough', 'Put dough in the fridge',
        'Cover the container, mark the dough level and move it to a 3–5°C fridge.',
        'Chill while the dough is still early in bulk fermentation.',
        3, 'handsOn', List<dynamic>.from(bulk['after'] as List)),
      stage('fridge-hold', 'Cold rest', 'Keep the dough covered in the fridge.',
        '', coldMinutes, 'wait', ['chill-dough']),
      stage('un-chill-dough', 'Take dough out of the fridge',
        'Return the covered dough to the counter and check how far it has risen.',
        'If it is already puffy with bubbles at the sides, check readiness before more warm time.',
        2, 'handsOn', ['fridge-hold']),
      stage('temper-dough', 'Let the dough warm up',
        'Rest covered for an initial $wake minutes. The centre may still be cool.',
        '', wake, 'wait', ['un-chill-dough']),
      {...bulk, 'after': ['temper-dough'],
        'durationMinutes': remaining,
        if (isBulk) 'instructions': 'Check volume, bubbles and strength after the fridge hold. Continue bulk at room temperature as needed and shape only when the dough is ready.'},
      ...steps.skip(index + 1),
    ],
  };
}

/// Warm-equivalent time at an assumed dough temperature. The eight-degree
/// rate rule is a baker's approximation. A 150-minute cooling constant keeps
/// the centre warmer than the fridge for several hours.
int equivalentWarmMinutes(int fridgeMinutes, double warmC) {
  var equivalent = 0.0;
  for (var elapsed = 0; elapsed < fridgeMinutes; elapsed += 5) {
    final sample = math.min(5, fridgeMinutes - elapsed);
    final core = 4 + (warmC - 4) * math.exp(-(elapsed + sample / 2) / 150);
    equivalent += sample * math.pow(2, (core - warmC) / 8);
  }
  return equivalent.round();
}

/// Uses the same approximate thermal constant for warming and cooling.
/// This is a planning model, not a measurement of a particular dough/container.
int counterRecoveryMinutes(int fridgeMinutes, double warmC, double requiredWarmMinutes) {
  if (requiredWarmMinutes <= 0) return 0;
  final initialCore = 4 + (warmC - 4) * math.exp(-fridgeMinutes / 150);
  var equivalent = 0.0;
  for (var elapsed = 0; elapsed < 1440; elapsed++) {
    final core = warmC - (warmC - initialCore) * math.exp(-(elapsed + 0.5) / 150);
    equivalent += math.pow(2, (core - warmC) / 8);
    if (equivalent >= requiredWarmMinutes) return elapsed + 1;
  }
  return 1440;
}
