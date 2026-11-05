module DiscourseGraphQL
  module Types
    class SiteSettingChoiceType < BaseObject
      field :name, String, null: true
      field :value_wire, String, null: true
      field :native_name, String, null: true
      field :id, String, null: true

      def name
        SiteSettingMetadataValues.wire(object.is_a?(Hash) ? object["name"] : object)
      end

      def value_wire
        SiteSettingMetadataValues.wire(object.is_a?(Hash) ? object["value"] : object)
      end

      def native_name
        object["native_name"] if object.is_a?(Hash)
      end

      def id
        SiteSettingMetadataValues.wire(object["id"]) if object.is_a?(Hash)
      end
    end
  end
end
