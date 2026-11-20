#!/usr/bin/env ruby
# Runs only on a trusted macOS release runner after importing the signing material.
require 'json'
require 'xcodeproj'

manifest = JSON.parse(File.read(ENV.fetch('CRISPY_IOS_PROFILE_MANIFEST')))
team = '6X9UVM8P4G'
targets = {
  'Runner' => 'app.crispycrust.mobile',
  'CrispyWatch' => 'app.crispycrust.mobile.watch',
  'CrispyWidgets' => 'app.crispycrust.mobile.widgets'
}
abort 'Unexpected profile bundle identifiers.' unless manifest.keys.sort == targets.values.sort
project = Xcodeproj::Project.open(File.expand_path('../apps/mobile/ios/Runner.xcodeproj', __dir__))
targets.each do |name, identifier|
  target = project.targets.find { |item| item.name == name }
  abort "Missing release target #{name}." unless target
  profile = manifest.fetch(identifier)
  abort "Unexpected signing team for #{identifier}." unless profile.fetch('team') == team
  target.build_configurations.each do |config|
    next unless %w[Release Profile].include?(config.name)
    config.build_settings.merge!({
      'DEVELOPMENT_TEAM' => team,
      'CODE_SIGN_STYLE' => 'Manual',
      'CODE_SIGN_IDENTITY' => 'Apple Distribution',
      'PROVISIONING_PROFILE_SPECIFIER' => profile.fetch('name'),
      'PROVISIONING_PROFILE' => profile.fetch('uuid')
    })
  end
end
project.save

export_options = {
  'method' => 'app-store-connect', 'teamID' => team,
  'signingStyle' => 'manual', 'signingCertificate' => 'Apple Distribution',
  'manageAppVersionAndBuildNumber' => false, 'uploadSymbols' => true,
  'provisioningProfiles' => manifest.transform_values { |profile| profile.fetch('name') }
}
Xcodeproj::Plist.write_to_path(export_options, ENV.fetch('CRISPY_IOS_EXPORT_OPTIONS'))
puts 'Configured manual App Store signing for phone, watch and widgets.'
