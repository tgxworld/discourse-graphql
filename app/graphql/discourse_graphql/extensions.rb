module DiscourseGraphQL
  module Extensions
    def self.query_modules
      Discourse.plugins_by_name.key?("chat") ? [Chat::QueryFields] : []
    end

    def self.capabilities
      optional = query_modules.map(&:capability)
      optional_fields = optional.flat_map { |capability| capability.fetch(:query_fields) }
      [
        {
          id: "discourse",
          available: true,
          query_fields: Types::QueryType.fields.keys.sort - optional_fields,
          mutation_fields: Types::MutationType.fields.keys.sort,
        },
        *optional,
      ]
    end
  end
end
