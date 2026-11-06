require "rails_helper"
require "memory_profiler"

RSpec.describe DiscourseGraphQL::GraphQLController, type: :request do
  it "bounds allocation growth when aliases share a large native draft window" do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    user = Fabricate(:user, refresh_auto_groups: true)
    api_key = Fabricate(:api_key, user: user)
    headers = { "Api-Key" => api_key.key, "Api-Username" => user.username }
    source_bytes =
      20.times.sum do |index|
        content = "#{index}:".ljust(SiteSetting.max_chat_draft_length, "x")
        Chat::Draft.create!(user: user, chat_channel: Fabricate(:category_channel), data: content)
        content.bytesize
      end
    get "/session/current.json", headers: headers
    expect(response.status).to eq(200)
    native_queries = nil
    native_report =
      MemoryProfiler.report do
        native_queries = track_sql_queries { get "/session/current.json", headers: headers }
      end
    expect(response.parsed_body.dig("current_user", "chat_drafts").size).to eq(20)
    native_response_bytes = response.body.bytesize
    measurements =
      [1, 8].map do |aliases|
        fields =
          aliases
            .times
            .map { |index| "a#{index}: currentUserChatDrafts(first: 1) { windowSize }" }
            .join(" ")
        get "/discourse-graphql/graphql", params: { query: "{ #{fields} }" }, headers: headers
        expect(response.parsed_body["errors"]).to be_blank
        queries = nil
        report =
          MemoryProfiler.report do
            queries =
              track_sql_queries do
                get "/discourse-graphql/graphql",
                    params: {
                      query: "{ #{fields} }",
                    },
                    headers: headers
              end
          end
        expect(response.status).to eq(200)
        expect(response.parsed_body["errors"]).to be_blank
        expect(response.parsed_body.fetch("data").values).to eq([{ "windowSize" => 20 }] * aliases)
        expect(response.body.bytesize).to be < 1000
        {
          aliases: aliases,
          allocated_bytes: report.total_allocated_memsize,
          sql_queries: queries.size,
          native_reads: queries.count { |sql| sql.match?(/FROM "chat_drafts"/i) },
          response_bytes: response.body.bytesize,
          largest_allocation_sources: report.allocated_memory_by_location.first(5),
        }
      end
    growth_bytes =
      measurements.last.fetch(:allocated_bytes) - measurements.first.fetch(:allocated_bytes)
    growth_limit_bytes = source_bytes * 2 + 1024 * 1024
    puts JSON.generate(
           measurement: "chat_draft_window_allocations",
           source_bytes: source_bytes,
           native_allocated_bytes: native_report.total_allocated_memsize,
           native_sql_queries: native_queries.size,
           native_response_bytes: native_response_bytes,
           measurements: measurements,
           allocation_growth_bytes: growth_bytes,
           growth_limit_bytes: growth_limit_bytes,
           native_source_prepares_unselected_data: true,
           total_performance_budgets_verified: false,
         )
    expect(growth_bytes).to be <= growth_limit_bytes
    expect(measurements.map { |measurement| measurement.fetch(:native_reads) }).to eq([1, 1])
  end
end
