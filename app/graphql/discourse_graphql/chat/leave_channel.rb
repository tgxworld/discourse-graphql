module DiscourseGraphQL
  module Chat
    class LeaveChannel < ::Chat::Api::ChannelsCurrentUserMembershipController
      include NativeRequest
      include MembershipResult

      def call(parameters:, fields:)
        @membership_fields = fields
        self.params = ActionController::Parameters.new(parameters)
        process(:destroy)
        membership_result
      end
    end
  end
end
