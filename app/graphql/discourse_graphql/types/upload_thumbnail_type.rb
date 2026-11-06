module DiscourseGraphQL
  module Types
    class UploadThumbnailType < BaseObject
      graphql_name "UploadThumbnail"

      field :id, ID, null: true, hash_key: "id"
      field :upload_id, ID, null: true, hash_key: "upload_id"
      field :width, Int, null: true, hash_key: "width"
      field :height, Int, null: true, hash_key: "height"
      field :url, String, null: true, hash_key: "url"
      field :extension, String, null: true, hash_key: "extension"
      field :filesize, GraphQL::Types::BigInt, null: true, hash_key: "filesize"
    end
  end
end
