#!/usr/bin/env ruby
# Reproducible unsigned target embedding; signing is selected by the owner at release.
require 'xcodeproj'
require 'fileutils'
require 'json'

mobile = File.expand_path('..', __dir__)
ios = File.join(mobile, 'apps/mobile/ios')
project_path = File.join(ios, 'Runner.xcodeproj')
abort 'Generate the Flutter iOS runner first.' unless File.exist?(project_path)
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |target| target.name == 'Runner' }
abort 'Flutter Runner target not found.' unless runner
companions = File.join(ios, 'RunnerCompanions')
FileUtils.mkdir_p(companions)

def plist(path, values)
  Xcodeproj::Plist.write_to_path(values, path)
end

def embed(project, runner, target, phase_name, destination, subfolder)
  runner.add_dependency(target) unless runner.dependencies.any? { |dep| dep.target == target }
  phase = runner.copy_files_build_phases.find { |item| item.name == phase_name } || runner.new_copy_files_build_phase(phase_name)
  phase.dst_subfolder_spec = subfolder
  phase.dst_path = destination
  unless phase.files.any? { |item| item.file_ref == target.product_reference }
    file = phase.add_file_reference(target.product_reference)
    file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  end
end

def add_target(project, name, platform, deployment, files, plist_path, identifier)
  target = project.targets.find { |item| item.name == name } || project.new_target(
    platform == :watchos ? :application : :app_extension, name, platform, deployment)
  group = project.main_group.find_subpath('RunnerCompanions', true)
  files.each do |path|
    relative = Pathname.new(path).relative_path_from(Pathname.new(project.project_dir)).to_s
    reference = group.files.find { |item| item.path == relative } || group.new_file(relative)
    target.source_build_phase.add_file_reference(reference) unless target.source_build_phase.files.any? { |item| item.file_ref == reference }
  end
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => identifier,
      'PRODUCT_NAME' => name, 'PRODUCT_MODULE_NAME' => name,
      'EXECUTABLE_NAME' => '$(PRODUCT_NAME)',
      'WRAPPER_EXTENSION' => platform == :watchos ? 'app' : 'appex',
      'SWIFT_VERSION' => '5.0', 'SWIFT_STRICT_CONCURRENCY' => 'minimal',
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'INFOPLIST_FILE' => Pathname.new(plist_path).relative_path_from(Pathname.new(project.project_dir)).to_s,
      'CURRENT_PROJECT_VERSION' => '1', 'MARKETING_VERSION' => '0.1.0',
      'SKIP_INSTALL' => 'YES', 'CODE_SIGN_STYLE' => 'Automatic'
    })
    if platform == :watchos
      config.build_settings.merge!({'SDKROOT' => 'watchos', 'SUPPORTED_PLATFORMS' => 'watchos watchsimulator',
        'WATCHOS_DEPLOYMENT_TARGET' => deployment, 'TARGETED_DEVICE_FAMILY' => '4'})
    else
      config.build_settings.merge!({'SDKROOT' => 'iphoneos', 'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
        'IPHONEOS_DEPLOYMENT_TARGET' => deployment, 'TARGETED_DEVICE_FAMILY' => '1,2',
        'APPLICATION_EXTENSION_API_ONLY' => 'YES'})
    end
  end
  target
end

bundle_id = runner.build_configurations.first.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
bundle_id = 'app.crispycrust.crispy_crust' if bundle_id.nil? || bundle_id.include?('$')
watch_dir = File.join(companions, 'Watch')
widget_dir = File.join(companions, 'Widgets')
FileUtils.mkdir_p([watch_dir, widget_dir])
watch_file = File.join(watch_dir, 'WatchApp.swift')
File.write(watch_file, File.read(File.join(mobile, 'native/apple/Watch/WatchApp.swift')).gsub("import CrispyCompanionCore\n", ''))
core_file = File.join(watch_dir, 'TaskSnapshot.swift')
FileUtils.cp(File.join(mobile, 'native/apple/Sources/CrispyCompanionCore/TaskSnapshot.swift'), core_file)
widget_file = File.join(widget_dir, 'BakeActivity.swift')
FileUtils.cp(File.join(mobile, 'native/apple/Widgets/BakeActivity.swift'), widget_file)
base_plist = {'CFBundleDevelopmentRegion' => 'en', 'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
  'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion' => '6.0',
  'CFBundleName' => '$(PRODUCT_NAME)', 'CFBundleShortVersionString' => '$(MARKETING_VERSION)',
  'CFBundleVersion' => '$(CURRENT_PROJECT_VERSION)'}
watch_plist = File.join(watch_dir, 'Info.plist')
plist(watch_plist, base_plist.merge({'CFBundleDisplayName' => 'Crispy Crust', 'CFBundlePackageType' => 'APPL',
  'WKApplication' => true, 'WKCompanionAppBundleIdentifier' => bundle_id,
  'WKRunsIndependentlyOfCompanionApp' => false}))
widget_plist = File.join(widget_dir, 'Info.plist')
plist(widget_plist, base_plist.merge({'CFBundleDisplayName' => 'Crispy Crust', 'CFBundlePackageType' => 'XPC!',
  'NSExtension' => {'NSExtensionPointIdentifier' => 'com.apple.widgetkit-extension'}}))
watch = add_target(project, 'CrispyWatch', :watchos, '9.0', [watch_file, core_file], watch_plist, "#{bundle_id}.watch")
widget = add_target(project, 'CrispyWidgets', :ios, '16.2', [widget_file], widget_plist, "#{bundle_id}.widgets")
embed(project, runner, widget, 'Embed Crispy Widgets', '', '13')
embed(project, runner, watch, 'Embed Crispy Watch', '$(CONTENTS_FOLDER_PATH)/Watch', '16')
group_identifier = 'group.app.crispycrust.shared'
runner_entitlements = File.join(ios, 'Runner/CrispyRunner.entitlements')
widget_entitlements = File.join(widget_dir, 'CrispyWidgets.entitlements')
existing = File.exist?(runner_entitlements) ? Xcodeproj::Plist.read_from_path(runner_entitlements) : {}
existing['com.apple.security.application-groups'] = [group_identifier]
plist(runner_entitlements, existing)
plist(widget_entitlements, {'com.apple.security.application-groups' => [group_identifier]})
runner.build_configurations.each { |config| config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/CrispyRunner.entitlements' }
widget.build_configurations.each { |config| config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'RunnerCompanions/Widgets/CrispyWidgets.entitlements' }
[watch, widget].each do |target|
  target.build_configurations.each do |config|
    abort "Missing companion PRODUCT_NAME for #{target.name}/#{config.name}" if config.build_settings['PRODUCT_NAME'].to_s.empty?
  end
end
project.save
puts 'Embedded CrispyWatch and CrispyWidgets targets into Runner with explicit sources, plists, dependencies and copy phases.'
