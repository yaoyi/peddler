# frozen_string_literal: true

require 'http'
require 'forwardable'
require 'peddler/jeff'
require 'peddler/errors/builder'
require 'peddler/marketplace'
require 'peddler/operation'
require 'peddler/parser'

class CustomError < HTTP::StateError
  attr_reader :response

  def initialize(response)
    @response = response
  end
end

module Peddler
  # An abstract client
  #
  # Subclass this to implement an MWS API section.
  class Client
    extend Forwardable
    include Jeff

    class << self
      # @api private
      attr_accessor :parser, :path, :version

      private

      def inherited(base)
        base.parser = parser
        base.params params
      end
    end

    params 'SellerId' => -> { merchant_id },
           'MWSAuthToken' => -> { auth_token },
           'Version' => -> { version }
    self.parser = Parser

    def_delegators :marketplace, :host, :encoding
    def_delegators :'self.class', :parser, :version

    # Creates a new client
    # @param [Hash] opts
    # @option opts [String] :aws_access_key_id
    # @option opts [String] :aws_secret_access_key
    # @option opts [String, Peddler::Marketplace] :marketplace
    # @option opts [String] :merchant_id
    # @option opts [String] :auth_token
    def initialize(opts = {})
      opts.each { |k, v| send("#{k}=", v) }
    end

    # The MWS Auth Token for a seller's account
    # @note You can omit this if you are accessing your own seller account
    # @return [String]
    attr_accessor :auth_token

    # The seller's Merchant ID
    # @return [String]
    attr_accessor :merchant_id

    # The marketplace where you signed up as application developer
    # @note You can pass the two-letter country code of the marketplace as
    #   shorthand when setting
    # @return [Peddler::Marketplace]
    attr_reader :marketplace

    # @!parse attr_writer :marketplace
    def marketplace=(marketplace)
      @marketplace =
        if marketplace.is_a?(Marketplace)
          marketplace
        else
          Marketplace.find(marketplace)
        end
    end

    # The body of the HTTP request
    # @return [String]
    attr_reader :body

    # @!parse attr_writer :body
    def body=(str)
      str ? add_content(str) : clear_content!
    end

    # @api private
    attr_writer :path

    # @api private
    def path
      @path ||= self.class.path
    end

    # @api private
    def defaults
      @defaults ||= {}
    end

    # @api private
    def headers
      @headers ||= {}
    end

    # @api private
    def aws_endpoint
      "https://#{host}#{path}"
    end

    # @api private
    def operation(action = nil)
      action ? @operation = Operation.new(action) : @operation
    end

    # @api private
    def run
      opts = build_options
      res = post(opts)
      self.body = nil if res.status == 200
      raise CustomError.new(res) if res.status != 200
      return yield(res) if block_given?
      parser.new(res, encoding)
    rescue CustomError => e
      handle_http_status_error(e)
    end

    private

    def clear_content!
      headers.delete('Content-Type')
      @body = nil
    end

    def add_content(content)
      if content.start_with?('<?xml')
        headers['Content-Type'] = 'text/xml'
        @body = content
      else
        headers['Content-Type'] =
          "text/tab-separated-values; charset=#{encoding}"
        @body = content.encode(encoding)
      end
    end

    def extract_options(args)
      args.last.is_a?(Hash) ? args.pop : {}
    end

    def build_options
      opts = defaults.merge(query: operation, headers: headers)
      body ? opts.update(body: body) : opts
    end

    def handle_http_status_error(error)
      new_error = Errors::Builder.call(error)
      raise new_error || error
    end
  end
end
