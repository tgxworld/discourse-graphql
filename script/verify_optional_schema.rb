abort "Load only discourse-graphql for this check." unless ENV["LOAD_PLUGINS"] == "discourse-graphql"
abort "Chat must be absent." if Discourse.plugins_by_name.key?("chat")

Rails.application.eager_load!

session = ActionDispatch::Integration::Session.new(Rails.application)
session.get(
  "/discourse-graphql/graphql",
  params: {
    query: "{ capabilities { id queryFields mutationFields } __schema { queryType { fields { name } } types { name } } }",
  },
  headers: { "HTTP_HOST" => "test.localhost" },
)
abort "Unexpected HTTP status: #{session.response.status}" unless session.response.status == 200

payload = JSON.parse(session.response.body)
abort payload.fetch("errors").inspect if payload["errors"].present?
data = payload.fetch("data")
fields = data.dig("__schema", "queryType", "fields").map { |field| field.fetch("name") }
types = data.dig("__schema", "types").map { |type| type.fetch("name") }
capabilities = data.fetch("capabilities")
abort "Unexpected optional capabilities." unless capabilities.map { |capability| capability.fetch("id") } == ["discourse"]
abort "Capability fields do not match the schema." unless capabilities.first.fetch("queryFields").sort == fields.sort
abort "Chat fields leaked into the schema." if fields.include?("chatChannels")
abort "Chat types leaked into the schema." if types.any? { |name| name.start_with?("Chat") }
abort "Native Chat constants were loaded." if defined?(::Chat)

puts JSON.generate(status: "passed", eager_loaded: true, capabilities: capabilities, optional_chat: "absent")
