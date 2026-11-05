abort "Run this check only in test." unless Rails.env.test?
abort "Use no argument or disabled." unless ARGV.empty? || ARGV == ["disabled"]
abort "Load discourse-graphql, chat and its native automation prerequisite." unless ENV.fetch("LOAD_PLUGINS", "").split(",").sort == %w[automation chat discourse-graphql]
disabled = ARGV == ["disabled"]
abort "Chat must be loaded." unless Discourse.plugins_by_name.key?("chat")
abort "Native Chat requires Automation during boot." unless Discourse.plugins_by_name.key?("automation")

Rails.application.eager_load!
SiteSetting.chat_enabled = !disabled
session = ActionDispatch::Integration::Session.new(Rails.application)
query = '{ capabilities { id available queryFields mutationFields } __schema { queryType { fields { name } } mutationType { fields { name } } types { name } } }'
session.get("/discourse-graphql/graphql", params: { query: query }, headers: { "HTTP_HOST" => "test.localhost" })
abort "Unexpected discovery HTTP status." unless session.response.status == 200
result = JSON.parse(session.response.body)
abort result.fetch("errors").inspect if result["errors"].present?
data = result.fetch("data")
capabilities = data.fetch("capabilities")
expected = %w[discourse chat.channelDiscovery chat.messageHistory chat.reactionUsers chat.messageCreation chat.membershipAndReading chat.reactionChanges]
abort "Unexpected optional capabilities." unless capabilities.map { |capability| capability.fetch("id") } == expected
abort "Unexpected Chat availability." unless capabilities.drop(1).all? { |capability| capability.fetch("available") == !disabled }
types = data.dig("__schema", "types").map { |type| type.fetch("name") }
abort "Reaction types missing." unless %w[ChatReaction ChatReactionActor ChatReactionUser ChatReactionPage ChatReactionUserPage ChatReactionChangeInput ChatReactionAction].all? { |name| types.include?(name) }
abort "Unexpected Checklist types." if types.any? { |name| name.start_with?("Checklist") }
fields = data.dig("__schema", "queryType", "fields").map { |field| field.fetch("name") }
mutations = data.dig("__schema", "mutationType", "fields").map { |field| field.fetch("name") }
abort "Reaction query missing." unless fields.include?("chatReactionUsers")
abort "Reaction mutation missing." unless mutations.include?("updateChatReaction")
query = '{ chatReactionUsers(channelId: "0", messageId: "0") { totalCount } __typename }'
session.get("/discourse-graphql/graphql", params: { query: query }, headers: { "HTTP_HOST" => "test.localhost" })
abort "Unexpected reactor HTTP status." unless session.response.status == 200
result = JSON.parse(session.response.body)
expected_error = disabled ? "FEATURE_DISABLED" : "UNAUTHENTICATED"
abort result.inspect unless result.dig("errors", 0, "extensions", "code") == expected_error && result.dig("data", "chatReactionUsers").nil?
abort "Reactor query lost its sibling." unless result.dig("data", "__typename") == "Query"
mutation = 'mutation { updateChatReaction(input: { channelId: "0", messageId: "0", emoji: "heart", action: ADD }) { success errors { code } } __typename }'
session.post("/discourse-graphql/graphql", params: { query: mutation }, headers: { "HTTP_HOST" => "test.localhost" }, as: :json)
abort "Unexpected mutation HTTP status." unless session.response.status == 200
result = JSON.parse(session.response.body)
if disabled
  abort result.inspect unless result.dig("errors", 0, "extensions", "code") == expected_error && result.dig("data", "updateChatReaction").nil?
else
  abort result.inspect unless result.dig("data", "updateChatReaction", "errors", 0, "code") == expected_error
end
abort "Mutation lost its sibling." unless result.dig("data", "__typename") == "Mutation"
abort "Native Checklist loaded unexpectedly." if defined?(::Checklist)
abort "Native Data Explorer loaded unexpectedly." if defined?(::DiscourseDataExplorer)
puts JSON.generate(status: "passed", eager_loaded: true, chat_available: !disabled, reaction_error: expected_error, capabilities: capabilities.map { |capability| capability.fetch("id") })
