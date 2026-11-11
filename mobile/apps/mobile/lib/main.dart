import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'data/local_database.dart';
import 'data/local_store.dart';
import 'screens/main_screen.dart';
import 'services_screen.dart';
import 'platform/local_notifications.dart';
import 'platform/kitchen_platform.dart';
import 'platform/companion_snapshot.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final directory=await getApplicationSupportDirectory();
    final catalogue=jsonDecode(await rootBundle.loadString('assets/catalogue.json')) as Map<String,dynamic>;
    final store=LocalAppStore(LocalDatabase.file(File(path.join(directory.path,'crispy_crust.sqlite'))),catalogue);
    await store.load();
    runApp(CrispyCrustApp(store:store));
  } catch(error) {
    runApp(MaterialApp(home:Scaffold(body:SafeArea(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.storage_outlined,size:48),const SizedBox(height:20),const Text('Your local library could not be opened.',style:TextStyle(fontSize:24)),const SizedBox(height:12),const Text('Close and reopen the app. Your data has not been reset. If the problem continues, keep the app installed and contact support with this diagnostic:'),const SizedBox(height:12),SelectableText(error.toString())]))))));
  }
}

class CrispyCrustApp extends StatefulWidget {
  const CrispyCrustApp({super.key,required this.store});
  final LocalAppStore store;
  @override State<CrispyCrustApp> createState()=>_CrispyCrustAppState();
}
class _CrispyCrustAppState extends State<CrispyCrustApp> with WidgetsBindingObserver {
  final gateway=LocalNotificationGateway();
  final kitchen=KitchenPlatform();
  final navigator=GlobalKey<NavigatorState>();
  Timer? debounce;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);widget.store.addListener(changed);
    kitchen.listenForCompanionActions((action)async{
      final bake=widget.store.find(action.bakeId);if(bake==null)return false;
      if(action.type=='open'){navigator.currentState?.push(MaterialPageRoute(builder:(_)=>BakeDetail(store:widget.store,id:action.bakeId)));return true;}
      return widget.store.acknowledgeCompanion(operationId:action.operationId,bakeId:action.bakeId,stepId:action.stepId,expectedRevision:action.expectedRevision);
    });changed();}
  void changed(){
    debounce?.cancel();
    debounce=Timer(const Duration(milliseconds:300),()async{
      if(widget.store.preference('nativeReminders',false)==true) {
        try{await reconcileReminders(widget.store,gateway);}catch(_){/* In-app deadlines remain authoritative. */}
      }
      try{
        final bakes=widget.store.records('bake').where((b)=>!['complete','abandoned','archived'].contains(b.text('status'))).toList();
        if(widget.store.preference('companionSnapshots',false)!=true || bakes.isEmpty){await kitchen.clearCompanion();return;}
        final bake=bakes.first;final steps=(bake.fields['steps'] as List).cast<Map>();final index=bake.number('stepIndex').toInt();
        if(index>=steps.length){await kitchen.clearCompanion();return;}
        final step=steps[index];final due=DateTime.tryParse(step['plannedEnd']?.toString()??'');
        if(due==null)return;
        await kitchen.publishCompanion(CompanionTaskSnapshot(bakeId:bake.id,stepId:step['id'] as String,title:bake.text('name'),action:step['title'] as String,revision:bake.revision,dueAt:due.toUtc(),generatedAt:DateTime.now().toUtc()),enableLiveActivity:widget.store.preference('liveActivity',false)==true);
      }catch(_){/* Unsupported native surfaces do not block local baking. */}
    });
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed)changed();}
  @override void dispose(){debounce?.cancel();widget.store.removeListener(changed);WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.store,builder:(context,_)=>MaterialApp(
    title:'Crispy Crust',navigatorKey:navigator,debugShowCheckedModeBanner:false,
    theme:buildTheme(false),darkTheme:buildTheme(true),themeMode:widget.store.darkMode?ThemeMode.dark:ThemeMode.light,
    home:MainScreen(store:widget.store,servicesBuilder:(context)=>ServicesScreen(store:widget.store))));
}
ThemeData buildTheme(bool dark) {
  final scheme=ColorScheme.fromSeed(seedColor:const Color(0xff465538),brightness:dark?Brightness.dark:Brightness.light).copyWith(
    primary:Color(dark?0xffc3d2a6:0xff465538),onPrimary:Color(dark?0xff1e2b15:0xfffffffb),
    surface:Color(dark?0xff1c241a:0xfffffffb),onSurface:Color(dark?0xfff3f2e8:0xff263024),
    onSurfaceVariant:Color(dark?0xffbfc7b4:0xff5b6354),outline:Color(dark?0xff849076:0xff7a806f),error:Color(dark?0xffffb4ab:0xffa52f2f));
  return ThemeData(useMaterial3:true,colorScheme:scheme,fontFamily:'DM Sans',
    scaffoldBackgroundColor:Color(dark?0xff121810:0xfff8f7f0),
    visualDensity:VisualDensity.standard,
    appBarTheme:const AppBarTheme(centerTitle:false),
    inputDecorationTheme:InputDecorationTheme(border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)),contentPadding:const EdgeInsets.all(16)),
    filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(minimumSize:const Size(48,56),padding:const EdgeInsets.symmetric(horizontal:20,vertical:16),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)))),
    outlinedButtonTheme:OutlinedButtonThemeData(style:OutlinedButton.styleFrom(minimumSize:const Size(48,48),padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)))),
    textTheme:const TextTheme(bodyLarge:TextStyle(fontSize:16,height:1.5),bodyMedium:TextStyle(fontSize:16,height:1.5),titleLarge:TextStyle(fontSize:24,fontWeight:FontWeight.w600),titleMedium:TextStyle(fontSize:20,fontWeight:FontWeight.w600),headlineSmall:TextStyle(fontSize:26,fontWeight:FontWeight.w600)));
}
