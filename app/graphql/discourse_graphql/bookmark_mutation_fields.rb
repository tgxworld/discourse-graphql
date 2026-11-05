module DiscourseGraphQL
  module BookmarkMutationFields
    def self.included(type)
      type.field :create_bookmark, Types::BookmarkPayloadType, null: true, complexity: 1000 do
        argument :input, Types::CreateBookmarkInput, required: true
      end
      type.field :update_bookmark, Types::BookmarkPayloadType, null: true, complexity: 1000 do
        argument :input, Types::UpdateBookmarkInput, required: true
      end
      %i[delete_bookmark toggle_bookmark_pin].each do |name|
        type.field name, Types::BookmarkPayloadType, null: true, complexity: 1000 do
          argument :id, GraphQL::Types::ID, required: true
        end
      end
      type.field :bulk_bookmarks, Types::BookmarkPayloadType, null: true do
        argument :ids, [GraphQL::Types::ID], required: true
        argument :operation, Types::BookmarkBulkOperation, required: true
        complexity ->(_context, arguments, child_complexity) do
          1000 + arguments[:ids].size.clamp(0, 50) * 20 + child_complexity
        end
      end
    end

    def create_bookmark(input:)
      parameters = input.to_h
      parameters[:bookmarkable_id] = parameters.delete(:target_id)
      parameters[:bookmarkable_type] = parameters.delete(:target_type)
      change_bookmark(adapter: BookmarkCreation, parameters: parameters, request_method: "POST")
    end

    def update_bookmark(input:)
      change_bookmark(adapter: BookmarkUpdate, parameters: input.to_h, request_method: "PUT")
    end

    def delete_bookmark(id:)
      change_bookmark(adapter: BookmarkDeletion, parameters: { id: id }, request_method: "DELETE")
    end

    def toggle_bookmark_pin(id:)
      change_bookmark(adapter: BookmarkPin, parameters: { bookmark_id: id }, request_method: "PUT")
    end

    def bulk_bookmarks(ids:, operation:)
      raise Discourse::InvalidParameters if ids.size > 50

      change_bookmark(adapter: BookmarkBulk, parameters: { bookmark_ids: ids, operation: { type: operation } }, request_method: "PUT")
    end

    private

    def change_bookmark(adapter:, parameters:, request_method:)
      context.dataloader.clear_cache
      parameters[:reminder_at] = parameters[:reminder_at].iso8601(6) if parameters[:reminder_at]
      adapter.new(request: context[:request], request_method: request_method).call(parameters: parameters)
    ensure
      context.dataloader.clear_cache
    end
  end
end
