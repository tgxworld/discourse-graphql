module DiscourseGraphQL
  module Types
    class SiteSettingJsonPropertyType < BaseObject
      field :name, String, null: false
      field :definition, "DiscourseGraphQL::Types::SiteSettingJsonSchemaType", null: true

      def name
        object.first
      end

      def definition
        object.last
      end
    end
  end
end
