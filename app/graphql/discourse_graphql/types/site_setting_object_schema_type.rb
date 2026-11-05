module DiscourseGraphQL
  module Types
    class SiteSettingObjectSchemaType < BaseObject
      field :name, String, null: true, hash_key: "name"
      field :identifier, String, null: true, hash_key: "identifier"
      field :properties, SiteSettingObjectPropertyPageType, null: true, extras: [:lookahead] do
        argument :first,
                 Integer,
                 required: false,
                 default_value: 25,
                 replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child) { 100 + arguments[:first].clamp(1, 100) * child }
      end

      def properties(first:, lookahead:, after: nil)
        NativeArrayPage.call(
          source: object["properties"],
          kind: "object_properties",
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
        )
      end
    end
  end
end
