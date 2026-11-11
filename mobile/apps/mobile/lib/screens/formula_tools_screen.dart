import 'dart:convert';
import 'package:baking_domain/baking_domain.dart';
import 'package:flutter/material.dart';
import '../platform/export_share.dart';

/// Parse decimal-dot or decimal-comma input exactly. Commas never mean grouping;
/// mixed separators, exponents and nonfinite shorthand are rejected explicitly.
Rational parseToolQuantity(String input,{bool allowZero=true,String label='Quantity'}) {
  final text=input.trim();
  if(text.length>64||!RegExp(r'^\+?\d+(?:[.,]\d{1,12})?$|^\+?\d+/\d+$').hasMatch(text))throw FormatException('$label: use a nonnegative decimal (1.5 or 1,5) or fraction (1/3), without thousands separators.');
  Rational value;
  try{value=Rational.parse(text.replaceAll(',','.'));}on Object{throw FormatException('$label is not a valid finite quantity.');}
  if(value<Rational.zero||(!allowZero&&value==Rational.zero)||value>Rational.fromNum(1000000))throw FormatException('$label must be ${allowZero?'nonnegative':'positive'} and no greater than 1,000,000.');
  return value;
}
Rational _percent(String text,String label,{num maximum=1000}) {
  final value=parseToolQuantity(text,label:label);
  if(value>Rational.fromNum(maximum))throw FormatException('$label must not exceed $maximum%.');
  return value/Rational.fromNum(100);
}
class ToolPhysicalInput {
  const ToolPhysicalInput({required this.id,required this.name,required this.role,
    required this.grams, this.prefermentHydration='100'});
  final String id,name,role,grams,prefermentHydration;
}
class ToolPhysicalCalculation {
  ToolPhysicalCalculation(this.formula,this.inputs,this.prefermentedFlour,this.saltMass);
  final PhysicalFormula formula;
  final List<ToolPhysicalInput> inputs;
  final Rational prefermentedFlour,saltMass;
  Rational get prefermentedFlourPercent=>prefermentedFlour/formula.totalFlour*Rational.fromNum(100);
  Rational get saltPercent=>saltMass/formula.totalFlour*Rational.fromNum(100);
  Map<String,dynamic> toJson()=>{'formula':formula.toJson(),'rowNames':{for(final row in inputs)row.id:row.name},'roles':{for(final row in inputs)row.id:row.role},'prefermentedFlourPercent':prefermentedFlourPercent.toJson(),'explicitSaltPercent':saltPercent.toJson(),'hydrationBasis':'Plain water and declared preferment water only. Water in milk/eggs/other inclusions is excluded; no density or composition guessed.'};
}
ToolPhysicalCalculation calculatePhysicalTool(List<ToolPhysicalInput> rows,{String? targetDough,String? multiplier}) {
  if(rows.isEmpty||rows.length>40)throw const FormatException('Use between one and forty physical ingredient rows.');
  if(targetDough!=null&&multiplier!=null)throw const FormatException('Choose target mass or batch multiplier, not both.');
  final ingredients=<PhysicalIngredient>[];var prefermented=Rational.zero,salt=Rational.zero;
  for(final row in rows) {
    if(row.name.trim().isEmpty||row.name.length>100)throw const FormatException('Each ingredient needs a short name.');
    final grams=parseToolQuantity(row.grams,label:'${row.name} grams');
    var flour=Rational.zero,water=Rational.zero;
    switch(row.role) {
      case 'flour':flour=grams;
      case 'water':water=grams;
      case 'salt':salt+=grams;
      case 'preferment':
        final hydration=_percent(row.prefermentHydration,'${row.name} hydration');
        if(grams>Rational.zero) {
          // Ask the existing engine to split this physical preferment; do not
          // duplicate its hydration/component equations in the app layer.
          final split=const FormulaEngine().calculate(FormulaDefinition(totalFlour:Rational.one,hydration:hydration,saltFraction:Rational.zero,prefermentedFlourFraction:Rational.one,starterHydration:hydration),targetDoughWeight:grams);
          flour=split.starterFlour;water=split.starterWater;prefermented+=flour;
        }
      case 'other':break;
      default:throw const FormatException('Unknown ingredient role.');
    }
    ingredients.add(PhysicalIngredient(id:row.id,grams:grams,flourGrams:flour,waterGrams:water));
  }
  var formula=PhysicalFormula(ingredients);
  if(formula.totalFlour<=Rational.zero)throw const FormatException('At least one declared flour component is needed for baker’s percentages.');
  final original=formula.totalDough;
  if(targetDough!=null)formula=formula.toDoughWeight(parseToolQuantity(targetDough,allowZero:false,label:'Target dough mass'));
  if(multiplier!=null)formula=formula.scale(parseToolQuantity(multiplier,allowZero:false,label:'Batch multiplier'));
  final factor=formula.totalDough/original;
  return ToolPhysicalCalculation(formula,List.unmodifiable(rows),prefermented*factor,salt*factor);
}
class ToolPrefermentInput {
  const ToolPrefermentInput({required this.id,required this.flourPercent,required this.hydrationPercent});
  final String id,flourPercent,hydrationPercent;
}
FormulaResult calculateBakerTool({required String flourGrams,required String hydrationPercent,
    required String saltPercent,required List<ToolPrefermentInput> preferments,String? targetDough}) {
  if(preferments.length>12)throw const FormatException('Use at most twelve preferments.');
  final definition=FormulaDefinition(totalFlour:parseToolQuantity(flourGrams,allowZero:false,label:'Total flour'),hydration:_percent(hydrationPercent,'Overall hydration'),saltFraction:_percent(saltPercent,'Salt',maximum:100),prefermentedFlourFraction:Rational.zero,starterHydration:Rational.one,preferments:preferments.map((p)=>Preferment(id:p.id,flourFraction:_percent(p.flourPercent,'Prefermented flour',maximum:100),hydration:_percent(p.hydrationPercent,'Preferment hydration'))).toList());
  return const FormulaEngine().calculate(definition,targetDoughWeight:targetDough==null?null:parseToolQuantity(targetDough,allowZero:false,label:'Target dough mass'));
}
FeedBuildResult calculateFeedTool({required String requiredMass,required String retainMass,
  required String allowance,required String seedParts,required String flourParts,
  required String waterParts,required String seedHydration,String? availableSeed})=>const FormulaEngine().buildStarter(FeedBuildRequest(requiredMass:parseToolQuantity(requiredMass,label:'Recipe use'),retainMass:parseToolQuantity(retainMass,label:'Retain in jar'),wasteAllowance:parseToolQuantity(allowance,label:'Handling allowance'),seedParts:parseToolQuantity(seedParts,allowZero:false,label:'Seed parts'),flourParts:parseToolQuantity(flourParts,allowZero:false,label:'Flour parts'),waterParts:parseToolQuantity(waterParts,label:'Water parts'),seedHydration:_percent(seedHydration,'Seed hydration'),availableSeed:availableSeed==null?null:parseToolQuantity(availableSeed,label:'Available seed')));

