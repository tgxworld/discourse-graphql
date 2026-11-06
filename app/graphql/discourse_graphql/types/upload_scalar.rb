module DiscourseGraphQL
  module Types
    class UploadScalar < GraphQL::Schema::Scalar
      graphql_name "Upload"

      def self.coerce_input(value, _context)
        return value if value.is_a?(ActionDispatch::Http::UploadedFile)
        raise GraphQL::CoercionError, I18n.t("discourse_graphql.errors.invalid_parameters")
      end
    end
  end
end
