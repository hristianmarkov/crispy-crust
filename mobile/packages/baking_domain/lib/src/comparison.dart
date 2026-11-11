import 'common.dart';

/// Recorded observations only. Unknown values are null, never zero. Numeric
/// fields use caller-defined canonical units (grams, Celsius, fractions).
final class BakeMeasurements {
 final String bakeId,recipeVersion;
 final Map<String,Rational?> measurements;
 final Map<String,String?> conditions;
 BakeMeasurements({required this.bakeId,required this.recipeVersion,
   Map<String,Rational?> measurements=const {},Map<String,String?> conditions=const {}})
   : measurements=Map.unmodifiable(measurements),conditions=Map.unmodifiable(conditions);
}
final class MeasurementDifference {
 final String field;
 final Rational baseline,other;
 const MeasurementDifference(this.field,this.baseline,this.other);
 Rational get delta=>other-baseline;
 Map<String,dynamic> toJson()=>{'field':field,'baseline':baseline.toJson(),'other':other.toJson(),'delta':delta.toJson()};
}
final class BakeComparison {
 final String baselineId,otherId;
 final bool sameRecipeVersion;
 final List<MeasurementDifference> numericDifferences;
 final List<String> changedConditions,missingFields,intendedChanges,uncontrolledChanges;
 BakeComparison({required this.baselineId,required this.otherId,required this.sameRecipeVersion,
  required List<MeasurementDifference> numericDifferences,required List<String> changedConditions,
  required List<String> missingFields,required List<String> intendedChanges,required List<String> uncontrolledChanges})
 :numericDifferences=List.unmodifiable(numericDifferences),changedConditions=List.unmodifiable(changedConditions),missingFields=List.unmodifiable(missingFields),intendedChanges=List.unmodifiable(intendedChanges),uncontrolledChanges=List.unmodifiable(uncontrolledChanges);
 bool get supportsCausalClaim=>false;
 bool get recordedConditionsControlled=>sameRecipeVersion&&missingFields.isEmpty&&uncontrolledChanges.isEmpty;
 String get explanation=>!sameRecipeVersion?'Recipe versions differ; compare the exact formula snapshots.':missingFields.isNotEmpty?'Some conditions were not recorded. Differences are associations, not proof of a cause.':uncontrolledChanges.isNotEmpty?'More than the intended variable changed. Differences are associations, not proof of a cause.':'Recorded conditions are aligned. A personal comparison still does not establish causation.';
}
final class BakeComparator {
 const BakeComparator();
 BakeComparison compare(BakeMeasurements baseline,BakeMeasurements other,{Set<String> intendedVariables=const {}}) {
  final missing=<String>[],numeric=<MeasurementDifference>[],changed=<String>[];
  final numericKeys={...baseline.measurements.keys,...other.measurements.keys}.toList()..sort();
  for(final key in numericKeys){final a=baseline.measurements[key],b=other.measurements[key];if(a==null||b==null){missing.add(key);}else if(a!=b){numeric.add(MeasurementDifference(key,a,b));}}
  final conditionKeys={...baseline.conditions.keys,...other.conditions.keys}.toList()..sort();
  for(final key in conditionKeys){final a=baseline.conditions[key],b=other.conditions[key];if(a==null||b==null||a.isEmpty||b.isEmpty){missing.add(key);}else if(a!=b){changed.add(key);}}
  final differences={...numeric.map((v)=>v.field),...changed}.toList()..sort();
  return BakeComparison(baselineId:baseline.bakeId,otherId:other.bakeId,sameRecipeVersion:baseline.recipeVersion==other.recipeVersion,numericDifferences:numeric,changedConditions:changed,missingFields:missing,intendedChanges:differences.where(intendedVariables.contains).toList(),uncontrolledChanges:differences.where((v)=>!intendedVariables.contains(v)).toList());
 }
}

