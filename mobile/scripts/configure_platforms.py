#!/usr/bin/env python3
"""Idempotent native configuration. Never writes secrets or signing identities."""
from pathlib import Path
import plistlib
import re
import shutil
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
app = root / 'apps' / 'mobile'
templates = root / 'scripts' / 'templates'
android = app / 'android'
if android.exists():
    manifest = android / 'app/src/main/AndroidManifest.xml'
    ns = 'http://schemas.android.com/apk/res/android'
    ET.register_namespace('android', ns)
    tree = ET.parse(manifest)
    element = tree.getroot()
    permissions = {
        'android.permission.INTERNET': {},
        'android.permission.POST_NOTIFICATIONS': {},
        'android.permission.RECEIVE_BOOT_COMPLETED': {},
        'android.permission.SCHEDULE_EXACT_ALARM': {},
        'android.permission.READ_CALENDAR': {},
        'android.permission.BLUETOOTH_SCAN': {'usesPermissionFlags': 'neverForLocation'},
        'android.permission.BLUETOOTH_CONNECT': {},
        'android.permission.BLUETOOTH': {'maxSdkVersion': '30'},
        'android.permission.BLUETOOTH_ADMIN': {'maxSdkVersion': '30'},
        'android.permission.ACCESS_FINE_LOCATION': {'maxSdkVersion': '30'},
    }
    existing = {x.get(f'{{{ns}}}name') for x in element.findall('uses-permission')}
    for name, attributes in permissions.items():
        if name not in existing:
            ET.SubElement(element, 'uses-permission', {f'{{{ns}}}name': name,
                **{f'{{{ns}}}{k}': v for k, v in attributes.items()}})
    application = element.find('application')
    application.set(f'{{{ns}}}label', 'Crispy Crust')
    activity = application.find('activity')
    activity.set(f'{{{ns}}}name', 'app.crispycrust.crispy_crust.MainActivity')
    if not any(x.find("data") is not None and x.find('data').get(f'{{{ns}}}scheme') == 'app.crispycrust'
               for x in activity.findall('intent-filter')):
        intent = ET.SubElement(activity, 'intent-filter')
        ET.SubElement(intent, 'action', {f'{{{ns}}}name': 'android.intent.action.VIEW'})
        for category in ['DEFAULT', 'BROWSABLE']:
            ET.SubElement(intent, 'category', {f'{{{ns}}}name': f'android.intent.category.{category}'})
        ET.SubElement(intent, 'data', {f'{{{ns}}}scheme': 'app.crispycrust', f'{{{ns}}}host': 'auth', f'{{{ns}}}path': '/callback'})
    for receiver_name in ['com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
                          'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver']:
        if not any(x.get(f'{{{ns}}}name') == receiver_name for x in application.findall('receiver')):
            receiver = ET.SubElement(application, 'receiver', {f'{{{ns}}}name': receiver_name, f'{{{ns}}}exported': 'false'})
            if receiver_name.endswith('BootReceiver'):
                intent = ET.SubElement(receiver, 'intent-filter')
                for action in ['BOOT_COMPLETED', 'MY_PACKAGE_REPLACED', 'QUICKBOOT_POWERON']:
                    ET.SubElement(intent, 'action', {f'{{{ns}}}name': f'android.intent.action.{action}'})
    queries = element.find('queries')
    if queries is None:
        queries = ET.SubElement(element, 'queries')
    if not any(i.find('action') is not None and i.find('action').get(f'{{{ns}}}name') == 'android.intent.action.TTS_SERVICE' for i in queries.findall('intent')):
        intent = ET.SubElement(queries, 'intent')
        ET.SubElement(intent, 'action', {f'{{{ns}}}name': 'android.intent.action.TTS_SERVICE'})
    ET.indent(tree, space='    ')
    tree.write(manifest, encoding='unicode', xml_declaration=True)
    widget_class = 'app.crispycrust.crispy_crust.KitchenWidget'
    for receiver in application.findall('receiver'):
        if receiver.get(f'{{{ns}}}name') == '.KitchenWidget':
            receiver.set(f'{{{ns}}}name', widget_class)
    if not any(x.get(f'{{{ns}}}name') == widget_class for x in application.findall('receiver')):
        receiver = ET.SubElement(application, 'receiver', {f'{{{ns}}}name': widget_class, f'{{{ns}}}exported': 'false'})
        intent = ET.SubElement(receiver, 'intent-filter')
        ET.SubElement(intent, 'action', {f'{{{ns}}}name': 'android.appwidget.action.APPWIDGET_UPDATE'})
        ET.SubElement(receiver, 'meta-data', {f'{{{ns}}}name': 'android.appwidget.provider', f'{{{ns}}}resource': '@xml/kitchen_widget_info'})
        ET.indent(tree, space='    ')
        tree.write(manifest, encoding='unicode', xml_declaration=True)
    kotlin = android / 'app/src/main/kotlin/app/crispycrust/crispy_crust/MainActivity.kt'
    kotlin.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(templates / 'MainActivity.kt', kotlin)
    shutil.copyfile(templates / 'KitchenWidget.kt', kotlin.with_name('KitchenWidget.kt'))
    xml = android / 'app/src/main/res/xml'
    xml.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(templates / 'kitchen_widget_info.xml', xml / 'kitchen_widget_info.xml')
    drawable = android / 'app/src/main/res/drawable'
    drawable.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(templates / 'ic_notification.xml', drawable / 'ic_notification.xml')
    gradle = android / 'app/build.gradle.kts'
    if gradle.exists():
        text = gradle.read_text()
        text = re.sub(r'namespace\s*=\s*"[^"]+"', 'namespace = "app.crispycrust.crispy_crust"', text)
        text = re.sub(r'applicationId\s*=\s*"[^"]+"', 'applicationId = "app.crispycrust.mobile"', text)
        if 'isCoreLibraryDesugaringEnabled' not in text:
            text = text.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true')
        if 'desugar_jdk_libs' not in text:
            text += '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        if 'play-services-wearable' not in text:
            text += '\n\ndependencies {\n    implementation("com.google.android.gms:play-services-wearable:19.0.0")\n}\n'
        gradle.write_text(text)
    ET.indent(tree, space='    ')
    tree.write(manifest, encoding='unicode', xml_declaration=True)
    settings = android / 'settings.gradle.kts'
    if settings.exists() and 'include(":wear")' not in settings.read_text():
        with settings.open('a') as output:
            output.write('\ninclude(":wear")\nproject(":wear").projectDir = file("../../../native/wearos/app")\n')
