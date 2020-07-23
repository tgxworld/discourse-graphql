module Types
  class SearchPostType < Types::BaseObject
    description "SearchPostType"

    field :id, ID, null: false
    field :name, String, null: true
    field :username, String, null: true
    field :avatar_template, String, null: false
    field :blurb, String, null: false
    field :like_count, Int, null: false
    field :post_number, Int, null: false
    field :topic, SearchTopicType, null: false

    def topic
      object.topic
    end

    def blurb
      context[:result].blurb(object)
    end

    def name
      if SiteSetting.enable_names?
        object.user&.name
      end
    end

    def username
      object.user&.username
    end

    def avatar_template
      object.user&.avatar_template
    end
  end
end
