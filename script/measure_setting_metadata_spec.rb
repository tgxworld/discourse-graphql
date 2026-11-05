require "rails_helper"
require "memory_profiler"

RSpec.describe DiscourseGraphQL::GraphQLController, type: :request do
  it "bounds total request allocations and SQL growth across repeated metadata selections" do
    admin = Fabricate(:admin)
    api_key = Fabricate(:api_key, user: admin)
    headers = { "Api-Key" => api_key.key, "Api-Username" => admin.username }
    choices = 200.times.map { |index| "#{index}:#{"x" * 4096}" }
    plugin = Discourse.plugins_by_name.fetch("discourse-graphql")
    modifier = ->(setting) { setting[:setting].to_s == "title" ? setting.merge(choices: choices) : setting }
    DiscoursePluginRegistry.register_modifier(plugin, :site_setting_result, &modifier)
    begin
      query = '{ adminSiteSetting(name: "title") { choices(first: 1) { nodes { valueWire } pageInfo { endCursor } } } }'
      post "/discourse-graphql/graphql", params: { query: query }, headers: headers, as: :json
      expect(response.parsed_body["errors"]).to be_blank
      native_queries = nil
      native_report = MemoryProfiler.report do
        native_queries = track_sql_queries do
          get "/admin/site_settings.json", params: { names: ["title"] }, headers: headers
        end
      end
      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("site_settings").find { |setting| setting["setting"] == "title" }.fetch("choices")).to eq(choices)
      native = { allocated_bytes: native_report.total_allocated_memsize, sql_queries: native_queries.size, largest_allocation_sources: native_report.allocated_memory_by_location.first(5) }
      measurements = [1, 40].map do |count|
        fields = count.times.map { |index| "option#{index}: choices(first: 1) { nodes { valueWire } pageInfo { endCursor } }" }.join(" ")
        queries = nil
        report = MemoryProfiler.report do
          queries = track_sql_queries do
            post "/discourse-graphql/graphql", params: { query: "{ adminSiteSetting(name: \"title\") { #{fields} } }" }, headers: headers, as: :json
          end
        end
        expect(response.status).to eq(200)
        expect(response.parsed_body["errors"]).to be_blank
        data = response.parsed_body.dig("data", "adminSiteSetting")
        expect(data.size).to eq(count)
        expect(data.values.map { |page| page.dig("nodes", 0, "valueWire") }).to eq([choices.first] * count)
        { selections: count, allocated_bytes: report.total_allocated_memsize, sql_queries: queries.size, largest_allocation_sources: report.allocated_memory_by_location.first(5) }
      end
      source_bytes = choices.sum(&:bytesize)
      allocation_growth_bytes = measurements.last.fetch(:allocated_bytes) - measurements.first.fetch(:allocated_bytes)
      growth_limit_bytes = source_bytes * 3 + 1024 * 1024
      puts JSON.generate(native: native, measurements: measurements, source_bytes: source_bytes, allocation_growth_bytes: allocation_growth_bytes, growth_limit_bytes: growth_limit_bytes)
      expect(allocation_growth_bytes).to be <= growth_limit_bytes
      expect(measurements.last.fetch(:sql_queries)).to be <= measurements.first.fetch(:sql_queries) + 2
    ensure
      DiscoursePluginRegistry.unregister_modifier(plugin, :site_setting_result, &modifier)
    end
  end
end
