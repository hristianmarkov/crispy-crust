import 'package:baking_domain/baking_domain.dart';
import 'package:test/test.dart';
Rational r(num n)=>Rational.fromNum(n);
void main(){
 test('comparison retains missing values and identifies confounding changes',(){
  final a=BakeMeasurements(bakeId:'a',recipeVersion:'v1',measurements:{'hydration':r(.7),'temperature':r(24),'rise':null},conditions:{'flour':'white','starter':'jar1'});
  final b=BakeMeasurements(bakeId:'b',recipeVersion:'v1',measurements:{'hydration':r(.75),'temperature':r(22),'rise':r(40)},conditions:{'flour':'white','starter':'jar1'});
  final comparison=const BakeComparator().compare(a,b,intendedVariables:{'hydration'});
  expect(comparison.intendedChanges,['hydration']);expect(comparison.uncontrolledChanges,['temperature']);expect(comparison.missingFields,['rise']);expect(comparison.supportsCausalClaim,isFalse);expect(comparison.recordedConditionsControlled,isFalse);
 });
 test('different versions cannot be treated as controlled conditions',(){
  final c=const BakeComparator().compare(BakeMeasurements(bakeId:'a',recipeVersion:'1'),BakeMeasurements(bakeId:'b',recipeVersion:'2'));
  expect(c.recordedConditionsControlled,isFalse);expect(c.supportsCausalClaim,isFalse);
 });
 test('cost uses exact fractional minor units before presentation rounding',(){
  final e=const CostAndShoppingEngine();final cost=e.cost([IngredientUse('flour',r(333)),IngredientUse('flour',r(167))],[IngredientPrice(ingredientId:'flour',currency:'GBP',packageGrams:r(1500),packageCostMinorUnits:200,recordedAt:DateTime.utc(2026,1))],currency:'GBP',portions:2);
  expect(cost.totalCostMinorUnits,Rational.parse('200/3'));expect(cost.perPortionCostMinorUnits,Rational.parse('100/3'));expect(cost.complete,isTrue);
 });
 test('unknown price is not free',(){
  final cost=const CostAndShoppingEngine().cost([IngredientUse('seeds',r(10))],[],currency:'GBP');expect(cost.totalCostMinorUnits,isNull);expect(cost.missingPrices,['seeds']);
 });
 test('mixed currencies require explicit conversion',(){
  expect(()=>const CostAndShoppingEngine().cost([],[IngredientPrice(ingredientId:'flour',currency:'USD',packageGrams:r(1000),packageCostMinorUnits:200,recordedAt:DateTime.utc(2026))],currency:'GBP'),throwsA(isA<DomainException>().having((e)=>e.code,'code','CURRENCY_MISMATCH')));
 });
 test('shopping distinguishes shortage unknown stock and excess stock',(){
  final demands=const CostAndShoppingEngine().shopping([IngredientUse('flour',r(500)),IngredientUse('seeds',r(20)),IngredientUse('salt',r(10))],{'flour':r(300),'salt':r(100)});
  expect(demands.first.additionalGrams,r(200));expect(demands.first.ingredientId,'flour');expect(demands[1].additionalGrams,Rational.zero);expect(demands.last.additionalGrams,isNull);
 });
 test('CSV escapes quotes newlines and spreadsheet formula cells',(){
  expect(safeCsv([['=HYPERLINK("bad")','a,b','line\nline',3,null]]),'"\'=HYPERLINK(""bad"")","a,b","line\nline","3",""');
 });
}
