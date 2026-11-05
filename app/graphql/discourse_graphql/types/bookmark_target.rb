module DiscourseGraphQL
  module Types
    class BookmarkTarget < BaseEnum
      if Discourse.plugins_by_name.key?("discourse-data-explorer")
        value "DATA_EXPLORER_QUERY_GROUP", value: "DiscourseDataExplorer::QueryGroup"
      end
      value "POST", value: "Post"
      value "TOPIC", value: "Topic"
      value "CHAT_MESSAGE", value: "Chat::Message" if Discourse.plugins_by_name.key?("chat")
    end
  end
end
