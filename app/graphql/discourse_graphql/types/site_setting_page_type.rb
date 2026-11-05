module DiscourseGraphQL
  module Types
    class SiteSettingPageType < BaseObject
      field :nodes, [SiteSettingDefinitionType], null: false
      field :page_info, PageInfoType, null: false
    end
  end
end
