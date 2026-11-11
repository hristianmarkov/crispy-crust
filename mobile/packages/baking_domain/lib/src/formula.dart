import 'common.dart';

final class Preferment {
 final String id;
 final Rational flourFraction,hydration;
 Preferment({required this.id,required this.flourFraction,required this.hydration}) {
  if(id.isEmpty||flourFraction.isNegative||hydration.isNegative)throw const DomainException('FORMULA_INVALID_BASIS','Preferments need identity and nonnegative flour/hydration.');
 }
 Map<String,dynamic> toJson()=>{'id':id,'flourFraction':flourFraction.toJson(),'hydration':hydration.toJson()};
 factory Preferment.fromJson(Map<String,dynamic> j)=>Preferment(id:j['id'],flourFraction:Rational.fromJson(j['flourFraction']),hydration:Rational.fromJson(j['hydration']));
}

final class FormulaDefinition {
  final Rational totalFlour;
  final Rational hydration;
  final Rational saltFraction;
  final Rational prefermentedFlourFraction;
  final Rational starterHydration;
  /// When nonempty these explicitly replace the single starter definition.
  final List<Preferment> preferments;
  /// Physical extra ingredients. Their mass is counted exactly once.
  final Map<String, Rational> inclusions;
  /// Optional measured water supplied by inclusions; interpretation is explicit.
  final Rational inclusionWater;
  FormulaDefinition({required this.totalFlour, required this.hydration,
    required this.saltFraction, required this.prefermentedFlourFraction,
    required this.starterHydration, Map<String, Rational> inclusions = const {},
    Rational? inclusionWater, List<Preferment> preferments = const []}) : preferments=List.unmodifiable(preferments), inclusions = Map.unmodifiable(inclusions),
    inclusionWater = inclusionWater ?? Rational.zero;
  factory FormulaDefinition.fromNumbers({required num totalFlour, required num hydration,
    num saltFraction = .02, num prefermentedFlourFraction = .10,
    num starterHydration = 1, Map<String, num> inclusions = const {}, num inclusionWater = 0, List<Preferment> preferments=const []}) => FormulaDefinition(
      totalFlour: Rational.fromNum(totalFlour), hydration: Rational.fromNum(hydration),
      saltFraction: Rational.fromNum(saltFraction), prefermentedFlourFraction: Rational.fromNum(prefermentedFlourFraction),
      starterHydration: Rational.fromNum(starterHydration),
      inclusions: inclusions.map((key, value) => MapEntry(key, Rational.fromNum(value))), inclusionWater: Rational.fromNum(inclusionWater),preferments:preferments);
  factory FormulaDefinition.fromJson(Map<String, dynamic> json) => FormulaDefinition(
    preferments:(json['preferments'] as List? ?? []).map((p)=>Preferment.fromJson(p)).toList(), totalFlour: Rational.fromJson(json['totalFlour']), hydration: Rational.fromJson(json['hydration']),
    saltFraction: Rational.fromJson(json['saltFraction']), prefermentedFlourFraction: Rational.fromJson(json['prefermentedFlourFraction']),
    starterHydration: Rational.fromJson(json['starterHydration']), inclusionWater: Rational.fromJson(json['inclusionWater']),
    inclusions: (json['inclusions'] as Map<String, dynamic>).map((key, value) => MapEntry(key, Rational.fromJson(value))));
  FormulaDefinition scale(Rational factor) => FormulaDefinition(totalFlour: totalFlour * factor,
    hydration: hydration, saltFraction: saltFraction, prefermentedFlourFraction: prefermentedFlourFraction,
    starterHydration: starterHydration, preferments:preferments, inclusions: inclusions.map((k,v) => MapEntry(k,v*factor)), inclusionWater: inclusionWater * factor);
  Map<String, dynamic> toJson() => {'preferments':preferments.map((p)=>p.toJson()).toList(),'totalFlour': totalFlour.toJson(), 'hydration': hydration.toJson(),
    'saltFraction': saltFraction.toJson(), 'prefermentedFlourFraction': prefermentedFlourFraction.toJson(),
    'starterHydration': starterHydration.toJson(), 'inclusionWater': inclusionWater.toJson(),
    'inclusions': inclusions.map((k,v) => MapEntry(k,v.toJson()))};
}

