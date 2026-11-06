module DiscourseGraphQL
  module Chat
    class BlockElementType < GraphQL::Schema::Union
      graphql_name "ChatBlockElement"
      possible_types ButtonElementType, CategoryElementType

      def self.resolve_type(object, _context)
        case object["type"]
        when "button"
          ButtonElementType
        when "category"
          CategoryElementType
        else
          raise GraphQL::ExecutionError.new(
            I18n.t("discourse_graphql.errors.internal_error"),
            extensions: { code: "INTERNAL_ERROR" },
          )
        end
      end
    end
  end
end
