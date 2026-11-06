module DiscourseGraphQL
  module Types
    class SiteSettingDefaultOverrideType < BaseObject
      field :old_default, String, null: true, hash_key: "old_default"
      field :new_default, String, null: true, hash_key: "new_default"
      field :change_setting_name, String, null: true, hash_key: "change_setting_name"
    end
  end
end
