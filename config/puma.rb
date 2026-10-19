# frozen_string_literal: true

root = Dir.getwd

run_directory = ENV.fetch('PUMA_RUN_DIR', "#{root}/tmp/puma")
pidfile "#{run_directory}/pid"
state_path "#{run_directory}/state"
rackup "#{root}/config.ru"
