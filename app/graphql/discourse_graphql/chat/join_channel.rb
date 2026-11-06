module DiscourseGraphQL
  module Chat
    class JoinChannel < ::Chat::Api::ChannelsCurrentUserMembershipController
      include NativeRequest
      include MembershipResult

      def call(parameters:, fields:)
        @membership_fields = fields
        self.params = ActionController::Parameters.new(parameters)
        process(:create)
        membership_result
      end
    end
  end
end
