module DiscourseGraphQL
  module Types
    class SiteSettingPlaceholderType < BaseObject
      field :text, String, null: true
      field :key, String, null: true
      field :value, String, null: true

      def text
        object if object.is_a?(String)
      end

      def key
        object["key"] if object.is_a?(Hash)
      end

      def value
        object["value"] if object.is_a?(Hash)
      end
    end
  end
end
