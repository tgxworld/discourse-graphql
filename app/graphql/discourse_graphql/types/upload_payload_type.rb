module DiscourseGraphQL
  module Types
    class UploadPayloadType < BaseObject
      field :success, Boolean, null: false
      field :upload, UploadType, null: true
      field :errors, [UserErrorType], null: false
    end
  end
end
