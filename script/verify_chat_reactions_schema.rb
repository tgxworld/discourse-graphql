abort "Run this check only in test." unless Rails.env.test?
abort "Use no argument or disabled." unless ARGV.empty? || ARGV == ["disabled"]
unless ENV.fetch("LOAD_PLUGINS", "").split(",").sort == %w[automation chat discourse-graphql]
  abort "Load discourse-graphql, chat and its native automation prerequisite."
end
disabled = ARGV == ["disabled"]
abort "Chat must be loaded." unless Discourse.plugins_by_name.key?("chat")
unless Discourse.plugins_by_name.key?("automation")
  abort "Native Chat requires Automation during boot."
end

Rails.application.eager_load!
SiteSetting.chat_enabled = !disabled
session = ActionDispatch::Integration::Session.new(Rails.application)
query =
  "{ capabilities { id available queryFields mutationFields } __schema { queryType { fields { name } } mutationType { fields { name } } types { name } } }"
session.get(
  "/discourse-graphql/graphql",
  params: {
    query: query,
  },
  headers: {
    "HTTP_HOST" => "test.localhost",
  },
)
abort "Unexpected discovery HTTP status." unless session.response.status == 200
result = JSON.parse(session.response.body)
abort result.fetch("errors").inspect if result["errors"].present?
data = result.fetch("data")
capabilities = data.fetch("capabilities")
expected = %w[
  discourse
  chat.channelDiscovery
  chat.messageHistory
  chat.reactionUsers
  chat.threadLookup
  chat.threadLists
  chat.threadMessageHistory
  chat.draftReading
  chat.messageCreation
  chat.membershipAndReading
  chat.reactionChanges
  chat.threadControls
  chat.threadCreation
  chat.draftChanges
  chat.messageChanges
]
unless capabilities.map { |capability| capability.fetch("id") } == expected
  abort "Unexpected optional capabilities."
end
unless capabilities.drop(1).all? { |capability| capability.fetch("available") == !disabled }
  abort "Unexpected Chat availability."
end
types = data.dig("__schema", "types").map { |type| type.fetch("name") }
unless %w[
         ChatMessage
         ChatMessageBookmark
         ChatReplyPreview
         ChatWebhookPresentation
         ChatMessageUserPage
         ChatMessageUploadPage
         ChatMessageBlockPage
         ChatMessageBlock
         ChatBlockElement
         ChatButtonElement
         ChatCategoryElement
         ChatBlockParameter
         ChatBlockChange
         UploadThumbnail
         OptimizedVideo
         UserSnapshot
         UserStatusSnapshot
         UpdateChatMessageInput
       ].all? { |name| types.include?(name) }
  abort "Message presentation types missing."
end
unless %w[
         ChatReaction
         ChatReactionActor
         ChatReactionUser
         ChatReactionPage
         ChatReactionUserPage
         ChatReactionChangeInput
         ChatReactionAction
       ].all? { |name| types.include?(name) }
  abort "Reaction types missing."
end
abort "Unexpected Checklist types." if types.any? { |name| name.start_with?("Checklist") }
fields = data.dig("__schema", "queryType", "fields").map { |field| field.fetch("name") }
mutations = data.dig("__schema", "mutationType", "fields").map { |field| field.fetch("name") }
abort "Reaction query missing." if fields.exclude?("chatReactionUsers")
abort "Reaction mutation missing." if mutations.exclude?("updateChatReaction")
unless %w[
         ChatThreadMembership
         ChatThreadMembershipPayload
         ChatThreadNotificationLevel
       ].all? { |name| types.include?(name) }
  abort "Thread membership types missing."
end
unless %w[chatChannelThreads currentUserChatThreads chatThreadMessages currentUserChatDrafts].all? { |name| fields.include?(name) }
  abort "Thread lists missing."
end
abort "Thread lookup missing." if fields.exclude?("chatThread")
abort "Thread creation missing." if mutations.exclude?("createChatThread")
unless %w[updateChatChannelDraft updateChatThreadDraft].all? { |name| mutations.include?(name) }
  abort "Draft mutations missing."
end
unless %w[
         ChatThread
         ChatThreadOriginalMessage
         ChatThreadPreview
         ChatThreadCreateInput
         ChatThreadCreatePayload
         ChatThreadPage
         ChatThreadMessagePage
         ChatDraft
         ChatDraftPage
         ChatThreadTracking
       ].all? { |name| types.include?(name) }
  abort "Thread types missing."
