module DiscourseGraphQL
  module Types
    class SiteSettingJsonPropertyPageType < BaseObject
      field :nodes, [SiteSettingJsonPropertyType], null: false
      field :total_count, Integer, null: false
      field :page_info, PageInfoType, null: false
    end
  end
end
