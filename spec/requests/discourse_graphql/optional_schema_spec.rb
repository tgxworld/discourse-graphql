require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  describe "#execute" do
    it "builds the schema with exactly the installed optional adapters" do
      Rails.application.eager_load! if !Discourse.plugins_by_name.key?("chat")

      get "/discourse-graphql/graphql",
          params: {
            query: "{ capabilities { id available queryFields mutationFields } __schema { queryType { fields { name } } mutationType { fields { name } } types { name } } }",
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      data = response.parsed_body.fetch("data")
      fields = data.dig("__schema", "queryType", "fields").map { |field| field.fetch("name") }
      mutations = data.dig("__schema", "mutationType", "fields").map { |field| field.fetch("name") }
      types = data.dig("__schema", "types").map { |type| type.fetch("name") }
      capabilities = data.fetch("capabilities")
      expect(capabilities.flat_map { |capability| capability.fetch("queryFields") }).to match_array(fields)
      expect(capabilities.flat_map { |capability| capability.fetch("mutationFields") }).to match_array(mutations)
      expected_capabilities = ["discourse"]

      if Discourse.plugins_by_name.key?("chat")
        expect(fields).to include("chatChannels", "chatMessages", "chatReactionUsers", "chatThread")
        expect(types).to include("ChatChannel", "ChatChannelPage")
        expect(mutations).to include("createChatMessage", "updateChatReaction", "createChatThread", "updateChatThreadTitle", "markChatThreadRead", "updateChatThreadNotifications", "markChatThreadTitlePromptSeen")
        expect(types).to include("ChatThreadMembership", "ChatThreadMembershipPayload", "ChatThreadNotificationLevel")
        expected_capabilities.concat(["chat.channelDiscovery", "chat.messageHistory", "chat.reactionUsers", "chat.threadLookup", "chat.messageCreation", "chat.membershipAndReading", "chat.reactionChanges", "chat.threadControls", "chat.threadCreation"])
      else
        expect(fields).not_to include("chatChannels", "chatMessages", "chatReactionUsers", "chatThread")
        expect(mutations).not_to include("createChatMessage", "updateChatReaction", "createChatThread", "updateChatThreadTitle", "markChatThreadRead", "updateChatThreadNotifications", "markChatThreadTitlePromptSeen")
        expect(types.grep(/^Chat/)).to be_empty
        expect(defined?(::Chat)).to be_nil
      end

      if Discourse.plugins_by_name.key?("checklist")
        expected_capabilities << "checklist.checkboxChanges"
        expect(mutations).to include("updateChecklist")
        expect(types).to include("ChecklistUpdateInput", "ChecklistUpdatePayload")
      else
        expect(mutations).not_to include("updateChecklist")
        expect(types.grep(/^Checklist/)).to be_empty
        expect(defined?(::Checklist)).to be_nil
      end
      expect(capabilities.map { |capability| capability.fetch("id") }).to eq(expected_capabilities)
    end
  end
end
