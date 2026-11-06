require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController, type: :request do
  it "records native attachment preparation across message page sizes and selections" do
    user = Fabricate(:user, refresh_auto_groups: true)
    channel = Fabricate(:category_channel)
    api_key = Fabricate(:api_key, user: user)
    headers = { "Api-Key" => api_key.key, "Api-Username" => user.username }
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
    50.times do
      upload = Fabricate(:upload)
      Fabricate(
        :optimized_image,
        upload: upload,
        width: upload.thumbnail_width,
        height: upload.thumbnail_height,
      )
      Fabricate(:chat_message, chat_channel: channel, user: user, uploads: [upload])
    end

    measurements = []
    %w[native graphql_id graphql_upload_id graphql_thumbnail].each do |operation|
      [1, 50].each do |last|
        request_page =
          lambda do
            if operation == "native"
              get "/chat/api/channels/#{channel.id}/messages.json",
                  params: {
                    page_size: last,
                    direction: "past",
                  },
                  headers: headers
            else
              selection = {
                "graphql_id" => "id",
                "graphql_upload_id" => "uploads(first: 1) { nodes { id } }",
                "graphql_thumbnail" =>
                  "uploads(first: 1) { nodes { id thumbnail { id width height url } } }",
              }.fetch(operation)
              get "/discourse-graphql/graphql",
                  params: {
                    query:
                      "{ chatMessages(channelId: #{channel.id.to_s.to_json}, last: #{last}) { nodes { #{selection} } } }",
                  },
                  headers: headers
            end
            expect(response.status).to eq(200)
            expect(response.parsed_body["errors"]).to be_blank
            nodes =
              (
                if operation == "native"
                  response.parsed_body["messages"]
                else
                  response.parsed_body.dig("data", "chatMessages", "nodes")
                end
              )
            expect(nodes.size).to eq(last)
            if operation == "graphql_thumbnail"
              expect(
                nodes.map { |node| node.dig("uploads", "nodes", 0, "thumbnail", "id") },
              ).to all(be_present)
            end
          end
        request_page.call
        records = Hash.new(0)
        listener = ->(_name, _start, _finish, _id, payload) do
          records[payload.fetch(:class_name)] += payload.fetch(:record_count)
        end
        queries = nil
        ActiveSupport::Notifications.subscribed(listener, "instantiation.active_record") do
          queries = track_sql_queries { request_page.call }
        end
        measurements << {
          operation: operation,
          messages: last,
          queries: queries.size,
          tables: queries.group_by { |sql| sql[/FROM "([^"]+)"/i, 1] }.transform_values(&:size),
          loaded_records: records,
        }
      end
    end
    puts JSON.generate(
           measurement: "chat_message_media_preparation",
           measurements: measurements,
           total_performance_budgets_verified: false,
         )
  end
end
