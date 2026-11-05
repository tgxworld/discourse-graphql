abort "Run this check only in test." unless Rails.env.test?
abort "Use no argument or disabled." unless ARGV.empty? || ARGV == ["disabled"]
disabled = ARGV == ["disabled"]

unless ENV.fetch("LOAD_PLUGINS", "").split(",").sort == %w[checklist discourse-graphql]
  abort "Load only discourse-graphql and checklist."
end
abort "Checklist must be loaded." unless Discourse.plugins_by_name.key?("checklist")
abort "Chat must be absent." if Discourse.plugins_by_name.key?("chat")

Rails.application.eager_load!
SiteSetting.checklist_enabled = !disabled
session = ActionDispatch::Integration::Session.new(Rails.application)
discovery =
  '{ capabilities { id available mutationFields } __schema { mutationType { fields { name } } types { name } } __type(name: "Post") { fields { name } } }'
session.get(
  "/discourse-graphql/graphql",
  params: {
    query: discovery,
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
unless capabilities.map { |capability| capability.fetch("id") } ==
         %w[discourse checklist.checkboxChanges]
  abort "Unexpected capabilities."
end
abort "Unexpected Checklist availability." unless capabilities.last.fetch("available") == !disabled
mutation_fields = data.dig("__schema", "mutationType", "fields").map { |field| field.fetch("name") }
abort "Missing Checklist mutation." if mutation_fields.exclude?("updateChecklist")
types = data.dig("__schema", "types").map { |type| type.fetch("name") }
unless %w[ChecklistUpdateInput ChecklistUpdatePayload ChecklistToggleInput].all? { |name|
         types.include?(name)
       }
  abort "Missing Checklist types."
end
abort "Chat types leaked." if types.any? { |name| name.start_with?("Chat") }
unless data.fetch("__type").fetch("fields").any? { |field| field.fetch("name") == "updatedAt" }
  abort "Missing native timestamp projection."
end

mutation =
  'mutation { updateChecklist(input: { postId: "1", expectedRaw: "- [ ] item", expectedUpdatedAt: "2026-11-05T12:00:00.345Z", mutationId: "schema-probe", toggles: [{ checkboxIndex: 0, checkboxSource: "0:0", checked: true }] }) { success errors { code } } __typename }'
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
  unless result.dig("errors", 0, "extensions", "code") == "FEATURE_DISABLED" &&
           result.dig("data", "updateChecklist").nil?
    abort "Disabled Checklist did not fail predictably."
  end
else
  unless result.dig("data", "updateChecklist", "errors", 0, "code") == "UNAUTHENTICATED"
    abort result.inspect
  end
end
unless result.dig("data", "__typename") == DiscourseGraphQL::Schema.mutation.graphql_name
  abort "Update field lost its sibling."
end
abort "Native Chat constants were loaded." if defined?(::Chat)

puts JSON.generate(
       status: "passed",
       eager_loaded: true,
       capabilities: capabilities.map { |capability| capability.fetch("id") },
       optional_chat: "absent",
       checklist_available: !disabled,
       update_error: disabled ? "FEATURE_DISABLED" : "UNAUTHENTICATED",
     )
