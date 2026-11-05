module DiscourseGraphQL
  module Types
    class UploadPartsPayloadType < BaseObject
      field :success, Boolean, null: false
      field :parts,
            [UploadPartUrlType],
            null: true,
            complexity: ->(_context, _arguments, child) { 100 * child }
      field :errors, [UserErrorType], null: false
    end
  end
end
