module Buezli
  module Api
    class Client
      class Record
        attr_reader :raw_attributes, :model_name, :client, :schema

        def initialize(attributes:, model_name:, client:, schema:)
          @raw_attributes = (attributes || {}).with_indifferent_access
          @model_name = model_name
          @client = client
          @schema = schema
        end

        def id
          raw_attributes[:id]
        end

        def deleted?
          raw_attributes[:_deleted] == true
        end

        def [](key)
          raw_attributes[key]
        end

        def to_h
          raw_attributes.to_h
        end

        def method_missing(method, *args, &block)
          return super unless args.empty? && block.nil? && schema.declared_field?(model_name, method)

          read_value(method.to_s)
        end

        def respond_to_missing?(method, include_private = false)
          schema.declared_field?(model_name, method) || super
        end

        private

        def read_value(name)
          value = raw_attributes[name]
          return build_association(name, value) if schema.association?(model_name, name)

          case schema.attribute_type(model_name, name).to_s
          when "datetime" then parse_time(value)
          when "date" then parse_date(value)
          else value
          end
        end

        def build_association(name, value)
          return if value.nil?

          target_model = schema.association_class_name(model_name, name)
          if schema.association_collection?(model_name, name)
            Array(value).map { |attributes| client.build_record(target_model, attributes) }
          else
            client.build_record(target_model, value)
          end
        end

        def parse_time(value)
          Time.parse(value.to_s) if value.present?
        rescue ArgumentError
          value
        end

        def parse_date(value)
          Date.parse(value.to_s) if value.present?
        rescue Date::Error
          value
        end
      end
    end
  end
end
