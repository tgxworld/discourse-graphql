module DiscourseGraphQL
  module Types
    class SiteSettingChoicePageType < BaseObject
      field :nodes, [SiteSettingChoiceType], null: false
      field :total_count, Integer, null: false
      field :page_info, PageInfoType, null: false
    end
  end
end
