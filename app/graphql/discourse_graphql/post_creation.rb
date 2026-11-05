module DiscourseGraphQL
  class PostCreation < ::PostsController
    skip_before_action :clear_notifications
    skip_after_action :perform_refresh_session

    def self.requires_login_arg
      superclass.requires_login_arg
    end

    def initialize(request:)
      super()
      set_request!(ActionDispatch::Request.new(request.env.dup))
      set_response!(ActionDispatch::Response.new)
      self.request.format = :json
    end

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters.merge(nested_post: true))
      process(:create)
      payload = JSON.parse(response.body)
      successful = response.status.between?(200, 299)
      status =
        if !successful
          "FAILED"
        elsif payload["action"] == "enqueued"
          "PENDING"
        elsif payload.dig("post", "id")
          "PUBLISHED"
        else
          "HANDLED"
        end

      {
        status: status,
        action: payload["action"],
        post_id: payload.dig("post", "id"),
        pending_count: payload["pending_count"],
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
