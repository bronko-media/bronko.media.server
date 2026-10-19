# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

class EntrypointTest < Minitest::Test
  def test_migration_failure_prevents_server_start
    Dir.mktmpdir do |directory|
      bundle = File.join(directory, 'bundle')
      File.write(bundle, "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$CALLS\"\nexit 42\n")
      FileUtils.chmod(0o755, bundle)
      calls = File.join(directory, 'calls')
      _output, status = Open3.capture2e({ 'PATH' => "#{directory}:#{ENV.fetch('PATH')}", 'CALLS' => calls,
                                          'PUMA_RUN_DIR' => File.join(directory, 'puma') },
                                        File.expand_path('../entry.sh', __dir__), chdir: directory)
      assert_equal 42, status.exitstatus
      assert_equal "exec rake db:migrate\n", File.read(calls)
    end
  end

  def test_custom_command_replaces_entrypoint_without_running_migrations
    output, status = Open3.capture2e(File.expand_path('../entry.sh', __dir__), 'printf', 'custom command')
    assert status.success?
    assert_equal 'custom command', output
  end
end
