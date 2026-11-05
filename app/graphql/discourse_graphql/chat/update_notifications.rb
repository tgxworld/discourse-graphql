module DiscourseGraphQL
  module Chat
    class UpdateNotifications < ::Chat::Api::ChannelsCurrentUserNotificationsSettingsController
      include NativeRequest
      include MembershipResult

      def call(parameters:, fields:)
        @membership_fields = fields
        self.params = ActionController::Parameters.new(parameters)
        process(:update)
        membership_result
      end
    end
  end
end
