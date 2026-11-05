require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  describe "#execute" do
    it "builds the schema with exactly the installed optional adapters" do
      Rails.application.eager_load! if !Discourse.plugins_by_name.key?("chat")

      get "/discourse-graphql/graphql",
          params: {
            query: "{ capabilities { id available queryFields mutationFields } __schema { queryType { fields { name } } types { name } } }",
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      data = response.parsed_body.fetch("data")
      fields = data.dig("__schema", "queryType", "fields").map { |field| field.fetch("name") }
      types = data.dig("__schema", "types").map { |type| type.fetch("name") }
      capabilities = data.fetch("capabilities")
      expect(capabilities.flat_map { |capability| capability.fetch("queryFields") }).to match_array(fields)

      if Discourse.plugins_by_name.key?("chat")
        expect(fields).to include("chatChannels")
        expect(types).to include("ChatChannel", "ChatChannelPage")
        expect(capabilities.map { |capability| capability.fetch("id") }).to eq(["discourse", "chat.channelDiscovery"])
      else
        expect(fields).not_to include("chatChannels")
        expect(types.grep(/^Chat/)).to be_empty
        expect(capabilities.map { |capability| capability.fetch("id") }).to eq(["discourse"])
        expect(defined?(::Chat)).to be_nil
      end
    end
  end
end
