module DiscourseGraphQL
  module Types
    class SearchPostType < Types::PostType
      description "SearchPostType"

      field :blurb, String, null: false

      def blurb
        context[:result].blurb(object, scope: context[:guardian])
      end
    end
  end
end
