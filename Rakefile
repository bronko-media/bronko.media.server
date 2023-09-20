# frozen_string_literal: true

require 'sinatra/activerecord/rake'
require 'rubocop/rake_task'
require './app'

RuboCop::RakeTask.new(:rubocop) do |t|
  t.formatters = ['simple']
  t.options = ['--display-cop-names']
end
