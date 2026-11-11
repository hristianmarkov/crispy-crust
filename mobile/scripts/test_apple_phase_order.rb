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
