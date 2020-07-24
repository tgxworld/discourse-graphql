module Types
  class SearchPostType < Types::PostType
    description "SearchPostType"

    field :blurb, String, null: false
    field :topic, TopicType, null: false

    def blurb
      context[:result].blurb(object)
    end

    def topic
      object.topic
    end
  end
end
