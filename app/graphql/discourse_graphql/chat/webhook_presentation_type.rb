module DiscourseGraphQL
  module Chat
    class WebhookPresentationType < Types::BaseObject
      graphql_name "ChatWebhookPresentation"

      field :username, String, null: true, hash_key: "username"
      field :emoji, String, null: true, hash_key: "emoji"
    end
  end
end
