module DiscourseGraphQL
  module Extensions
    def self.query_modules
      Discourse.plugins_by_name.key?("chat") ? [Chat::QueryFields] : []
    end

    def self.mutation_modules
      Discourse.plugins_by_name.key?("chat") ? [Chat::MutationFields] : []
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
