module DiscourseGraphQL
  class PostCreation < ::PostsController
    include NativeRequest

    def self.requires_login_arg
      superclass.requires_login_arg
    end

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters.merge(nested_post: true))
      process(:create)
      result = NativeResponse.new(response)
      payload = result.payload
      successful = result.successful?
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
        errors: result.errors,
      }
    end
  end
end
