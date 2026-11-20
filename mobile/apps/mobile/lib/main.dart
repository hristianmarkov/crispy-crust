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
import 'screens/welcome_screen.dart';
import 'services_screen.dart';
import 'platform/local_notifications.dart';
import 'platform/kitchen_platform.dart';
import 'platform/companion_snapshot.dart';
import 'platform/app_analytics.dart';
import 'data/app_store.dart';

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
  static const welcomeCompleted = 'welcomeCompleted';
  late final bool newLibrary = !widget.store.hasLocalRecords;
  final gateway=LocalNotificationGateway();
  final kitchen=KitchenPlatform();
  final navigator=GlobalKey<NavigatorState>();
  late final analytics = AppAnalytics(() => widget.store.preference(analyticsConsentKey, false) == true);
  Timer? debounce;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);widget.store.addListener(changed);
    kitchen.listenForCompanionActions((action)async{
      final bake=widget.store.find(action.bakeId);if(bake==null)return false;
      if(action.type=='open'){navigator.currentState?.push(MaterialPageRoute(builder:(_)=>BakeDetail(store:widget.store,id:action.bakeId)));return true;}
      return widget.store.acknowledgeCompanion(operationId:action.operationId,bakeId:action.bakeId,stepId:action.stepId,expectedRevision:action.expectedRevision);
    });unawaited(initializeReminders());changed();}
  Future<void> initializeReminders() async {
    try{
      await gateway.initialize(onOpen:(payload){
        if(payload==null)return;
        try{final data=jsonDecode(payload) as Map;final id=data['aggregateId'];if(id is String)openAggregate(id);}catch(_){/* Ignore malformed external payloads. */}
      });
    }catch(_){/* Native capability is checked at the point of use. */}
  }
  void openAggregate(String id){
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(!mounted)return;
      final record=widget.store.find(id);if(record==null)return;
      if(record.kind=='bake')navigator.currentState?.push(MaterialPageRoute(builder:(_)=>BakeDetail(store:widget.store,id:id)));
      if(record.kind=='starter')navigator.currentState?.push(MaterialPageRoute(builder:(_)=>StarterDetail(store:widget.store,id:id)));
      if(record.kind=='timer' && record.text('state')=='running') {
        navigator.currentState?.push(MaterialPageRoute(
          builder: (_) => TimerCentreScreen(store: widget.store),
        ));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
  void changed(){
    unawaited(analytics.updateConsent());
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
    home:newLibrary && widget.store.preference(welcomeCompleted, false) != true
      ? WelcomeScreen(onContinue: () => widget.store.setPreference(welcomeCompleted, true))
      : MainScreen(
      store: widget.store,
      onTabSelected: (tab) => unawaited(analytics.tabOpened(tab)),
      servicesBuilder: (context) => ServicesScreen(store: widget.store, analytics: analytics),
    )));
}
ThemeData buildTheme(bool dark) {
  final canvas = Color(dark ? 0xff161b13 : 0xfff6f3eb);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff465538),
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: Color(dark ? 0xffc3d2a6 : 0xff38452e),
    onPrimary: Color(dark ? 0xff202918 : 0xfffff9ed),
    surface: Color(dark ? 0xff22291e : 0xfffffcf5),
    onSurface: Color(dark ? 0xfff2efe4 : 0xff262b22),
    onSurfaceVariant: Color(dark ? 0xffc0c7b4 : 0xff555e50),
    secondaryContainer: Color(dark ? 0xff343e2a : 0xffe3e8d7),
    onSecondaryContainer: Color(dark ? 0xffe7efd8 : 0xff2a3823),
    outline: Color(dark ? 0xff849076 : 0xff737b6b),
    outlineVariant: Color(dark ? 0xff495144 : 0xffd8d8ca),
    error: Color(dark ? 0xffffb4ab : 0xffa52f2f),
  );
  const serif = 'DM Serif Display';
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: scheme.outline),
  );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'DM Sans',
    scaffoldBackgroundColor: canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: canvas, foregroundColor: scheme.onSurface,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      titleTextStyle: TextStyle(color: scheme.onSurface, fontFamily: serif, fontSize: 23),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface, elevation: 0, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: RoundedRectangleBorder(),
      collapsedShape: RoundedRectangleBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      height: 72,
      labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: scheme.surface, border: fieldBorder,
      enabledBorder: fieldBorder, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48), shape: buttonShape,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48), shape: buttonShape,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    )),
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontFamily: serif, fontSize: 43, height: 1.04),
      headlineMedium: TextStyle(fontFamily: serif, fontSize: 34, height: 1.12),
      headlineSmall: TextStyle(fontFamily: serif, fontSize: 28, height: 1.12),
      titleLarge: TextStyle(fontFamily: serif, fontSize: 23, height: 1.16),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 15, height: 1.45),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  );
}
