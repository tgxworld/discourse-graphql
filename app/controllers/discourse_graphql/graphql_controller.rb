module DiscourseGraphQL
  class GraphQLController < ApplicationController
    requires_plugin DiscourseGraphQL::PLUGIN_NAME
    allow_when_archived :execute

    skip_before_action :check_xhr, :preload_json

    def execute
      parameters = MultipartRequest.parameters(params)
      if parameters[:_json].present? || !parameters[:query].is_a?(String) || parameters[:query].blank?
        return render_bad_request
      end

      variables = parameters[:variables]
      variables = JSON.parse(variables) if variables.is_a?(String) && variables.present?
      variables = {} if variables.nil? || variables == ""
      variables = variables.to_unsafe_h if variables.is_a?(ActionController::Parameters)
      return render_bad_request unless variables.is_a?(Hash)

      operation_name = parameters[:operationName]
      return render_bad_request if operation_name && !operation_name.is_a?(String)

      document = GraphQL.parse(parameters[:query])
      query =
        GraphQL::Query.new(
          DiscourseGraphQL::Schema,
          document: document,
          variables: variables,
          operation_name: operation_name,
          context: { guardian: guardian, request: request },
        )

      return render_bad_request if request.get? && query.selected_operation&.operation_type == "mutation"

      if SiteSetting.site_archived && !request.get? && !request.head? && !ArchiveAdmission.allowed?(query)
        raise Discourse::SiteArchived
      end

      result = query.result.to_h
      if query.validation_errors.present?
        result.fetch("errors", []).each do |error|
          error["extensions"] ||= {}
          error["extensions"]["code"] = "GRAPHQL_VALIDATION_FAILED"
        end
      end

      render json: result
    rescue JSON::ParserError, Discourse::InvalidParameters
      render_bad_request
    rescue GraphQL::ParseError
      render json: {
               errors: [
                 {
                   message: I18n.t("discourse_graphql.errors.invalid_query"),
                   extensions: { code: "GRAPHQL_PARSE_FAILED" },
                 },
               ],
             }
    end

    private

    def render_bad_request
      render json: {
               errors: [
                 {
                   message: I18n.t("discourse_graphql.errors.invalid_request"),
                   extensions: { code: "BAD_REQUEST" },
                 },
               ],
             },
             status: :bad_request
    end
  end
end
