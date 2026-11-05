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
    end
  end
end
