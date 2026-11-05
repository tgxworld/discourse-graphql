module DiscourseGraphQL
  class SiteSettingChanges < SiteSettingRequest
    def call(changes:)
      settings =
        changes.to_h do |change|
          [change.fetch(:name), { value: change.fetch(:value_wire), backfill: change[:backfill] }]
        end
      prepare_native_action(
        parameters: {
          settings: settings,
        },
        action: :update,
        path: "/admin/site_settings/bulk_update.json",
        route_parameters: {
          id: "bulk_update",
        },
      )
      process(:update)
      NativeResponse.new(response).action_payload
    end
  end
end
