module DiscourseGraphQL
  module Types
    class SiteSettingObjectPropertyDefinitionType < BaseObject
      field :type, String, null: true, hash_key: "type"
      field :required, Boolean, null: true, hash_key: "required"
      field :textarea, Boolean, null: true, hash_key: "textarea"
      field :validations, SiteSettingObjectValidationsType, null: true, hash_key: "validations"
    end
  end
end
