# frozen_string_literal: true

require 'config'
require 'digest'
require 'fileutils'
require 'logger'
require 'mini_magick'
require 'parallel'
require 'sinatra/activerecord'
require 'streamio-ffmpeg'
require 'yaml'
require 'faraday'
require 'json'
require 'wikipedia'

require_relative 'lib/helpers'
require_relative 'lib/models'

Config.load_and_set_settings("#{File.dirname(__FILE__)}/config/settings.yml")

def logger
  @logger ||= Logger.new($stdout)
end
