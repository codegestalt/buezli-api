module Buezli
  module Api
    class Client
      class Download
        attr_reader :body, :filename, :content_type, :headers

        def initialize(body:, filename:, content_type:, headers:)
          @body = body
          @filename = filename
          @content_type = content_type
          @headers = headers
        end
      end
    end
  end
end
