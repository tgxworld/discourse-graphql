module DiscourseGraphQL
  module SiteSettingQueryFields
    def self.included(type)
      type.field :admin_site_settings, Types::SiteSettingPageType, null: true do
        argument :first, Integer, required: false, default_value: 25, replace_null_with_default: true
        argument :after, String, required: false
        argument :names, [String], required: false
        argument :categories, [String], required: false
        argument :plugin, String, required: false
        complexity ->(_context, arguments, child) { 4000 + arguments[:first].clamp(1, 100) * child }
      end
      type.field :admin_site_setting, Types::SiteSettingDefinitionType, null: true, complexity: 4000 do
        argument :name, String, required: true
      end
      type.field :site_setting_affected_user_count, GraphQL::Types::BigInt, null: true, complexity: 1000 do
        argument :name, String, required: true
        argument :value_wire, String, required: true
      end
    end

    def admin_site_settings(first:, after: nil, names: nil, categories: nil, plugin: nil)
      SiteSettingParameters.validate_filters!(names: names, categories: categories, plugin: plugin)
      SiteSettingList.new(request: context[:request], request_method: "GET").call(first: first, after: after, names: names, categories: categories, plugin: plugin)
    end

    def admin_site_setting(name:)
      SiteSettingParameters.validate_name!(name)
      result = SiteSettingList.new(request: context[:request], request_method: "GET").call(first: 100, names: [name])
      result.fetch(:nodes).find { |setting| setting["setting"] == name }
    end

    def site_setting_affected_user_count(name:, value_wire:)
      SiteSettingParameters.validate_name!(name)
      SiteSettingUserCount.new(request: context[:request], request_method: "PUT").call(name: name, value_wire: value_wire)
    end
  end
end
