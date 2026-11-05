module DiscourseGraphQL
  module Types
    class ExternalUploadPayloadType < BaseObject
      field :success, Boolean, null: false
      field :ticket, ExternalUploadTicketType, null: true
      field :errors, [UserErrorType], null: false
    end
  end
end
