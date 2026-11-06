module DiscourseGraphQL
  module Types
    class UploadType < BaseObject
      graphql_name "UploadedFile"

      field :id, ID, null: true, hash_key: "id"
      field :url, String, null: true, hash_key: "url"
      field :short_url, String, null: true, hash_key: "short_url"
      field :short_path, String, null: true, hash_key: "short_path"
      field :original_filename, String, null: true, hash_key: "original_filename"
      field :filesize, GraphQL::Types::BigInt, null: true, hash_key: "filesize"
      field :width, Int, null: true, hash_key: "width"
      field :height, Int, null: true, hash_key: "height"
      field :thumbnail_width, Int, null: true, hash_key: "thumbnail_width"
      field :thumbnail_height, Int, null: true, hash_key: "thumbnail_height"
      field :extension, String, null: true, hash_key: "extension"
      field :retain_hours, Int, null: true, hash_key: "retain_hours"
      field :human_filesize, String, null: true, hash_key: "human_filesize"
      field :dominant_color, String, null: true, hash_key: "dominant_color"
      field :thumbnail, UploadThumbnailType, null: true, hash_key: "thumbnail"
      field :optimized_video, OptimizedVideoType, null: true, hash_key: "optimized_video"
    end
  end
end
