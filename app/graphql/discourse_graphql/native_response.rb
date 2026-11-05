module DiscourseGraphQL
  class NativeResponse
    attr_reader :payload

    def initialize(response)
      @status = response.status
      @payload = response.body.blank? ? {} : JSON.parse(response.body)
    end

    def successful?
      @status.between?(200, 299)
    end

    def errors
      return [] if successful?

      messages = Array(payload["errors"]).presence || [I18n.t("discourse_graphql.errors.operation_failed")]
      messages.map do |message|
        { code: error_code, message: message.to_s, retry_after_seconds: payload.dig("extras", "wait_seconds"), description: payload.dig("extras", "description") }
      end
    end

    def action_payload
      { success: successful?, errors: errors }
    end

    def raise_error!
      return if successful?

      error = errors.first
      extensions = { code: error.fetch(:code) }
      extensions[:retryAfterSeconds] = error[:retry_after_seconds] if error[:retry_after_seconds]
      extensions[:description] = error[:description] if error[:description]
      raise GraphQL::ExecutionError.new(error.fetch(:message), extensions: extensions)
    end

    private

    def error_code
      return "UNAUTHENTICATED" if payload["error_type"] == "not_logged_in"

      case @status
      when 403
        "FORBIDDEN"
      when 404
        "NOT_FOUND"
      when 409
        "CONFLICT"
      when 429
        "RATE_LIMITED"
      when 500..599
        "UNAVAILABLE"
      else
        "BAD_USER_INPUT"
      end
    end
  end
end
