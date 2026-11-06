module DiscourseGraphQL
  module NativeFieldSelection
    def self.select(serializer:, fields:)
      serializer.extend(self)
      serializer.select_graphql_fields(fields)
      serializer
    end

    def select_graphql_fields(fields)
      @graphql_selected_fields = fields
    end

    def include?(name)
      @graphql_selected_fields.include?(name) && super
    end
  end
end