final class FormulaResult {
  final FormulaDefinition definition;
  final Map<String, Rational> ingredients;
  final Rational totalDough;
  final Rational starterFlour;
  final Rational starterWater;
  FormulaResult(this.definition, Map<String, Rational> ingredients, this.totalDough, this.starterFlour, this.starterWater) : ingredients = Map.unmodifiable(ingredients);
  Rational get addedFlour => ingredients['flour']!;
  Rational get addedWater => ingredients['water']!;
  Rational get starterMass => starterFlour+starterWater;
  Rational get salt => ingredients['salt']!;
  /// Independent rounding followed by a visible residual adjustment to water
  /// (or flour if needed) conserves the rounded displayed dough target.
  WeighOut roundForScale({num incrementGrams = 1}) {
    final increment = Rational.fromNum(incrementGrams);
    if (increment <= Rational.zero) throw ArgumentError('Increment must be positive');
    final rows = ingredients.map((k,v) => MapEntry(k,v.roundTo(increment)));
    final target = totalDough.roundTo(increment);
    final sum = rows.values.fold(Rational.zero, (a,b) => a+b);
    final residual = target-sum;
    final correction = rows['water']! + residual >= Rational.zero ? 'water' : 'flour';
    if (rows[correction]!+residual < Rational.zero) throw const DomainException('ROUNDING_UNSUPPORTED', 'Use a more precise scale increment.');
    rows[correction] = rows[correction]!+residual;
    return WeighOut(Map.unmodifiable(rows), target, residual, correction);
  }
  Map<String, dynamic> toJson() => {'definition': definition.toJson(), 'ingredients': ingredients.map((k,v)=>MapEntry(k,v.toJson())),
    'totalDough': totalDough.toJson(), 'starterFlour': starterFlour.toJson(), 'starterWater': starterWater.toJson()};
}
final class WeighOut {
  final Map<String,Rational> ingredients;
  final Rational totalDough, roundingResidual;
  final String residualIngredient;
  const WeighOut(this.ingredients,this.totalDough,this.roundingResidual,this.residualIngredient);
}

