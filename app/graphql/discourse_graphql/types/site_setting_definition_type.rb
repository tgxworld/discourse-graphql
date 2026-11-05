module DiscourseGraphQL
  module Types
    class SiteSettingDefinitionType < BaseObject
      field :name, String, null: false, hash_key: "setting"
      field :display_name, String, null: true, hash_key: "humanized_name"
      field :type, String, null: true, hash_key: "type"
      field :category, String, null: true, hash_key: "category"
      field :primary_area, String, null: true, hash_key: "primary_area"
      field :plugin, String, null: true, hash_key: "plugin"
      field :description, String, null: true, hash_key: "description"
      field :value_wire, String, null: true, hash_key: "value"
      field :default_wire, String, null: true, hash_key: "default"
      field :secret, Boolean, null: true, hash_key: "secret"
      field :themeable, Boolean, null: true, hash_key: "themeable"
      field :keywords, [String, null: true], null: true, complexity: 100
      field :preview, String, null: true, hash_key: "preview"
      field :textarea, Boolean, null: true, hash_key: "textarea"
      field :disabled, Boolean, null: true, hash_key: "disabled"
      field :allow_any, Boolean, null: true, hash_key: "allow_any"
      field :list_type, String, null: true, hash_key: "list_type"
      field :translate_names, Boolean, null: true, hash_key: "translate_names"
      field :minimum, GraphQL::Types::BigInt, null: true, hash_key: "min"
      field :maximum, GraphQL::Types::BigInt, null: true, hash_key: "max"
      field :mandatory_values_wire, String, null: true, hash_key: "mandatory_values"
      field :disallowed_groups_wire, String, null: true, hash_key: "disallowed_groups"
      field :requires_confirmation, String, null: true, hash_key: "requires_confirmation"
      field :depends_behavior, String, null: true, hash_key: "depends_behavior"
      field :dependent_setting_display, String, null: true, hash_key: "dependent_setting_display"
      field :authorized_extensions, String, null: true, hash_key: "authorized_extensions"
      field :max_file_size_kb, GraphQL::Types::BigInt, null: true, hash_key: "max_file_size_kb"
      field :placeholder, SiteSettingPlaceholderType, null: true, hash_key: "placeholder"
      field :upload, SiteSettingUploadType, null: true, hash_key: "upload"
      field :default_override,
            SiteSettingDefaultOverrideType,
            null: true,
            hash_key: "upcoming_change_default_override_metadata"
      field :object_schema, SiteSettingObjectSchemaType, null: true, hash_key: "schema"
      field :json_schema, SiteSettingJsonSchemaType, null: true, hash_key: "json_schema"
      field :choices, SiteSettingChoicePageType, null: true, extras: [:lookahead] do
        argument :first,
                 Integer,
                 required: false,
                 default_value: 25,
                 replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child) { 100 + arguments[:first].clamp(1, 100) * child }
      end
      field :valid_values, SiteSettingChoicePageType, null: true, extras: [:lookahead] do
        argument :first,
                 Integer,
                 required: false,
                 default_value: 25,
                 replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child) { 100 + arguments[:first].clamp(1, 100) * child }
      end
      field :dependencies, SiteSettingDependencyPageType, null: true, extras: [:lookahead] do
        argument :first,
                 Integer,
                 required: false,
                 default_value: 25,
                 replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child) { 100 + arguments[:first].clamp(1, 100) * child }
      end

      def keywords
        SiteSettingMetadataValues.list(object["keywords"])
      end

      def choices(first:, lookahead:, after: nil)
        NativeArrayPage.call(
          source: object["choices"],
          kind: "choices",
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
        )
      end

      def valid_values(first:, lookahead:, after: nil)
        NativeArrayPage.call(
          source: object["valid_values"],
          kind: "valid_values",
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
        )
      end

      def dependencies(first:, lookahead:, after: nil)
        source = object["depends_on"]
        values = nil
        if source
          cache = context.namespace(:site_setting_dependency_descriptors).compare_by_identity
          values =
            cache[object] ||= source.each_with_index.map do |name, index|
              {
                name: name,
                display_name: object["depends_on_humanized_names"]&.[](index),
                allowed_values: object["depends_on_values"]&.[](name),
              }
            end
        end
        NativeArrayPage.call(
          source: values,
          kind: "dependencies",
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
        )
      end
    end
  end
end
