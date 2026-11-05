module DiscourseGraphQL
  module Chat
    class MessageCreation < ::Chat::Api::ChannelMessagesController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:create)
        payload = JSON.parse(response.body)
        successful = response.status.between?(200, 299)

        {
          status: successful ? "CREATED" : "FAILED",
          message_id: payload["message_id"],
          errors: successful ? [] : payload.fetch("errors").map { |message| user_error(message: message, payload: payload) },
        }
      end

      private

      def user_error(message:, payload:)
        code =
          if payload["error_type"] == "not_logged_in"
            "UNAUTHENTICATED"
          else
            case response.status
            when 403
              "FORBIDDEN"
            when 404
              "NOT_FOUND"
            when 429
              "RATE_LIMITED"
            when 500..599
              "UNAVAILABLE"
            else
              "BAD_USER_INPUT"
            end
          end

        {
          code: code,
          message: message,
          retry_after_seconds: payload.dig("extras", "wait_seconds"),
        }
      end
    end
  end
end