final class IngredientUse {
 final String ingredientId;
 final Rational grams;
 IngredientUse(this.ingredientId,this.grams){if(ingredientId.isEmpty||grams.isNegative)throw ArgumentError('Ingredient demand must have identity and nonnegative mass');}
}
final class IngredientPrice {
 final String ingredientId,currency;
 final Rational packageGrams;
 final int packageCostMinorUnits;
 final DateTime recordedAt;
 IngredientPrice({required this.ingredientId,required this.currency,required this.packageGrams,required this.packageCostMinorUnits,required this.recordedAt}){
  if(ingredientId.isEmpty||!RegExp(r'^[A-Z]{3}$').hasMatch(currency)||packageGrams<=Rational.zero||packageCostMinorUnits<0||!recordedAt.isUtc)throw ArgumentError('Price requires ingredient, ISO currency, positive pack mass, nonnegative minor-unit cost and UTC date');
 }
}
final class BatchCost {
 final String currency;
 final Rational knownCostMinorUnits;
 final Rational? totalCostMinorUnits,perPortionCostMinorUnits;
 final List<String> missingPrices;
 final List<DateTime> priceDates;
 BatchCost(this.currency,this.knownCostMinorUnits,this.totalCostMinorUnits,this.perPortionCostMinorUnits,List<String> missingPrices,List<DateTime> priceDates):missingPrices=List.unmodifiable(missingPrices),priceDates=List.unmodifiable(priceDates);
 bool get complete=>missingPrices.isEmpty;
}
final class ShoppingDemand {
 final String ingredientId;
 final Rational requiredGrams;
 /// Null means stock is unknown, not that no stock exists.
 final Rational? stockGrams,additionalGrams;
 const ShoppingDemand(this.ingredientId,this.requiredGrams,this.stockGrams,this.additionalGrams);
}
final class CostAndShoppingEngine {
 const CostAndShoppingEngine();
 Map<String,Rational> aggregate(Iterable<IngredientUse> uses){
  final totals=<String,Rational>{};
  for(final u in uses)totals[u.ingredientId]=(totals[u.ingredientId]??Rational.zero)+u.grams;
  return Map.unmodifiable(totals);
 }
 BatchCost cost(Iterable<IngredientUse> uses,List<IngredientPrice> prices,{required String currency,int portions=1}){
  if(portions<1||!RegExp(r'^[A-Z]{3}$').hasMatch(currency))throw ArgumentError('Positive portions and ISO currency are required');
  final byId=<String,IngredientPrice>{};
  for(final price in prices){
   // Currency mixing is rejected rather than silently converted or dropped.
   if(price.currency!=currency)throw const DomainException('CURRENCY_MISMATCH','Convert prices explicitly before summing different currencies.');
   final previous=byId[price.ingredientId];
   if(previous==null||price.recordedAt.isAfter(previous.recordedAt))byId[price.ingredientId]=price;
  }
  var known=Rational.zero;final missing=<String>[],dates=<DateTime>[];
  for(final demand in aggregate(uses).entries){
   if(demand.value==Rational.zero)continue;
   final price=byId[demand.key];
   if(price==null){missing.add(demand.key);}else{known+=demand.value/price.packageGrams*Rational.fromNum(price.packageCostMinorUnits);dates.add(price.recordedAt);}
  }
  missing.sort();dates.sort();
  return BatchCost(currency,known,missing.isEmpty?known:null,missing.isEmpty?known/Rational.fromNum(portions):null,missing,dates);
 }
 List<ShoppingDemand> shopping(Iterable<IngredientUse> uses,Map<String,Rational?> stock){
  if(stock.values.any((v)=>v!=null&&v.isNegative))throw ArgumentError('Stock cannot be negative');
  final keys=aggregate(uses).entries.toList()..sort((a,b)=>a.key.compareTo(b.key));
  return List.unmodifiable(keys.map((e){final have=stock[e.key];final additional=have==null?null:e.value>have?e.value-have:Rational.zero;return ShoppingDemand(e.key,e.value,have,additional);}));
 }
}

/// CSV values are escaped and spreadsheet formula prefixes neutralised. The
/// structured JSON archive remains the lossless format for original user text.
String safeCsv(List<List<Object?>> rows)=>rows.map((row)=>row.map((value){
 var text=value?.toString()??'';
 if(value is String&&RegExp(r'^[\s]*[=+\-@\t\r]').hasMatch(text))text="'$text";
 return '"${text.replaceAll('"','""')}"';
}).join(',')).join('\r\n');
