module DiscourseGraphQL
  module Types
    class ExternalUploadTicketType < BaseObject
      field :unique_identifier, ID, null: false, hash_key: "unique_identifier"
      field :storage_key, String, null: false, hash_key: "key"
      field :external_upload_identifier, ID, null: true, hash_key: "external_upload_identifier"
      field :url, String, null: true, hash_key: "url"
      field :signed_headers,
            [UploadHeaderType],
            null: false,
            hash_key: "signed_headers",
            complexity: ->(_context, _arguments, child) { 100 * child }
    end
  end
end
