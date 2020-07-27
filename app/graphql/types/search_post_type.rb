module Types
  class SearchPostType < Types::PostType
    description "SearchPostType"

    field :blurb, String, null: false

    def blurb
      context[:result].blurb(object)
    end
  end
end
