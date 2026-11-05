module DiscourseGraphQL
  module Chat
    class StarChannel < ::Chat::Api::ChannelsCurrentUserMembershipController
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
