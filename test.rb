# frozen_string_literal: true

Dir[File.join(__dir__, 'test', '*_test.rb')].each { |file| require file }
