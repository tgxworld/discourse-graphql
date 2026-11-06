module DiscourseGraphQL
  module Types
    class OptimizedVideoType < BaseObject
      graphql_name "OptimizedVideo"

      field :id, ID, null: true, hash_key: "id"
      field :upload_id, ID, null: true, hash_key: "upload_id"
      field :url, String, null: true, hash_key: "url"
      field :extension, String, null: true, hash_key: "extension"
      field :filesize, GraphQL::Types::BigInt, null: true, hash_key: "filesize"
      field :sha1, String, null: true, hash_key: "sha1"
      field :original_filename, String, null: true, hash_key: "original_filename"
    end
  end
end
