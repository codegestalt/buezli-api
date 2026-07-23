module Buezli
  module Api
    class Schema
      attr_reader :version, :config

      def self.load(path)
        new(JSON.parse(Pathname(path).read))
      end

      def initialize(config)
        @config = config.with_indifferent_access
        @version = @config.fetch(:version)
      end

      def endpoints
        config.fetch(:endpoints, {})
      end

      def for(model_name)
        config.dig(:models, model_name.to_s)
      end

      def model_name_for_resource(resource_name)
        config.fetch(:models).find do |_model_name, model|
          model[:resource_name] == resource_name.to_s
        end&.first
      end

      def declared_field?(model_name, field_name)
        model = self.for(model_name)
        model&.fetch(:attributes, {})&.key?(field_name.to_s) ||
          model&.fetch(:associations, {})&.key?(field_name.to_s)
      end

      def attribute_type(model_name, attribute)
        self.for(model_name)&.dig(:attributes, attribute.to_s)
      end

      def association?(model_name, association)
        self.for(model_name)&.fetch(:associations, {})&.key?(association.to_s)
      end

      def association_metadata(model_name, association)
        self.for(model_name)&.dig(:associations, association.to_s) || {}.with_indifferent_access
      end

      def association_class_name(model_name, association)
        association_metadata(model_name, association)[:class_name] ||
          association.to_s.singularize.classify
      end

      def association_collection?(model_name, association)
        association_metadata(model_name, association)[:type].to_s.include?("many")
      end
    end
  end
end