class FormulaToolsScreen extends StatelessWidget {
  const FormulaToolsScreen({super.key});
  @override Widget build(BuildContext context)=>DefaultTabController(length:3,child:Scaffold(appBar:AppBar(title:const Text('Exact formula and feed tools'),bottom:const TabBar(isScrollable:true,tabAlignment:TabAlignment.start,tabs:[Tab(text:'Weigh-in'),Tab(text:'Percentages'),Tab(text:'Starter build')])),body:const TabBarView(children:[_PhysicalTool(),_BakerTool(),_FeedTool()])));
}
class _QuantityField extends StatelessWidget {
  const _QuantityField(this.controller,this.label,{this.onChanged});
  final TextEditingController controller;final String label;final VoidCallback? onChanged;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:16),child:TextField(controller:controller,decoration:InputDecoration(labelText:label),keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(_)=>onChanged?.call()));
}
class _FormulaRows extends StatelessWidget {
  const _FormulaRows(this.rows,{required this.title,this.names=const {}});
  final Map<String,Rational> rows;final String title;final Map<String,String> names;
  @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:Theme.of(context).textTheme.titleLarge),for(final row in rows.entries)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(names[row.key]??row.key)),const SizedBox(width:16),Flexible(child:Text('${row.value} g',textAlign:TextAlign.right))]))]);
}
class _ExportToolButton extends StatelessWidget {
  const _ExportToolButton(this.data);final Map<String,dynamic> data;
  @override Widget build(BuildContext context)=>OutlinedButton.icon(icon:const Icon(Icons.file_download_outlined),label:const Text('Preview and export selected calculation'),onPressed:()async {
    final text=const JsonEncoder.withIndent('  ').convert({'format':'crispy-crust-formula-calculation','version':1,'authority':'Calculator result, not a validated recipe or schedule','data':data});
    final accepted=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Review exactly what leaves this tool'),content:SizedBox(width:540,child:SingleChildScrollView(child:SelectableText(text))),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Keep private')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Save or share calculation'))]));
    if(accepted!=true)return;
    try {final result=await ExportShareService().shareTextFile(fileName:'crispy-crust-formula.json',content:text,mimeType:'application/json');if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(result.message)));}
    catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Export failed; calculation is still here. $e')));}
  });
}
const _inputNote='Example inputs are calculator values, not a validated recipe. Use decimal point or comma (never a thousands separator); fractions such as 1/3 can be pasted. Grams are physical masses.';
class _PhysicalRow {
  _PhysicalRow(this.id,String name,String grams,this.role):name=TextEditingController(text:name),grams=TextEditingController(text:grams);
  final String id;final TextEditingController name,grams;final hydration=TextEditingController(text:'100');String role;
  void dispose(){name.dispose();grams.dispose();hydration.dispose();}
  ToolPhysicalInput input()=>ToolPhysicalInput(id:id,name:name.text,role:role,grams:grams.text,prefermentHydration:hydration.text);
}
class _PhysicalTool extends StatefulWidget {const _PhysicalTool();@override State<_PhysicalTool> createState()=>_PhysicalToolState();}
class _PhysicalToolState extends State<_PhysicalTool> {
  final rows=[_PhysicalRow('flour-1','Bread flour','450','flour'),_PhysicalRow('water-1','Water','300','water'),_PhysicalRow('levain-1','Levain','100','preferment'),_PhysicalRow('salt-1','Salt','10','salt')];
  final target=TextEditingController(text:'1000'),factor=TextEditingController(text:'2');String scale='none',error='';int nextId=0;ToolPhysicalCalculation? result;num increment=1;
  @override void dispose(){for(final row in rows)row.dispose();target.dispose();factor.dispose();super.dispose();}
  void clear()=>setState((){result=null;error='';});
  void calculate(){try{final value=calculatePhysicalTool(rows.map((r)=>r.input()).toList(),targetDough:scale=='target'?target.text:null,multiplier:scale=='factor'?factor.text:null);setState((){result=value;error='';});}catch(e){setState((){result=null;error=e.toString();});}}
  @override Widget build(BuildContext context) {
    final value=result;final names={for(final row in rows)row.id:row.name.text};
    return ListView(padding:const EdgeInsets.all(20),children:[const Text(_inputNote),const SizedBox(height:16),const Text('Enter each physical ingredient once. A preferment is one weighed ingredient; its flour and water are counted internally and must not be entered again as separate additions.'),const SizedBox(height:16),
      for(final row in rows)Card(key:ValueKey(row.id),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[TextField(controller:row.name,decoration:const InputDecoration(labelText:'Ingredient name'),onChanged:(_)=>clear()),const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:row.role,isExpanded:true,decoration:const InputDecoration(labelText:'What is weighed?'),items:const [DropdownMenuItem(value:'flour',child:Text('Added flour')),DropdownMenuItem(value:'water',child:Text('Added plain water')),DropdownMenuItem(value:'preferment',child:Text('Starter / levain / preferment')),DropdownMenuItem(value:'salt',child:Text('Added salt')),DropdownMenuItem(value:'other',child:Text('Other inclusion (no water guessed)'))],onChanged:(v){if(v!=null)setState((){row.role=v;result=null;});}),const SizedBox(height:16),_QuantityField(row.grams,'Physical weight (g)',onChanged:clear),if(row.role=='preferment')_QuantityField(row.hydration,'This preferment’s hydration (%)',onChanged:clear),TextButton(onPressed:rows.length<=1?null:(){setState((){rows.remove(row);result=null;});row.dispose();},child:const Text('Remove this ingredient'))]))),
      OutlinedButton.icon(onPressed:rows.length>=40?null:()=>setState((){rows.add(_PhysicalRow('ingredient-${nextId++}','New ingredient','0','other'));result=null;}),icon:const Icon(Icons.add),label:const Text('Add physical ingredient')),
      DropdownButtonFormField<String>(initialValue:scale,isExpanded:true,decoration:const InputDecoration(labelText:'Scale this formula'),items:const [DropdownMenuItem(value:'none',child:Text('Keep these physical weights')),DropdownMenuItem(value:'target',child:Text('Target total dough mass')),DropdownMenuItem(value:'factor',child:Text('Multiply the whole formula'))],onChanged:(v)=>setState((){scale=v??'none';result=null;})),const SizedBox(height:16),if(scale=='target')_QuantityField(target,'Target total dough (g)',onChanged:clear),if(scale=='factor')_QuantityField(factor,'Batch multiplier',onChanged:clear),
      FilledButton(onPressed:calculate,child:const Text('Calculate exact physical formula')),if(error.isNotEmpty)Semantics(liveRegion:true,child:Text(error)),
      if(value!=null)...[const SizedBox(height:16),_FormulaRows({for(final i in value.formula.ingredients)i.id:i.grams},title:'Exact physical grams',names:names),Text('Total dough: ${value.formula.totalDough} g\nTotal flour including preferments: ${value.formula.totalFlour} g\nCounted water: ${value.formula.totalWater} g\nHydration: ${value.formula.hydration!*Rational.fromNum(100)}%\nPrefermented flour: ${value.prefermentedFlourPercent}% of total flour\nExplicit added salt: ${value.saltPercent}% of total flour'),const Text('Milk, egg and other inclusion water is excluded unless defined elsewhere. No cups conversion or substitution is guessed.'),
        const SizedBox(height:16),DropdownButtonFormField<num>(initialValue:increment,decoration:const InputDecoration(labelText:'Scale display precision'),items:const [DropdownMenuItem(value:1,child:Text('1 g increments')),DropdownMenuItem(value:0.1,child:Text('0.1 g increments'))],onChanged:(v)=>setState(()=>increment=v??1)),const SizedBox(height:16),
        _PhysicalRoundedView(value.formula,names:names,increment:increment),_ExportToolButton(value.toJson()),
      ],
    ]);
  }
}
class _PhysicalRoundedView extends StatelessWidget {
  const _PhysicalRoundedView(this.formula,{required this.names,required this.increment});final PhysicalFormula formula;final Map<String,String> names;final num increment;
  @override Widget build(BuildContext context) {
    PhysicalWeighOut rounded;
    try{rounded=formula.roundForScale(incrementGrams:increment);}catch(error){return Text('This scale precision cannot represent the physical formula. Choose a finer increment. $error');}
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[_FormulaRows(rounded.ingredients,title:'Rounded weigh-out only',names:names),Text('Rounded total: ${rounded.totalDough} g. Residual adjustment: ${rounded.roundingResidual} g to ${rounded.residualIngredient==null?'no ingredient (no adjustment)':names[rounded.residualIngredient]??rounded.residualIngredient}. The exact formula above is unchanged.'),if(rounded.roundedHydration!=null)Text('Hydration after display rounding: ${rounded.roundedHydration!*Rational.fromNum(100)}%')]);
  }
}
class _BakerTool extends StatefulWidget {const _BakerTool();@override State<_BakerTool> createState()=>_BakerToolState();}
class _PrefermentRow { _PrefermentRow(this.id);final String id;final flour=TextEditingController(text:'10'),hydration=TextEditingController(text:'100');void dispose(){flour.dispose();hydration.dispose();}}
class _BakerToolState extends State<_BakerTool> {
  final flour=TextEditingController(text:'500'),hydration=TextEditingController(text:'70'),salt=TextEditingController(text:'2'),target=TextEditingController(text:'1000');final preferments=[_PrefermentRow('levain-1')];int nextId=2;bool targetEnabled=false;num increment=1;FormulaResult? result;String error='';
  @override void dispose(){for(final c in [flour,hydration,salt,target])c.dispose();for(final p in preferments)p.dispose();super.dispose();}
  void clear()=>setState((){result=null;error='';});
  void calculate(){try{final value=calculateBakerTool(flourGrams:flour.text,hydrationPercent:hydration.text,saltPercent:salt.text,preferments:preferments.map((p)=>ToolPrefermentInput(id:p.id,flourPercent:p.flour.text,hydrationPercent:p.hydration.text)).toList(),targetDough:targetEnabled?target.text:null);setState((){result=value;error='';});}catch(e){setState((){result=null;error=e.toString();});}}
  @override Widget build(BuildContext context) {
    final value=result;WeighOut? weigh;String? roundingError;
    try{weigh=value?.roundForScale(incrementGrams:increment);}catch(e){roundingError='Choose finer scale precision; exact values are preserved. $e';}
    return ListView(padding:const EdgeInsets.all(20),children:[const Text(_inputNote),const SizedBox(height:16),const Text('Total flour includes all flour inside preferments. “10% prefermented flour” is not “10% starter mass”. Each named preferment replaces the generic starter definition.'),const SizedBox(height:16),_QuantityField(flour,'Total flour, including preferment flour (g)',onChanged:clear),_QuantityField(hydration,'Overall water-to-total-flour hydration (%)',onChanged:clear),_QuantityField(salt,'Salt as percentage of total flour (%)',onChanged:clear),for(final preferment in preferments)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(preferment.id),_QuantityField(preferment.flour,'Flour inside this preferment (% of total flour)',onChanged:clear),_QuantityField(preferment.hydration,'This preferment’s hydration (%)',onChanged:clear),TextButton(onPressed:preferments.length<=1?null:(){setState((){preferments.remove(preferment);result=null;});preferment.dispose();},child:const Text('Remove this preferment'))]))),OutlinedButton(onPressed:preferments.length>=12?null:()=>setState((){preferments.add(_PrefermentRow('levain-${nextId++}'));result=null;}),child:const Text('Add another preferment')),
      SwitchListTile(contentPadding:EdgeInsets.zero,value:targetEnabled,onChanged:(v)=>setState((){targetEnabled=v;result=null;}),title:const Text('Scale to a target dough mass')),if(targetEnabled)_QuantityField(target,'Target total dough mass (g)',onChanged:clear),FilledButton(onPressed:calculate,child:const Text('Calculate baker’s formula')),if(error.isNotEmpty)Semantics(liveRegion:true,child:Text(error)),if(value!=null)...[const SizedBox(height:16),_FormulaRows(value.ingredients,title:'Exact physical additions'),Text('Dough: ${value.totalDough} g\nPreferment flour already counted: ${value.starterFlour} g\nPreferment water already counted: ${value.starterWater} g\nOverall hydration: ${value.definition.hydration*Rational.fromNum(100)}%'),const Text('Do not weigh the component flour/water again. Only the physical additions in the table go into the bowl.'),DropdownButtonFormField<num>(initialValue:increment,decoration:const InputDecoration(labelText:'Weigh-out precision'),items:const [DropdownMenuItem(value:1,child:Text('1 g')),DropdownMenuItem(value:0.1,child:Text('0.1 g'))],onChanged:(v)=>setState(()=>increment=v??1)),if(roundingError!=null)Text(roundingError),if(weigh!=null)...[_FormulaRows(weigh.ingredients,title:'Rounded weigh-out only'),Text('Rounded dough ${weigh.totalDough} g; residual ${weigh.roundingResidual} g applied to ${weigh.residualIngredient}. Exact stored calculation remains unchanged.')],_ExportToolButton(value.toJson())],
    ]);
  }
}
class _FeedTool extends StatefulWidget {const _FeedTool();@override State<_FeedTool> createState()=>_FeedToolState();}
class _FeedToolState extends State<_FeedTool> {
  final requiredMass=TextEditingController(text:'200'),retain=TextEditingController(text:'20'),allowance=TextEditingController(text:'0'),seedParts=TextEditingController(text:'1'),flourParts=TextEditingController(text:'2'),waterParts=TextEditingController(text:'2'),hydration=TextEditingController(text:'100'),available=TextEditingController();FeedBuildResult? result;String error='';
  @override void dispose(){for(final c in [requiredMass,retain,allowance,seedParts,flourParts,waterParts,hydration,available])c.dispose();super.dispose();}
  void clear()=>setState((){result=null;error='';});
  void calculate(){try{final value=calculateFeedTool(requiredMass:requiredMass.text,retainMass:retain.text,allowance:allowance.text,seedParts:seedParts.text,flourParts:flourParts.text,waterParts:waterParts.text,seedHydration:hydration.text,availableSeed:available.text.trim().isEmpty?null:available.text);setState((){result=value;error='';});}catch(e){setState((){result=null;error=e.toString();});}}
  @override Widget build(BuildContext context) {
    final value=result;
    return ListView(padding:const EdgeInsets.all(20),children:[const Text('This plans one combined build that you later split. It does not log a feed or change your jar stock. The final mass includes the seed already in the bowl; it is not the amount of new flour/water to add.'),const SizedBox(height:16),_QuantityField(requiredMass,'Amount to use in recipe (g)',onChanged:clear),_QuantityField(retain,'Amount to retain as mother starter (g)',onChanged:clear),_QuantityField(allowance,'Handling allowance (g; optional planned margin)',onChanged:clear),_QuantityField(seedParts,'Ratio: seed parts',onChanged:clear),_QuantityField(flourParts,'Ratio: flour parts',onChanged:clear),_QuantityField(waterParts,'Ratio: water parts',onChanged:clear),_QuantityField(hydration,'Hydration of seed (%)',onChanged:clear),_QuantityField(available,'Available seed (g; leave blank if unknown)',onChanged:clear),FilledButton(onPressed:calculate,child:const Text('Calculate exact starter build')),if(error.isNotEmpty)Semantics(liveRegion:true,child:Text(error)),if(value!=null)...[const SizedBox(height:16),_FormulaRows({'seed':value.seed,'new flour':value.flour,'new water':value.water},title:'What goes into the build'),Text('Final combined build: ${value.total} g\nUse in recipe: ${value.used} g\nRetain in jar: ${value.retained} g\nHandling allowance: ${value.wasteAllowance} g\nResulting hydration: ${value.hydration*Rational.fromNum(100)}%'),const Text('Confirm actual weights in the feed log when you physically feed. An allowance is not an automatic discard or a safety assessment.'),_ExportToolButton(value.toJson())],
    ]);
  }
}
