module DiscourseGraphQL
  module Types
    class SiteSettingDependencyType < BaseObject
      field :name, String, null: false
      field :display_name, String, null: true
      field :allowed_values_wire, [String, null: true], null: true, complexity: 100

      def allowed_values_wire
        SiteSettingMetadataValues.list(object[:allowed_values])
      end
    end
  end
end
