module DiscourseGraphQL
  module Types
    class SiteSettingJsonSchemaType < BaseObject
      field :type, String, null: true, hash_key: "type"
      field :title, String, null: true, hash_key: "title"
      field :description, String, null: true, hash_key: "description"
      field :format, String, null: true, hash_key: "format"
      field :unique_items, Boolean, null: true, hash_key: "uniqueItems"
      field :items, self, null: true, hash_key: "items"
      field :required, [String, null: true], null: true, complexity: 100
      field :enum_values_wire, [String, null: true], null: true, complexity: 100
      field :default_wire, String, null: true
      field :properties, SiteSettingJsonPropertyPageType, null: true, extras: [:lookahead] do
        argument :first, Integer, required: false, default_value: 25, replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child) { 100 + arguments[:first].clamp(1, 100) * child }
      end

      def required
        SiteSettingMetadataValues.list(object["required"])
      end

      def enum_values_wire
        SiteSettingMetadataValues.list(object["enum"])
      end

      def default_wire
        SiteSettingMetadataValues.wire(object["default"])
      end

      def properties(first:, lookahead:, after: nil)
        SiteSettingMetadataPage.call(source: object["properties"], kind: "json_properties", context: context, lookahead: lookahead, first: first, after: after)
      end
    end
  end
end
