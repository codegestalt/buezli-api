module Buezli
  module Api
    class Client
      class List
        include Enumerable

        attr_reader :data, :meta

        def initialize(data:, meta:, client:, request_context:)
          @data = data
          @meta = (meta || {}).with_indifferent_access
          @client = client
          @request_context = request_context
        end

        def each(&block)
          data.each(&block)
        end

        def empty?
          data.empty?
        end

        def size
          data.size
        end

        alias length size

        def [](index)
          data[index]
        end

        def pagination
          meta.fetch(:pagination, {})
        end

        def next_page
          request_page(pagination[:next])
        end

        def previous_page
          request_page(pagination[:prev])
        end

        private

        def request_page(page)
          return if page.nil?

          current_page = pagination[:page] || @request_context[:params][:page]
          raise Error, "Infinite pagination loop detected" if current_page.to_s == page.to_s

          params = @request_context[:params].merge(page:)
          @client.send(:perform_request, **@request_context.merge(params:))
        end
      end
    end
  end
end
