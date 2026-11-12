module Buezli
  module Api
    class Client
      DEFAULT_ENDPOINT = "https://api.buezli.app"

      attr_reader :access_token, :endpoint, :version, :schema, :host

      def initialize(access_token:, endpoint: DEFAULT_ENDPOINT, version: nil, schema: nil, host: nil)
        @access_token = access_token
        @endpoint = endpoint.chomp("/")
        @schema = schema || load_schema(version)
        @version = version || @schema.version
        @host = host
        raise ArgumentError, "Schema version does not match requested version" if @schema.version != @version

        define_methods_from_schema
      end

      def build_record(model_name, attributes)
        Record.new(attributes:, model_name:, api_client: self, schema:)
      end

      def inspect
        "#<#{self.class.name} endpoint=#{endpoint.inspect} version=#{version.inspect} host=#{host.inspect}>"
      end

      private

      def load_schema(version)
        requested_version = version || latest_schema_version
        Schema.load(schema_directory.join("#{requested_version}.json"))
      end

      def schema_directory
        Pathname(__dir__).join("../../../schemas").expand_path
      end

      def latest_schema_version
        schema_directory.glob("*.json").map { |path| path.basename(".json").to_s }.max ||
          raise(ArgumentError, "No bundled API schemas found")
      end

      def define_methods_from_schema
        schema.endpoints.each do |resource, endpoints|
          # The client reads; write endpoints have no generated methods.
          endpoints.select { |endpoint_config| endpoint_config.fetch("verb") == "GET" }.each do |endpoint_config|
            define_singleton_method(method_name_for(resource, endpoint_config.fetch("action"))) do |*path_values, **params|
              perform_endpoint(resource, endpoint_config, path_values, params)
            end
          end
        end
      end

      def method_name_for(resource, action)
        return "retrieve_#{resource}" if action == "index"
        return "retrieve_#{resource.singularize}" if action == "show"

        "retrieve_#{resource.singularize}_#{action}"
      end

      def perform_endpoint(resource, endpoint_config, path_values, params)
        path = endpoint_config.fetch("path").dup
        query = params.with_indifferent_access

        path.scan(/:(\w+)/).flatten.each do |key|
          value = query.delete(key) || path_values.shift
          raise ArgumentError, "Missing required path parameter: #{key}" if value.nil?

          path.sub!(":#{key}", value.to_s)
        end
        raise ArgumentError, "Too many path parameters" if path_values.any?

        perform_request(
          resource:,
          action: endpoint_config.fetch("action"),
          verb: endpoint_config.fetch("verb"),
          path:,
          params: query
        )
      end

      def perform_request(resource:, action:, verb:, path:, params:)
        raise ArgumentError, "Unsupported API verb: #{verb}" unless verb == "GET"

        uri = URI("#{endpoint}#{path}")
        uri.query = encode_query(params) if params.present?
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Accept"] = "application/json, */*"
        request["Host"] = host if host

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(request)
        end
        raise Error.new(response) unless response.is_a?(Net::HTTPSuccess)

        parse_response(
          response,
          resource:,
          request_context: { resource:, action:, verb:, path:, params: params.dup }
        )
      end

      def parse_response(response, resource:, request_context:)
        content_type = response["Content-Type"].to_s.split(";").first
        return build_download(response) unless content_type == "application/json" || content_type.end_with?("+json")

        payload = JSON.parse(response.body)
        return Schema.new(payload) if resource == "schema"

        data = payload.key?("data") ? payload["data"] : payload
        model_name = schema.model_name_for_resource(resource)
        return payload unless model_name

        if data.is_a?(Array)
          List.new(
            data: data.map { |attributes| build_record(model_name, attributes) },
            meta: payload["meta"],
            client: self,
            request_context:
          )
        elsif data.is_a?(Hash)
          build_record(model_name, data)
        else
          data
        end
      end

      def build_download(response)
        headers = response.each_header.to_h.with_indifferent_access
        Download.new(
          body: response.body,
          filename: response_filename(response["Content-Disposition"]),
          content_type: response["Content-Type"].to_s.split(";").first,
          headers:
        )
      end

      def response_filename(disposition)
        encoded = disposition.to_s[/filename\*=(?:UTF-8'')?([^;]+)/i, 1]
        return URI.decode_www_form_component(encoded.delete_prefix('"').delete_suffix('"')) if encoded

        disposition.to_s[/filename="([^"]+)"/i, 1] ||
          disposition.to_s[/filename=([^;]+)/i, 1]&.strip
      end

      def encode_query(params, prefix = nil)
        params.flat_map do |key, value|
          full_key = prefix ? "#{prefix}[#{key}]" : key.to_s
          if value.is_a?(Hash)
            encode_query(value, full_key)
          elsif value.is_a?(Array)
            value.map { |item| encoded_pair("#{full_key}[]", item) }
          else
            encoded_pair(full_key, value)
          end
        end.join("&")
      end

      def encoded_pair(key, value)
        encoded_value = case value
        when Time, Date then value.iso8601
        else value.to_s
        end
        "#{URI.encode_www_form_component(key)}=#{URI.encode_www_form_component(encoded_value)}"
      end
    end
  end
end
