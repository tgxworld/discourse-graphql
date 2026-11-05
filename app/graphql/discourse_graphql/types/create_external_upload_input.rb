module DiscourseGraphQL
  module Types
    class CreateExternalUploadInput < BaseInputObject
      argument :file_name, String, required: true
      argument :file_size_bytes, GraphQL::Types::BigInt, required: true
      argument :upload_type, String, required: true
      argument :sha1_checksum, String, required: false
    end
  end
end
