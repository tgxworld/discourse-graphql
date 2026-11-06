require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController, type: :request do
  it "records replacement uploads and missing bulk targets through HTTP" do
    user = Fabricate(:user, refresh_auto_groups: true)
    channel = Fabricate(:category_channel)
    key = Fabricate(:api_key, user: user)
    headers = { "Api-Key" => key.key, "Api-Username" => user.username }
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
    owned = Fabricate(:upload, user: user)
    foreign = Fabricate(:upload)
    measurements = []
    [{}, { upload_ids: nil }, { upload_ids: [] }, { upload_ids: [foreign.id] }, { upload_ids: [owned.id, foreign.id] }, { upload_ids: [owned.id, owned.id] }].each_with_index do |input, index|
      message = Fabricate(:chat_message, chat_channel: channel, user: user, uploads: [owned])
      put "/chat/api/channels/#{channel.id}/messages/#{message.id}.json", params: input.merge(message: "Native edit #{index}"), headers: headers, as: :json
      expect(response.status).to eq(200)
      measurements << { input: input, status: response.status, retained_uploads: message.reload.upload_ids }
    end
    delete "/chat/api/channels/#{channel.id}/messages.json", params: { message_ids: [0] }, headers: headers, as: :json
    measurements << { operation: "missing_bulk", status: response.status, errors: response.parsed_body["errors"] }
    [{}, { message: nil }, { message: "" }].each do |input|
      before_count = Chat::Message.count
      post "/chat/#{channel.id}.json", params: input.merge(upload_ids: [owned.id]), headers: headers, as: :json
      measurements << { operation: "create", input: input, status: response.status, created: Chat::Message.count - before_count }
      entry = Fabricate(:chat_message, chat_channel: channel, user: user)
      put "/chat/api/channels/#{channel.id}/messages/#{entry.id}.json", params: input.merge(upload_ids: [owned.id]), headers: headers, as: :json
      measurements << { operation: "update", input: input, status: response.status, raw: entry.reload.message, uploads: entry.upload_ids }
    end
    admin = Fabricate(:admin)
    admin_key = Fabricate(:api_key, user: admin)
    thread_channel = Fabricate(:category_channel, threading_enabled: true)
    thread = Fabricate(:chat_thread, channel: thread_channel)
    reply = Fabricate(:chat_message, chat_channel: thread_channel, thread: thread)
    thread.update!(last_message: reply, replies_count: 1)
    admin_headers = { "Api-Key" => admin_key.key, "Api-Username" => admin.username }
    get "/chat/api/channels/#{thread_channel.id}/threads/#{thread.id}.json", headers: admin_headers
    expect(response.status).to eq(200)
    before_replies = response.parsed_body.dig("thread", "reply_count")
    put "/chat/api/channels/#{thread_channel.id}/messages/#{reply.id}/restore.json", headers: admin_headers, as: :json
    restore_status = response.status
    get "/chat/api/channels/#{thread_channel.id}/threads/#{thread.id}.json", headers: admin_headers
    expect(response.status).to eq(200)
    measurements << { operation: "restore_live", status: restore_status, replies_before: before_replies, replies_after: response.parsed_body.dig("thread", "reply_count"), deleted_at: reply.reload.deleted_at }
    post "/discourse-graphql/graphql", params: { query: "mutation { restoreChatMessage(channelId: #{thread_channel.id.to_s.to_json}, messageId: #{reply.id.to_s.to_json}) { success } }" }, headers: admin_headers, as: :json
    expect(response.parsed_body.dig("data", "restoreChatMessage", "success")).to eq(true)
    get "/chat/api/channels/#{thread_channel.id}/threads/#{thread.id}.json", headers: admin_headers
    measurements << { operation: "graphql_restore_live", replies_after: response.parsed_body.dig("thread", "reply_count"), deleted_at: reply.reload.deleted_at }
    SiteSetting.chat_pinned_messages = true
    pinned = Fabricate(:chat_message, chat_channel: channel, user: user)
    pin = Fabricate(:chat_pinned_message, chat_message: pinned, user: user)
    delete "/chat/api/channels/#{channel.id}/messages.json", params: { message_ids: [pinned.id] }, headers: headers, as: :json
    expect(response.status).to eq(200)
    get "/chat/api/channels/#{channel.id}/pins.json", headers: headers
    measurements << { operation: "pins_after_bulk_delete", status: response.status, pin_retained: Chat::PinnedMessage.exists?(pin.id), message_deleted: pinned.reload.trashed? }
    puts JSON.generate(measurement: "native_chat_lifecycle_contract", owned_upload_id: owned.id, foreign_upload_id: foreign.id, measurements: measurements, total_performance_budgets_verified: false)
  end

  it "records native and GraphQL bulk deletion query growth separately from writes" do
    user = Fabricate(:user, refresh_auto_groups: true)
    key = Fabricate(:api_key, user: user)
    headers = { "Api-Key" => key.key, "Api-Username" => user.username }
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    measurements = []
    %w[native graphql].each do |operation|
      [1, 50].each do |count|
        channel = Fabricate(:category_channel)
        channel.add(user)
        entries = Fabricate.times(count, :chat_message, chat_channel: channel, user: user)
        ids = entries.map(&:id)
        cached_reads = 0
        cached_tables = Hash.new(0)
        listener = ->(_name, _start, _finish, _id, payload) do
          if payload[:cached] && payload[:sql].match?(/\A\s*(SELECT|WITH)\b/i)
            cached_reads += 1
            cached_tables[payload[:sql][/FROM "([^"]+)"/i, 1]] += 1
          end
        end
        queries = nil
        ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
          queries = track_sql_queries do
            if operation == "native"
              delete "/chat/api/channels/#{channel.id}/messages.json", params: { message_ids: ids }, headers: headers, as: :json
            else
              post "/discourse-graphql/graphql", params: { query: "mutation($ids: [ID!]!) { deleteChatMessages(channelId: #{channel.id.to_s.to_json}, messageIds: $ids) { success } }", variables: { ids: ids.map(&:to_s) } }, headers: headers, as: :json
            end
          end
        end
        expect(response.status).to eq(200)
        expect(response.parsed_body["errors"]).to be_blank
        expect(response.parsed_body.dig("data", "deleteChatMessages", "success")).to eq(true) if operation == "graphql"
        expect(Chat::Message.where(id: ids)).not_to exist
        reads = queries.select { |sql| sql.match?(/\A\s*(SELECT|WITH)\b/i) }
        measurements << {
          operation: operation,
          messages: count,
          queries: queries.size,
          reads: reads.size,
          cached_reads: cached_reads,
          cached_tables: cached_tables,
          uncached_reads: reads.size - cached_reads,
          writes: queries.count { |sql| sql.match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) },
          read_tables: reads.group_by { |sql| sql[/FROM "([^"]+)"/i, 1] }.transform_values(&:size),
        }
      end
    end
    puts JSON.generate(measurement: "chat_bulk_delete_preparation", measurements: measurements, total_performance_budgets_verified: false)
  end
end
