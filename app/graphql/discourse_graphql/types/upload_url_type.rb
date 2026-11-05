module DiscourseGraphQL
  module Types
    class UploadUrlType < BaseObject
      field :short_url, String, null: true, hash_key: "short_url"
      field :url, String, null: true, hash_key: "url"
      field :short_path, String, null: true, hash_key: "short_path"
    end
  end
end
