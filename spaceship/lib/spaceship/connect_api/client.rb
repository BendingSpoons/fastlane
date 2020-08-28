require_relative '../client'
require_relative './response'
require 'logger'

module Spaceship
  class ConnectAPI
    class Client < Spaceship::Client
      attr_accessor :token

      # Temporary global counters to debug 401 errors
      @@call_counters = {
        global: 0,
        get: 0,
        post: 0,
        patch: 0,
        delete: 0
      }

      #####################################################
      # @!group Client Init
      #####################################################

      # Instantiates a client with cookie session or a JWT token.
      def initialize(cookie: nil, current_team_id: nil, token: nil)
        if token.nil?
          super(cookie: cookie, current_team_id: current_team_id, timeout: 1200)
        else
          options = {
            request: {
              timeout:       (ENV["SPACESHIP_TIMEOUT"] || 300).to_i,
              open_timeout:  (ENV["SPACESHIP_TIMEOUT"] || 300).to_i
            }
          }
          @token = token
          @current_team_id = current_team_id

          hostname = "https://api.appstoreconnect.apple.com/v1/"

          @client = Faraday.new(hostname, options) do |c|
            c.response(:json, content_type: /\bjson$/)
            c.response(:plist, content_type: /\bplist$/)
            c.use(FaradayMiddleware::RelsMiddleware)
            c.adapter(Faraday.default_adapter)
            c.headers["Authorization"] = "Bearer #{token.text}"

            if ENV['SPACESHIP_DEBUG']
              # for debugging only
              # This enables tracking of networking requests using Charles Web Proxy
              c.proxy = "https://127.0.0.1:8888"
              c.ssl[:verify_mode] = OpenSSL::SSL::VERIFY_NONE
            elsif ENV["SPACESHIP_PROXY"]
              c.proxy = ENV["SPACESHIP_PROXY"]
              c.ssl[:verify_mode] = OpenSSL::SSL::VERIFY_NONE if ENV["SPACESHIP_PROXY_SSL_VERIFY_NONE"]
            end

            if ENV["DEBUG"]
              puts("To run spaceship through a local proxy, use SPACESHIP_DEBUG")
            end
          end
        end
      end

      def self.hostname
        return nil
      end

      #
      # Helpers
      #

      def web_session?
        return @token.nil?
      end

      def build_params(filter: nil, includes: nil, limit: nil, sort: nil, cursor: nil)
        params = {}

        filter = filter.delete_if { |k, v| v.nil? } if filter

        params[:filter] = filter if filter && !filter.empty?
        params[:include] = includes if includes
        params[:limit] = limit if limit
        params[:sort] = sort if sort
        params[:cursor] = cursor if cursor

        return params
      end

      def get(url_or_path, params = nil)
        handle_api_call_logging(url_or_path, :get)
        response = with_asc_retry do
          request(:get) do |req|
            req.url(url_or_path)
            req.options.params_encoder = Faraday::NestedParamsEncoder
            req.params = params if params
            req.headers['Content-Type'] = 'application/json'
          end
        end
        handle_response(response)
      end

      def post(url_or_path, body, tries: 5)
        handle_api_call_logging(url_or_path, :post)
        response = with_asc_retry(tries) do
          request(:post) do |req|
            req.url(url_or_path)
            req.body = body.to_json
            req.headers['Content-Type'] = 'application/json'
          end
        end
        handle_response(response)
      end

      def patch(url_or_path, body)
        handle_api_call_logging(url_or_path, :patch)
        response = with_asc_retry do
          request(:patch) do |req|
            req.url(url_or_path)
            req.body = body.to_json
            req.headers['Content-Type'] = 'application/json'
          end
        end
        handle_response(response)
      end

      def delete(url_or_path, params = nil, body = nil)
        handle_api_call_logging(url_or_path, :delete)
        response = with_asc_retry do
          request(:delete) do |req|
            req.url(url_or_path)
            req.options.params_encoder = Faraday::NestedParamsEncoder if params
            req.params = params if params
            req.body = body.to_json if body
            req.headers['Content-Type'] = 'application/json' if body
          end
        end
        handle_response(response)
      end

      protected

      def with_asc_retry(tries = 5, &_block)
        tries = 1 if Object.const_defined?("SpecHelper")
        logger.warn("Executing asc retry, current tries (decreasing) #{tries}")
        response = yield

        status = response.status if response

        if [500, 504].include?(status)
          msg = "Timeout received! Retrying after 3 seconds (remaining: #{tries})..."
          raise msg
        end

        return response
      rescue => error
        tries -= 1
        logger.warn(error) if Spaceship::Globals.verbose?
        if tries.zero?
          return response
        else
          retry
        end
      end

      def handle_response(response)
        raise UnexpectedResponse, "Unhandled exception during API call" if response.nil?

        if (200...300).cover?(response.status) && (response.body.nil? || response.body.empty?)
          return
        end

        raise InternalServerError, "Server error got #{response.status}" if (500...600).cover?(response.status)

        unless response.body.kind_of?(Hash)
          raise UnexpectedResponse, response.body
        end

        raise UnexpectedResponse, response.body['error'] if response.body['error']

        raise UnexpectedResponse, handle_errors(response) if response.body['errors']

        raise UnexpectedResponse, "Temporary App Store Connect error: #{response.body}" if response.body['statusCode'] == 'ERROR'

        return Spaceship::ConnectAPI::Response.new(body: response.body, status: response.status, client: self)
      end

      def handle_errors(response)
        # Example error format
        # {
        # "errors":[
        #     {
        #       "id":"cbfd8674-4802-4857-bfe8-444e1ea36e32",
        #       "status":"409",
        #       "code":"STATE_ERROR",
        #       "title":"The request cannot be fulfilled because of the state of another resource.",
        #       "detail":"Submit for review errors found.",
        #       "meta":{
        #           "associatedErrors":{
        #             "/v1/appScreenshots/":[
        #                 {
        #                   "id":"23d1734f-b81f-411a-98e4-6d3e763d54ed",
        #                   "status":"409",
        #                   "code":"STATE_ERROR.SCREENSHOT_REQUIRED.APP_WATCH_SERIES_4",
        #                   "title":"App screenshot missing (APP_WATCH_SERIES_4)."
        #                 },
        #                 {
        #                   "id":"db993030-0a93-48e9-9fd7-7e5676633431",
        #                   "status":"409",
        #                   "code":"STATE_ERROR.SCREENSHOT_REQUIRED.APP_WATCH_SERIES_4",
        #                   "title":"App screenshot missing (APP_WATCH_SERIES_4)."
        #                 }
        #             ],
        #             "/v1/builds/d710b6fa-5235-4fe4-b791-2b80d6818db0":[
        #                 {
        #                   "id":"e421fe6f-0e3b-464b-89dc-ba437e7bb77d",
        #                   "status":"409",
        #                   "code":"ENTITY_ERROR.ATTRIBUTE.REQUIRED",
        #                   "title":"The provided entity is missing a required attribute",
        #                   "detail":"You must provide a value for the attribute 'usesNonExemptEncryption' with this request",
        #                   "source":{
        #                       "pointer":"/data/attributes/usesNonExemptEncryption"
        #                   }
        #                 }
        #             ]
        #           }
        #       }
        #     }
        # ]
        # }

        return response.body['errors'].map do |error|
          messages = [[error['title'], error['detail']].compact.join(" - ")]

          meta = error["meta"] || {}
          associated_errors = meta["associatedErrors"] || {}

          messages + associated_errors.values.flatten.map do |associated_error|
            [[associated_error["title"], associated_error["detail"]].compact.join(" - ")]
          end
        end.flatten.join("\n")
      end

      private

      def local_variable_get(binding, name)
        if binding.respond_to?(:local_variable_get)
          binding.local_variable_get(name)
        else
          binding.eval(name.to_s)
        end
      end

      def provider_id
        return team_id if self.provider.nil?
        self.provider.provider_id
      end

      def handle_api_call_logging(url_or_path, method)
        @@call_counters[method] += 1
        @@call_counters[:global] += 1

        components = [
          "[BSP DEBUG] ConnectAPI:",
          "global call #{@@call_counters[:global]},",
          "#{method.to_s.upcase} count #{@@call_counters[method]}",
          "on url or path #{url_or_path}"
        ]
        logger.warn(components.join(" "))
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
