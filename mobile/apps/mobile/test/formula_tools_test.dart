import 'package:baking_domain/baking_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/screens/formula_tools_screen.dart';

List<ToolPhysicalInput> physical()=>const [
  ToolPhysicalInput(id:'white',name:'White flour',role:'flour',grams:'300'),
  ToolPhysicalInput(id:'wholemeal',name:'Wholemeal flour',role:'flour',grams:'150'),
  ToolPhysicalInput(id:'water',name:'Added water',role:'water',grams:'300'),
  ToolPhysicalInput(id:'levain',name:'Liquid levain',role:'preferment',grams:'100',prefermentHydration:'100'),
  ToolPhysicalInput(id:'salt',name:'Salt',role:'salt',grams:'10'),
];
void main() {
  test('decimal comma, decimal dot and fractions preserve exact input',() {
    expect(parseToolQuantity('1,5'),Rational.parse('3/2'));expect(parseToolQuantity('1.5'),Rational.parse('3/2'));expect(parseToolQuantity('1/3')*Rational.fromNum(3),Rational.one);
    expect(parseToolQuantity('1,000'),Rational.one); // Comma explicitly means decimal, never grouping.
    for(final bad in ['1,234.5','NaN','Infinity','-1','1e3','1/0',''])expect(()=>parseToolQuantity(bad),throwsFormatException);
  });
  test('physical components count a preferment once across multiple flour rows',() {
    final result=calculatePhysicalTool(physical());
    expect(result.formula.totalDough,Rational.fromNum(860));expect(result.formula.totalFlour,Rational.fromNum(500));expect(result.formula.totalWater,Rational.fromNum(350));expect(result.formula.hydration,Rational.parse('7/10'));expect(result.prefermentedFlourPercent,Rational.fromNum(10));expect(result.saltPercent,Rational.fromNum(2));
    expect(result.formula.ingredients.length,5); // No duplicate starter component rows are weighed.
  });
  test('target mass and multiplier use exact domain scaling',() {
    final scaled=calculatePhysicalTool(physical(),targetDough:'1000');expect(scaled.formula.totalDough,Rational.fromNum(1000));expect(scaled.formula.hydration,Rational.parse('7/10'));
    expect(calculatePhysicalTool(physical(),multiplier:'2').formula.totalDough,Rational.fromNum(1720));
    expect(()=>calculatePhysicalTool(physical(),multiplier:'2',targetDough:'1000'),throwsFormatException);
  });
  test('milk water is not silently guessed or double counted',() {
    final result=calculatePhysicalTool([...physical(),const ToolPhysicalInput(id:'milk',name:'Milk',role:'other',grams:'100')]);
    expect(result.formula.totalDough,Rational.fromNum(960));expect(result.formula.totalWater,Rational.fromNum(350));expect(result.formula.hydration,Rational.parse('7/10'));
    expect(result.toJson()['hydrationBasis'],contains('excluded'));
  });
  test('multiple explicit preferments replace generic starter definition',() {
    final result=calculateBakerTool(flourGrams:'1000',hydrationPercent:'75',saltPercent:'2',preferments:const [ToolPrefermentInput(id:'liquid',flourPercent:'10',hydrationPercent:'100'),ToolPrefermentInput(id:'stiff',flourPercent:'5',hydrationPercent:'50')]);
    expect(result.starterFlour,Rational.fromNum(150));expect(result.starterWater,Rational.fromNum(125));expect(result.addedFlour,Rational.fromNum(850));expect(result.addedWater,Rational.fromNum(625));expect(result.ingredients.containsKey('starter'),isFalse);expect(result.ingredients['preferment:liquid'],Rational.fromNum(200));expect(result.ingredients['preferment:stiff'],Rational.fromNum(75));expect(result.totalDough,Rational.fromNum(1770));
  });
  test('impossible water addition and duplicate preferment IDs fail closed',() {
    expect(()=>calculateBakerTool(flourGrams:'500',hydrationPercent:'40',saltPercent:'2',preferments:const [ToolPrefermentInput(id:'wet',flourPercent:'50',hydrationPercent:'100')]),throwsA(isA<DomainException>().having((e)=>e.code,'code','FORMULA_NEGATIVE_ADDITION')));
    expect(()=>calculateBakerTool(flourGrams:'500',hydrationPercent:'70',saltPercent:'2',preferments:const [ToolPrefermentInput(id:'duplicate',flourPercent:'10',hydrationPercent:'100'),ToolPrefermentInput(id:'duplicate',flourPercent:'10',hydrationPercent:'100')]),throwsA(isA<DomainException>()));
  });
  test('feed final mass includes mother retention and existing seed, not just additions',() {
    final result=calculateFeedTool(requiredMass:'200',retainMass:'20',allowance:'0',seedParts:'1',flourParts:'2',waterParts:'2',seedHydration:'100',availableSeed:'44');
    expect(result.total,Rational.fromNum(220));expect(result.seed,Rational.fromNum(44));expect(result.flour,Rational.fromNum(88));expect(result.water,Rational.fromNum(88));expect(result.used,Rational.fromNum(200));expect(result.retained,Rational.fromNum(20));expect(result.hydration,Rational.one);
    expect(()=>calculateFeedTool(requiredMass:'200',retainMass:'20',allowance:'0',seedParts:'1',flourParts:'2',waterParts:'2',seedHydration:'100',availableSeed:'20'),throwsA(isA<DomainException>().having((e)=>e.code,'code','FEED_INSUFFICIENT_SEED')));
  });
  test('rounded physical weigh-out conserves display total without changing exact formula',() {
    final result=calculatePhysicalTool(physical(),targetDough:'1000');final original=canonicalJson(result.formula.toJson());
    final rounded=result.formula.roundForScale(incrementGrams:1);
    expect(rounded.ingredients.values.fold(Rational.zero,(a,b)=>a+b),rounded.totalDough);expect(canonicalJson(result.formula.toJson()),original);
  });
  testWidgets('calculator does not imply recipe approval or log any user action',(tester) async {
    await tester.pumpWidget(const MaterialApp(home:FormulaToolsScreen()));
    expect(find.textContaining('not a validated recipe'),findsWidgets);expect(find.text('Weigh-in'),findsOneWidget);expect(find.text('Percentages'),findsOneWidget);expect(find.text('Starter build'),findsOneWidget);
  });
}
