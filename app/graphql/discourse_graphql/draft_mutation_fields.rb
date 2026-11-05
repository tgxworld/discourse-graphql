module DiscourseGraphQL
  module DraftMutationFields
    def self.included(type)
      type.field :save_draft, Types::DraftPayloadType, null: true, complexity: 1000 do
        argument :input, Types::SaveDraftInput, required: true
      end
      type.field :delete_draft, Types::DraftPayloadType, null: true, complexity: 1000 do
        argument :key, GraphQL::Types::String, required: true
        argument :sequence, GraphQL::Types::BigInt, required: true
        argument :username, GraphQL::Types::String, required: false
      end
      type.field :delete_drafts, Types::DraftPayloadType, null: true do
        argument :drafts, [Types::DraftReferenceInput], required: true
        argument :username, GraphQL::Types::String, required: false
        complexity ->(_context, arguments, child) do
                     1000 + arguments[:drafts].size.clamp(0, 30) * 20 + child
                   end
      end
    end

    def save_draft(input:)
      parameters = input.to_h
      key = parameters.delete(:key)
      DraftParameters.validate!(key: key, sequence: parameters[:sequence])
      raise Discourse::InvalidParameters if parameters[:owner] && parameters[:owner].size > 200
      parameters[:draft_key] = key
      parameters[:data] = DraftContent.encode(parameters.delete(:content))
      change_draft(adapter: DraftSave, parameters: parameters, request_method: "POST")
    end

    def delete_draft(key:, sequence:, username: nil)
      DraftParameters.validate!(key: key, sequence: sequence)
      change_draft(
        adapter: DraftDelete,
        parameters: {
          id: key,
          sequence: sequence,
          username: username,
        },
        request_method: "DELETE",
      )
    end

    def delete_drafts(drafts:, username: nil)
      references = drafts.map(&:to_h)
      if references.size > 30 || references.map { |draft| draft[:key] }.uniq.size != references.size
        raise Discourse::InvalidParameters
      end
      references.each { |draft| DraftParameters.validate!(**draft) }
      change_draft(
        adapter: DraftBulkDelete,
        parameters: {
          draft_keys: references.map { |draft| draft[:key] },
          sequences: references.to_h { |draft| [draft[:key], draft[:sequence]] },
          username: username,
        },
        request_method: "DELETE",
      )
    end

    private

    def change_draft(adapter:, parameters:, request_method:)
      context.dataloader.clear_cache
      adapter.new(request: context[:request], request_method: request_method).call(
        parameters: parameters,
      )
    ensure
      context.dataloader.clear_cache
    end
  end
end
