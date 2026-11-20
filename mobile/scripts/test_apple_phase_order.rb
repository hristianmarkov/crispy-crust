#!/usr/bin/env ruby
require_relative 'apple_phase_order'

Phase = Struct.new(:name, :shell_script)
RunnerFixture = Struct.new(:build_phases)

def assert(value, message)
  raise message unless value
end

# Reproduce the actual failing CI order, including both products.
original = ['[CP] Check Pods Manifest.lock', 'Run Script', 'Sources', 'Frameworks',
  'Resources', 'Embed Frameworks', 'Thin Binary', 'Embed Crispy Widgets',
  'Embed Crispy Watch', '[CP] Embed Pods Frameworks']
runner = RunnerFixture.new(original.map { |name| Phase.new(name, nil) })
unchanged = runner.build_phases.reject { |phase| phase.name.start_with?('Embed Crispy') }
order_companion_embed_phases(runner)
names = runner.build_phases.map(&:name)
assert(names.index('Embed Crispy Widgets') < names.index('Run Script'), 'Widget copy still follows Flutter build')
assert(names.index('Embed Crispy Watch') < names.index('Thin Binary'), 'Watch copy still follows Flutter thinning')
assert(runner.build_phases.reject { |phase| phase.name.start_with?('Embed Crispy') } == unchanged,
  'Ordering changed unrelated build phases')
first = runner.build_phases.dup
order_companion_embed_phases(runner)
assert(first == runner.build_phases, 'Ordering is not idempotent')

# Detect Flutter scripts by their content if a future generator renames them.
runner = RunnerFixture.new([Phase.new('Build Flutter', '/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" build'),
  Phase.new('Embed Crispy Watch', nil), Phase.new('Embed Crispy Widgets', nil)])
order_companion_embed_phases(runner)
assert(runner.build_phases.last.name == 'Build Flutter', 'Script-content detection failed')
puts 'Apple phase ordering passed: actual CI cycle fixture, unrelated order, idempotence and renamed-script detection.'


# Exercise the production xcodeproj object graph, not only Struct doubles.
# PBXSourcesBuildPhase/PBXFrameworksBuildPhase/PBXResourcesBuildPhase do not
# implement `name`; this is the exact CI7 bootstrap failure regression.
require 'xcodeproj'
require 'tmpdir'
Dir.mktmpdir('crispy-phase-test') do |directory|
  project_path = File.join(directory, 'Runner.xcodeproj')
  project = Xcodeproj::Project.new(project_path)
  target = project.new_target(:application, 'Runner', :ios, '15.0')
  assert(target.build_phases.any? { |phase| !phase.respond_to?(:name) },
    'Real fixture must include unnamed native build-phase objects')
  build_script = target.new_shell_script_build_phase('Run Script')
  build_script.shell_script = '/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" build'
  thin_script = target.new_shell_script_build_phase('Thin Binary')
  thin_script.shell_script = '/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" embed_and_thin'
  target.new_copy_files_build_phase('Embed Crispy Widgets')
  target.new_copy_files_build_phase('Embed Crispy Watch')
  unrelated = target.build_phases.reject { |phase| companion_phase_name(phase).start_with?('Embed Crispy') }.map(&:uuid)
  order_companion_embed_phases(target)
  first_order = target.build_phases.map(&:uuid)
  assert(target.build_phases.reject { |phase| companion_phase_name(phase).start_with?('Embed Crispy') }.map(&:uuid) == unrelated,
    'Real object ordering changed unrelated phases')
  assert(target.build_phases.index(target.copy_files_build_phases.find { |phase| phase.name == 'Embed Crispy Widgets' }) <
    target.build_phases.index(build_script), 'Real widget copy still follows Flutter script')
  order_companion_embed_phases(target)
  assert(target.build_phases.map(&:uuid) == first_order, 'Real object ordering is not idempotent')
  project.save
  reopened = Xcodeproj::Project.open(project_path).targets.find { |item| item.name == 'Runner' }
  assert(reopened.build_phases.map(&:uuid) == first_order, 'Serialized Xcode project lost phase order')
  order_companion_embed_phases(reopened)
  assert(reopened.build_phases.map(&:uuid) == first_order, 'Reopened project ordering is not idempotent')
end
puts 'Real xcodeproj object/serialization ordering regression passed.'