end
unless %w[
         updateChatThreadTitle
         markChatThreadRead
         updateChatThreadNotifications
         markChatThreadTitlePromptSeen
       ].all? { |name| mutations.include?(name) }
  abort "Thread controls missing."
end
query = '{ chatReactionUsers(channelId: "0", messageId: "0") { totalCount } __typename }'
session.get(
  "/discourse-graphql/graphql",
  params: {
    query: query,
  },
  headers: {
    "HTTP_HOST" => "test.localhost",
  },
)
abort "Unexpected reactor HTTP status." unless session.response.status == 200
result = JSON.parse(session.response.body)
expected_error = disabled ? "FEATURE_DISABLED" : "UNAUTHENTICATED"
unless result.dig("errors", 0, "extensions", "code") == expected_error &&
         result.dig("data", "chatReactionUsers").nil?
  abort result.inspect
end
abort "Reactor query lost its sibling." unless result.dig("data", "__typename") == "Query"
mutation =
  'mutation { updateChatReaction(input: { channelId: "0", messageId: "0", emoji: "heart", action: ADD }) { success errors { code } } __typename }'
session.post(
  "/discourse-graphql/graphql",
  params: {
    query: mutation,
  },
  headers: {
    "HTTP_HOST" => "test.localhost",
  },
  as: :json,
)
abort "Unexpected mutation HTTP status." unless session.response.status == 200
result = JSON.parse(session.response.body)
if disabled
  unless result.dig("errors", 0, "extensions", "code") == expected_error &&
           result.dig("data", "updateChatReaction").nil?
    abort result.inspect
  end
else
  unless result.dig("data", "updateChatReaction", "errors", 0, "code") == expected_error
    abort result.inspect
  end
end
abort "Mutation lost its sibling." unless result.dig("data", "__typename") == "Mutation"
mutation =
  'mutation { markChatThreadRead(channelId: "0", threadId: "0") { success errors { code } } __typename }'
session.post(
  "/discourse-graphql/graphql",
  params: {
    query: mutation,
  },
  headers: {
    "HTTP_HOST" => "test.localhost",
  },
  as: :json,
)
abort "Unexpected thread control HTTP status." unless session.response.status == 200
result = JSON.parse(session.response.body)
if disabled
  unless result.dig("errors", 0, "extensions", "code") == expected_error &&
           result.dig("data", "markChatThreadRead").nil?
    abort result.inspect
  end
else
  unless result.dig("data", "markChatThreadRead", "errors", 0, "code") == expected_error
    abort result.inspect
  end
end
abort "Thread control lost its sibling." unless result.dig("data", "__typename") == "Mutation"
abort "Native Checklist loaded unexpectedly." if defined?(::Checklist)
mutation = 'mutation { edit: updateChatMessage(input: { channelId: "0", messageId: "0", message: "Probe" }) { success errors { code } } remove: deleteChatMessage(channelId: "0", messageId: "0") { success errors { code } } bulk: deleteChatMessages(channelId: "0", messageIds: ["0"]) { success errors { code } } restore: restoreChatMessage(channelId: "0", messageId: "0") { success errors { code } } __typename }'
session.post("/discourse-graphql/graphql", params: { query: mutation }, headers: { "HTTP_HOST" => "test.localhost" }, as: :json)
abort "Unexpected message mutation HTTP status." unless session.response.status == 200
result = JSON.parse(session.response.body)
%w[edit remove bulk restore].each do |field|
  if disabled
    abort result.inspect unless result.dig("data", field).nil?
  else
    abort result.inspect unless result.dig("data", field, "errors", 0, "code") == expected_error
  end
end
if disabled && result.fetch("errors").map { |error| error.dig("extensions", "code") } != [expected_error] * 4
  abort result.inspect
end
abort "Message mutations lost their sibling." unless result.dig("data", "__typename") == "Mutation"
abort "Native Data Explorer loaded unexpectedly." if defined?(::DiscourseDataExplorer)
puts JSON.generate(
       status: "passed",
       eager_loaded: true,
       chat_available: !disabled,
       reaction_error: expected_error,
       capabilities: capabilities.map { |capability| capability.fetch("id") },
     )
