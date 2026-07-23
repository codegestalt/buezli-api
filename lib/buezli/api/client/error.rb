module Buezli
  module Api
    class Client
      class Error < StandardError
        attr_reader :status, :code, :details, :response_body, :headers

        def initialize(response)
          if response.is_a?(String)
            @details = {}
            @headers = {}.with_indifferent_access
            return super(response)
          end

          @status = response.code.to_i
          @response_body = response.body.to_s
          @headers = response.each_header.to_h.with_indifferent_access
          parsed = parse_json(response_body)
          @code = parsed&.dig("error", "code")
          @details = parsed&.dig("error", "details") || {}
          message = parsed&.dig("error", "message") || response_body.presence ||
            "#{response.code} #{response.message}"

          super(message)
        end

        private

        def parse_json(body)
          JSON.parse(body)
        rescue JSON::ParserError, TypeError
          nil
        end
      end
    end
  end
end