final class FormulaEngine {
  const FormulaEngine();
  FormulaResult calculate(FormulaDefinition formula, {Rational? targetDoughWeight, int? loafCount}) {
    if (formula.totalFlour <= Rational.zero || [formula.hydration,formula.saltFraction,formula.prefermentedFlourFraction,formula.starterHydration,formula.inclusionWater,...formula.inclusions.values].any((x)=>x.isNegative)) {
      throw const DomainException('FORMULA_INVALID_QUANTITY','Flour must be positive and all other quantities nonnegative.');
    }
    if (formula.prefermentedFlourFraction > Rational.one || formula.inclusionWater > formula.inclusions.values.fold(Rational.zero,(a,b)=>a+b) || formula.inclusions.keys.any((k)=>['flour','water','starter','salt'].contains(k))) {
      throw const DomainException('FORMULA_INVALID_BASIS','Check prefermented flour, inclusion names and inclusion water.');
    }
    if (targetDoughWeight != null && loafCount != null) throw ArgumentError('Choose target weight or loaf count, not both.');
    if (loafCount != null && loafCount <= 0) throw ArgumentError('Loaf count must be positive');
    final named=<String,Rational>{};
    var starterFlour=Rational.zero,starterWater=Rational.zero;
    if(formula.preferments.isEmpty){
      starterFlour=formula.totalFlour*formula.prefermentedFlourFraction;
      starterWater=starterFlour*formula.starterHydration;
      named['starter']=starterFlour+starterWater;
    }else{
      for(final p in formula.preferments){
        final key='preferment:${p.id}';
        if(named.containsKey(key)||formula.inclusions.containsKey(key))throw const DomainException('FORMULA_INVALID_BASIS','Preferment identifiers must be unique.');
        final flour=formula.totalFlour*p.flourFraction,water=flour*p.hydration;
        starterFlour+=flour;starterWater+=water;named[key]=flour+water;
      }
    }
    final flour=formula.totalFlour-starterFlour;
    final water=formula.totalFlour*formula.hydration-starterWater-formula.inclusionWater;
    if (water.isNegative || flour.isNegative) throw const DomainException('FORMULA_NEGATIVE_ADDITION','Starter contributes more flour or water than this formula permits.');
    final rows={'flour':flour,'water':water,...named,'salt':formula.totalFlour*formula.saltFraction,...formula.inclusions};
    final total=rows.values.fold(Rational.zero,(a,b)=>a+b);
    if (targetDoughWeight != null) {
      if (targetDoughWeight <= Rational.zero) throw ArgumentError('Target weight must be positive');
      return calculate(formula.scale(targetDoughWeight/total));
    }
    if (loafCount != null && loafCount != 1) return calculate(formula.scale(Rational.fromNum(loafCount)));
    return FormulaResult(formula,rows,total,starterFlour,starterWater);
  }
  FeedBuildResult buildStarter(FeedBuildRequest request) {
    final ratioSum=request.seedParts+request.flourParts+request.waterParts;
    if (request.requiredMass.isNegative || request.retainMass.isNegative || request.wasteAllowance.isNegative || request.seedParts<=Rational.zero || request.flourParts<=Rational.zero || request.waterParts.isNegative || request.seedHydration.isNegative || (request.availableSeed?.isNegative ?? false)) {
      throw const DomainException('FEED_INVALID_QUANTITY','Feed quantities and ratios must be valid nonnegative masses.');
    }
    final total=request.requiredMass+request.retainMass+request.wasteAllowance;
    if (total<=Rational.zero) throw const DomainException('FEED_INVALID_QUANTITY','Build must have positive final mass.');
    final seed=total*request.seedParts/ratioSum;
    if (request.availableSeed!=null && seed>request.availableSeed!) throw DomainException('FEED_INSUFFICIENT_SEED','Not enough seed for this build.',{'required':seed.toJson(),'available':request.availableSeed!.toJson()});
    final flour=total*request.flourParts/ratioSum;
    final water=total*request.waterParts/ratioSum;
    final seedFlour=seed/(Rational.one+request.seedHydration);
    return FeedBuildResult(seed,flour,water,total,(water+seed-seedFlour)/(flour+seedFlour),request.requiredMass,request.retainMass,request.wasteAllowance);
  }
}
final class FeedBuildRequest {
  final Rational requiredMass, retainMass, wasteAllowance, seedParts, flourParts, waterParts, seedHydration;
  final Rational? availableSeed;
  FeedBuildRequest({required this.requiredMass,Rational? retainMass,Rational? wasteAllowance,Rational? seedParts,Rational? flourParts,Rational? waterParts,Rational? seedHydration,this.availableSeed})
  : retainMass=retainMass??Rational.zero,wasteAllowance=wasteAllowance??Rational.zero,seedParts=seedParts??Rational.one,flourParts=flourParts??Rational.fromNum(2),waterParts=waterParts??Rational.fromNum(2),seedHydration=seedHydration??Rational.one;
}
final class FeedBuildResult {
 final Rational seed,flour,water,total,hydration,used,retained,wasteAllowance;
 const FeedBuildResult(this.seed,this.flour,this.water,this.total,this.hydration,this.used,this.retained,this.wasteAllowance);
 Map<String,dynamic> toJson()=>{'seed':seed.toJson(),'flour':flour.toJson(),'water':water.toJson(),'total':total.toJson(),'hydration':hydration.toJson(),'used':used.toJson(),'retained':retained.toJson(),'wasteAllowance':wasteAllowance.toJson()};
}

/// Conversion is deliberately explicit about ingredient source/uncertainty.
final class IngredientDensity {
 final Rational gramsPerMillilitre;
 final String source;
 final String uncertainty;
 IngredientDensity(this.gramsPerMillilitre,{required this.source,required this.uncertainty}) {
  if (gramsPerMillilitre<=Rational.zero || source.isEmpty || uncertainty.isEmpty) throw ArgumentError('Density requires positive value, source and uncertainty');
 }
 Rational gramsFor(Rational millilitres) {
  if (millilitres.isNegative) throw ArgumentError('Volume cannot be negative');
  return gramsPerMillilitre*millilitres;
 }
}
Rational celsiusToFahrenheit(Rational c) => c*Rational.fromNum(9)/Rational.fromNum(5)+Rational.fromNum(32);
Rational fahrenheitToCelsius(Rational f) => (f-Rational.fromNum(32))*Rational.fromNum(5)/Rational.fromNum(9);
