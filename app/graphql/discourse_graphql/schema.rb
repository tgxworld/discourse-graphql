# frozen_string_literal: true

module DiscourseGraphQL
  class Schema < GraphQL::Schema
    # mutation(Types::MutationType)
    query(Types::QueryType)

    use GraphQL::Dataloader
    complexity_cost_calculation_mode :future
    query_analyzer Analysis::Complexity
    query_analyzer Analysis::Depth

    rescue_from(Discourse::NotLoggedIn) do
      raise GraphQL::ExecutionError.new(
        I18n.t("not_logged_in"),
        extensions: { code: "UNAUTHENTICATED" },
      )
    end

    rescue_from(Discourse::InvalidAccess) do
      raise GraphQL::ExecutionError.new(
        I18n.t("invalid_access"),
        extensions: { code: "FORBIDDEN" },
      )
    end

    rescue_from(Discourse::NotFound, ActiveRecord::RecordNotFound) do
      raise GraphQL::ExecutionError.new(
        I18n.t("not_found"),
        extensions: { code: "NOT_FOUND" },
      )
    end

    rescue_from(Discourse::InvalidParameters) do
      raise GraphQL::ExecutionError.new(
        I18n.t("discourse_graphql.errors.invalid_parameters"),
        extensions: { code: "BAD_USER_INPUT" },
      )
    end

    rescue_from(RateLimiter::LimitExceeded) do |error|
      raise GraphQL::ExecutionError.new(
        error.description,
        extensions: { code: "RATE_LIMITED", retryAfterSeconds: error.available_in },
      )
    end
  end
end
