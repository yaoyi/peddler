# frozen_string_literal: true

# Keep SimpleCov at top.
require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
end

require 'minitest/autorun'
require 'minitest/focus'
require 'webmock/minitest'
begin
  require 'pry'
rescue LoadError
  nil
end
