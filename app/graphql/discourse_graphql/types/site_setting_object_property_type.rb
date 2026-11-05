module DiscourseGraphQL
  module Types
    class SiteSettingObjectPropertyType < BaseObject
      field :name, String, null: false
      field :definition, SiteSettingObjectPropertyDefinitionType, null: true

      def name
        object.first
      end

      def definition
        object.last
      end
    end
  end
end
