#!/usr/bin/env ruby
# Reproducible unsigned target embedding; signing is selected by the owner at release.
require 'xcodeproj'
require 'fileutils'
require 'json'
require 'rexml/document'
require_relative 'apple_phase_order'

mobile = File.expand_path('..', __dir__)
ios = File.join(mobile, 'apps/mobile/ios')
project_path = File.join(ios, 'Runner.xcodeproj')
abort 'Generate the Flutter iOS runner first.' unless File.exist?(project_path)
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |target| target.name == 'Runner' }
abort 'Flutter Runner target not found.' unless runner
companions = File.join(ios, 'RunnerCompanions')
FileUtils.mkdir_p(companions)
launch_assets = File.join(ios, 'Runner/Assets.xcassets/LaunchImage.imageset')
FileUtils.mkdir_p(launch_assets)
FileUtils.cp(File.join(mobile, 'apps/mobile/assets/brand/app-icon.png'), File.join(launch_assets, 'LaunchImage.png'))
File.write(File.join(launch_assets, 'Contents.json'), JSON.pretty_generate({
  'images' => [{'idiom' => 'universal', 'filename' => 'LaunchImage.png', 'scale' => '1x'}],
  'info' => {'author' => 'xcode', 'version' => 1}
}))
launch_storyboard = File.join(ios, 'Runner/Base.lproj/LaunchScreen.storyboard')
launch_document = REXML::Document.new(File.read(launch_storyboard))
launch_image = REXML::XPath.first(launch_document, "//imageView[@image='LaunchImage']")
abort 'Flutter launch image view is missing.' unless launch_image
launch_image.attributes['contentMode'] = 'scaleAspectFit'
launch_constraints = launch_image.elements['constraints'] || launch_image.add_element('constraints')
{'width' => 'ccW-01-LaU', 'height' => 'ccH-01-LaU'}.each do |attribute, identifier|
  constraint = launch_constraints.elements["constraint[@firstAttribute='#{attribute}']"] || launch_constraints.add_element('constraint')
  constraint.add_attributes({'firstAttribute' => attribute, 'constant' => '128', 'id' => identifier})
end
launch_background = REXML::XPath.first(launch_document, "//view[@key='view']/color[@key='backgroundColor']")
launch_background&.add_attributes({'red' => '0.9647058824', 'green' => '0.9529411765', 'blue' => '0.9215686275'})
launch_resource = REXML::XPath.first(launch_document, "//resources/image[@name='LaunchImage']")
launch_resource&.add_attributes({'width' => '1024', 'height' => '1024'})
File.open(launch_storyboard, 'w') { |file| launch_document.write(file, 2) }

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

def add_target(project, name, platform, deployment, files, plist_path, identifier, version, build_number)
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
      'CURRENT_PROJECT_VERSION' => build_number, 'MARKETING_VERSION' => version,
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

bundle_id = 'app.crispycrust.mobile'
version_match = File.read(File.join(mobile, 'apps/mobile/pubspec.yaml')).match(/^version:\s*([^+\s]+)\+(\d+)\s*$/)
abort 'Expected a version and build number in pubspec.yaml.' unless version_match
app_version = ENV.fetch('CRISPY_APP_VERSION', version_match[1])
app_build = ENV.fetch('CRISPY_APP_BUILD_NUMBER', version_match[2])
abort 'Invalid Apple version.' unless app_version.match?(/\A\d+\.\d+(?:\.\d+)?\z/)
app_version += '.0' if app_version.split('.').length == 2 # Flutter normalizes 1.0 to 1.0.0.
abort 'Invalid Apple build number.' unless app_build.match?(/\A[1-9]\d*\z/)
runner.build_configurations.each { |config| config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id }
project.targets.select { |target| target.name == 'RunnerTests' }.each do |target|
  target.build_configurations.each { |config| config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{bundle_id}.RunnerTests" }
end
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
  'CFBundleIconName' => 'AppIcon',
  'WKApplication' => true, 'WKCompanionAppBundleIdentifier' => bundle_id,
  'WKRunsIndependentlyOfCompanionApp' => false}))
widget_plist = File.join(widget_dir, 'Info.plist')
plist(widget_plist, base_plist.merge({'CFBundleDisplayName' => 'Crispy Crust', 'CFBundlePackageType' => 'XPC!',
  'NSExtension' => {'NSExtensionPointIdentifier' => 'com.apple.widgetkit-extension'}}))
