module DiscourseGraphQL
  module Types
    class SiteSettingObjectPropertyPageType < BaseObject
      field :nodes, [SiteSettingObjectPropertyType], null: false
      field :total_count, Integer, null: false
      field :page_info, PageInfoType, null: false
    end
  end
end
