module DiscourseGraphQL
  module Chat
    class DraftPageType < Types::BaseObject
      graphql_name "ChatDraftPage"

      field :nodes, [DraftType], null: false
      field :window_size, Integer, null: false, hash_key: :total_count
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
