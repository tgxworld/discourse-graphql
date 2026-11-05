module DiscourseGraphQL
  module Types
    class SiteSettingChangeInput < BaseInputObject
      argument :name, String, required: true
      argument :value_wire, String, required: true
      argument :backfill,
               Boolean,
               required: false,
               default_value: false,
               replace_null_with_default: true
    end
  end
end
