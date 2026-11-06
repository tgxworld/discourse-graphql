module DiscourseGraphQL
  module Types
    class SiteSettingDependencyPageType < BaseObject
      field :nodes, [SiteSettingDependencyType], null: false
      field :total_count, Integer, null: false
      field :page_info, PageInfoType, null: false
    end
  end
end