ios = app / 'ios'
if ios.exists():
    plist = ios / 'Runner/Info.plist'
    with plist.open('rb') as f:
        config = plistlib.load(f)
    config['CFBundleDisplayName'] = 'Crispy Crust'
    config['NSSupportsLiveActivities'] = True
    config['CFBundleURLTypes'] = [{'CFBundleTypeRole': 'Editor', 'CFBundleURLSchemes': ['app.crispycrust']}]
    config['NSCalendarsFullAccessUsageDescription'] = 'Read only busy time ranges you choose to help fit baking around your day. Event details are not uploaded.'
    config['NSCalendarsUsageDescription'] = config['NSCalendarsFullAccessUsageDescription']
    config['NSBluetoothAlwaysUsageDescription'] = 'Connect a supported temperature probe you choose. Manual temperature entry always remains available.'
    config['NSCameraUsageDescription'] = 'Record a dough or starter observation when you choose to take a photo.'
    config['NSPhotoLibraryUsageDescription'] = 'Attach the photos you choose to your private baking journal.'
    with plist.open('wb') as f:
        plistlib.dump(config, f, sort_keys=False)
    shutil.copyfile(templates / 'AppDelegate.swift', ios / 'Runner/AppDelegate.swift')
    podfile = ios / 'Podfile'
    if podfile.exists() and 'PERMISSION_BLUETOOTH=1' not in podfile.read_text():
        text = podfile.read_text()
        needle = 'flutter_additional_ios_build_settings(target)'
        addition = """flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'PERMISSION_BLUETOOTH=1'
    end"""
        if needle in text:
            podfile.write_text(text.replace(needle, addition, 1))
print('Configured native permissions, secure callback, notifications, busy-calendar and keep-awake bridges.')
