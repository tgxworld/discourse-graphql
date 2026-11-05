module DiscourseGraphQL
  module SiteSettingMutationFields
    def self.included(type)
      type.field :update_site_settings,
                 Types::ActionPayloadType,
                 null: true,
                 native_archive_action: [::Admin::SiteSettingsController, :update] do
        argument :changes, [Types::SiteSettingChangeInput], required: true
        complexity ->(_context, arguments, child) do
                     2000 + arguments[:changes].size.clamp(0, 50) * 20 + child
                   end
      end
    end

    def update_site_settings(changes:)
      values = changes.map(&:to_h)
      if !values.size.between?(1, 50) ||
           values.map { |value| value[:name] }.uniq.size != values.size
        raise Discourse::InvalidParameters
      end
      values.each { |value| SiteSettingParameters.validate_name!(value[:name]) }
      context.dataloader.clear_cache
      SiteSettingChanges.new(request: context[:request], request_method: "PUT").call(
        changes: values,
      )
    ensure
      context.dataloader.clear_cache
    end
  end
end
