unless ENV["LOAD_PLUGINS"] == "discourse-graphql"
  abort "Load only discourse-graphql for this check."
end
abort "Chat must be absent." if Discourse.plugins_by_name.key?("chat")

Rails.application.eager_load!

session = ActionDispatch::Integration::Session.new(Rails.application)
session.get(
  "/discourse-graphql/graphql",
  params: {
    query:
      "{ capabilities { id queryFields mutationFields } __schema { queryType { fields { name } } mutationType { fields { name } } types { name } } __type(name: \"BookmarkTarget\") { enumValues { name } } postType: __type(name: \"Post\") { fields { name } } }",
  },
  headers: {
    "HTTP_HOST" => "test.localhost",
  },
)
abort "Unexpected HTTP status: #{session.response.status}" unless session.response.status == 200

payload = JSON.parse(session.response.body)
abort payload.fetch("errors").inspect if payload["errors"].present?
data = payload.fetch("data")
fields = data.dig("__schema", "queryType", "fields").map { |field| field.fetch("name") }
mutations = data.dig("__schema", "mutationType", "fields").map { |field| field.fetch("name") }
types = data.dig("__schema", "types").map { |type| type.fetch("name") }
unless %w[
         SiteSettingDefinition
         SiteSettingChoicePage
         SiteSettingDependencyPage
         SiteSettingObjectSchema
         SiteSettingJsonSchema
       ].all? { |name| types.include?(name) }
  abort "Core setting metadata types missing without optional plugins."
end
capabilities = data.fetch("capabilities")
targets = data.fetch("__type").fetch("enumValues").map { |value| value.fetch("name") }
abort "Optional bookmark targets leaked into the schema." unless targets.sort == %w[POST TOPIC]
unless capabilities.map { |capability| capability.fetch("id") } == ["discourse"]
  abort "Unexpected optional capabilities."
end
unless capabilities.first.fetch("queryFields").sort == fields.sort
  abort "Capability fields do not match the schema."
end
unless capabilities.first.fetch("mutationFields").sort == mutations.sort
  abort "Capability mutations do not match the schema."
end
abort "Chat mutations leaked into the schema." if mutations.any? { |name| name.include?("Chat") }
abort "Chat fields leaked into the schema." if fields.include?("chatChannels")
abort "Chat types leaked into the schema." if types.any? { |name| name.start_with?("Chat") }
abort "Native Chat constants were loaded." if defined?(::Chat)
abort "Native Data Explorer constants were loaded." if defined?(::DiscourseDataExplorer)
if types.any? { |name| name.start_with?("Checklist") }
  abort "Checklist types leaked into the schema."
end
if capabilities
     .flat_map { |capability| capability.fetch("mutationFields") }
     .include?("updateChecklist")
  abort "Checklist mutation leaked into the schema."
end
abort "Native Checklist constants were loaded." if defined?(::Checklist)

unless data.fetch("postType").fetch("fields").any? { |field| field.fetch("name") == "updatedAt" }
  abort "Core timestamp field missing without Checklist."
end
puts JSON.generate(
       status: "passed",
       eager_loaded: true,
       capabilities: capabilities,
       optional_chat: "absent",
       bookmark_targets: targets,
     )
