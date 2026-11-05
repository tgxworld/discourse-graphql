module DiscourseGraphQL
  module Extensions
    def self.query_modules
      Discourse.plugins_by_name.key?("chat") ? [Chat::QueryFields, Chat::HistoryQueryFields, Chat::ReactionQueryFields] : []
    end

    def self.mutation_modules
      modules = Discourse.plugins_by_name.key?("chat") ? [Chat::MutationFields, Chat::MembershipMutationFields, Chat::ReactionMutationFields] : []
      modules << Checklist::MutationFields if Discourse.plugins_by_name.key?("checklist")
      modules
    end

    def self.ensure_enabled!(plugin_name)
      if !Discourse.plugins_by_name.fetch(plugin_name).enabled?
        raise GraphQL::ExecutionError.new(
          I18n.t("discourse_graphql.errors.feature_disabled"),
          extensions: { code: "FEATURE_DISABLED" },
        )
      end
    end

    def self.capabilities
      optional = (query_modules + mutation_modules).map(&:capability)
      optional_fields = optional.flat_map { |capability| capability.fetch(:query_fields) }
      optional_mutations = optional.flat_map { |capability| capability.fetch(:mutation_fields) }
      [
        {
          id: "discourse",
          available: true,
          query_fields: Types::QueryType.fields.keys.sort - optional_fields,
          mutation_fields: Types::MutationType.fields.keys.sort - optional_mutations,
        },
        *optional,
      ]
    end
  end
end
