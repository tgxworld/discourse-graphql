module DiscourseGraphQL
  module Chat
    class MessageAuthorType < Types::BaseObject
      graphql_name "ChatMessageAuthor"

      field :id, ID, null: true
      field :username, String, null: false
      field :name, String, null: true
      field :avatar_template, String, null: false, hash_key: "avatar_template"
      field :admin, Boolean, null: true, hash_key: "admin"
      field :moderator, Boolean, null: true, hash_key: "moderator"
      field :staff, Boolean, null: true, hash_key: "staff"
      field :new_user, Boolean, null: true, hash_key: "new_user"
      field :primary_group_name, String, null: true, hash_key: "primary_group_name"
      field :flair_name, String, null: true, hash_key: "flair_name"
      field :flair_url, String, null: true, hash_key: "flair_url"
      field :flair_bg_color, String, null: true, hash_key: "flair_bg_color"
      field :flair_color, String, null: true, hash_key: "flair_color"
      field :flair_group_id, ID, null: true, hash_key: "flair_group_id"
      field :status, Types::UserStatusType, null: true, hash_key: "status"
    end
  end
end
