# Flutter's embedding scripts consume Runner.app/Info.plist. Extension/watch
# copies must precede those scripts or Xcode's dependency graph forms a cycle.
# See https://docs.flutter.dev/platform-integration/ios/app-extensions
def companion_phase_name(phase)
  if phase.respond_to?(:name) && !phase.name.to_s.empty?
    phase.name.to_s
  elsif phase.respond_to?(:display_name)
    phase.display_name.to_s
  else
    ''
  end
end

def order_companion_embed_phases(runner)
  names = ['Embed Crispy Widgets', 'Embed Crispy Watch']
  phases = names.map { |name| runner.build_phases.find { |phase| companion_phase_name(phase) == name } }
  raise 'Both companion embed phases must exist before ordering.' if phases.any?(&:nil?)
  phases.each { |phase| runner.build_phases.delete(phase) }
  flutter_script = runner.build_phases.find do |phase|
    ['Run Script', 'Thin Binary'].include?(companion_phase_name(phase)) ||
      (phase.respond_to?(:shell_script) && phase.shell_script.to_s.include?('xcode_backend.sh'))
  end
  raise 'Flutter build/embed script not found; refusing an ambiguous phase order.' unless flutter_script
  index = runner.build_phases.index(flutter_script)
  phases.each_with_index { |phase, offset| runner.build_phases.insert(index + offset, phase) }
  unless phases.all? { |phase| runner.build_phases.index(phase) < runner.build_phases.index(flutter_script) }
    raise 'Companion copy phases must precede Flutter scripts.'
  end
end
