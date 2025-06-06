# frozen_string_literal: true

require 'sinatra/activerecord/rake'
require './app'

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:rubocop) do |t|
    t.formatters = ['simple']
    t.options = ['--display-cop-names']
  end
rescue LoadError
  # rubocop isn't available, so we won't define a rake task with it
end

begin
  require 'rubygems'
  require 'github_changelog_generator/task'
rescue LoadError
  # github_changelog_generator isn't available, so we won't define a rake task with it
else
  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    config.header = "# Changelog\n\nAll notable changes to this project will be documented in this file."
    config.exclude_labels = %w[duplicate question invalid wontfix wont-fix skip-changelog]
    config.user = 'bronko-media'
    config.project = 'bronko.media.server'
    # get branch name from git and strip off any prefixes (e.g. 'release-')
    config.future_release = `git rev-parse --abbrev-ref HEAD`.strip.split('-', 2).last
  end
end
