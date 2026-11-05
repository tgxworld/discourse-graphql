module DiscourseGraphQL
  class SiteSettingUserCount < SiteSettingRequest
    def call(name:, value_wire:)
      prepare_native_action(parameters: { name => value_wire }, action: :user_count, path: "/admin/site_settings/#{ERB::Util.url_encode(name)}/user_count.json", route_parameters: { site_setting_id: name })
      process(:user_count)
      result = NativeResponse.new(response)
      result.raise_error!
      result.payload["user_count"]
    end
  end
end