watch = add_target(project, 'CrispyWatch', :watchos, '9.0', [watch_file, core_file], watch_plist, "#{bundle_id}.watch", app_version, app_build)
widget = add_target(project, 'CrispyWidgets', :ios, '16.2', [widget_file], widget_plist, "#{bundle_id}.widgets", app_version, app_build)
# Watch apps need their own icon catalogue for App Store validation. The brand
# source is an opaque 1024px RGB PNG; Xcode generates the watch size variants.
watch_assets = File.join(watch_dir, 'Assets.xcassets')
watch_icon = File.join(watch_assets, 'AppIcon.appiconset')
FileUtils.mkdir_p(watch_icon)
FileUtils.cp(File.join(mobile, 'apps/mobile/assets/brand/app-icon.png'), File.join(watch_icon, 'AppIcon.png'))
File.write(File.join(watch_assets, 'Contents.json'), JSON.pretty_generate({'info' => {'author' => 'xcode', 'version' => 1}}))
File.write(File.join(watch_icon, 'Contents.json'), JSON.pretty_generate({
  'images' => [{'filename' => 'AppIcon.png', 'idiom' => 'universal', 'platform' => 'watchos', 'size' => '1024x1024'}],
  'info' => {'author' => 'xcode', 'version' => 1}
}))
watch_group = project.main_group.find_subpath('RunnerCompanions', true)
watch_assets_path = Pathname.new(watch_assets).relative_path_from(Pathname.new(project.project_dir)).to_s
watch_assets_ref = watch_group.files.find { |item| item.path == watch_assets_path } || watch_group.new_file(watch_assets_path)
unless watch.resources_build_phase.files.any? { |item| item.file_ref == watch_assets_ref }
  watch.resources_build_phase.add_file_reference(watch_assets_ref)
end
watch.build_configurations.each { |config| config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon' }
embed(project, runner, widget, 'Embed Crispy Widgets', '', '13')
embed(project, runner, watch, 'Embed Crispy Watch', '$(CONTENTS_FOLDER_PATH)/Watch', '16')
order_companion_embed_phases(runner)
group_identifier = 'group.app.crispycrust.shared'
runner_entitlements = File.join(ios, 'Runner/CrispyRunner.entitlements')
widget_entitlements = File.join(widget_dir, 'CrispyWidgets.entitlements')
existing = File.exist?(runner_entitlements) ? Xcodeproj::Plist.read_from_path(runner_entitlements) : {}
existing['com.apple.security.application-groups'] = [group_identifier]
existing['com.apple.developer.applesignin'] = ['Default']
plist(runner_entitlements, existing)
plist(widget_entitlements, {'com.apple.security.application-groups' => [group_identifier]})
runner.build_configurations.each { |config| config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/CrispyRunner.entitlements' }
widget.build_configurations.each { |config| config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'RunnerCompanions/Widgets/CrispyWidgets.entitlements' }
# Both native implementations read/write the same App Group task snapshot.
# 1C8F.1 declares that local shared-defaults use; store privacy labels separately
# disclose optional account, photo, coach, purchase and analytics collection.
privacy_group = project.main_group.find_subpath('CrispyPrivacy', true)
[[runner, File.join(ios, 'Runner')], [widget, widget_dir]].each do |target, directory|
  manifest = File.join(directory, 'PrivacyInfo.xcprivacy')
  FileUtils.cp(File.join(mobile, 'native/apple/PrivacyInfo.xcprivacy'), manifest)
  relative = Pathname.new(manifest).relative_path_from(Pathname.new(project.project_dir)).to_s
  reference = privacy_group.files.find { |item| item.path == relative } || privacy_group.new_file(relative)
  unless target.resources_build_phase.files.any? { |item| item.file_ref == reference }
    target.resources_build_phase.add_file_reference(reference)
  end
end
[watch, widget].each do |target|
  target.build_configurations.each do |config|
    abort "Missing companion PRODUCT_NAME for #{target.name}/#{config.name}" if config.build_settings['PRODUCT_NAME'].to_s.empty?
  end
end
project.save
puts 'Embedded CrispyWatch and CrispyWidgets targets into Runner with explicit sources, plists, dependencies and copy phases.'
