module DiscourseGraphQL
  module Chat
    class MarkAllRead < ::Chat::Api::ChannelsReadController
      include NativeRequest
      include MembershipResult

      def call(parameters:, fields:)
        @membership_fields = fields
        self.params = ActionController::Parameters.new(parameters)
        process(:update_all)
        membership_result
      end
    end
  end
end
