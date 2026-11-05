require "rails_helper"
RSpec.describe DiscourseGraphQL::GraphQLController, type: :request do
  it "measures native protected upload URL lookup growth" do
    user = Fabricate(:user)
    key = Fabricate(:api_key, user: user)
    uploads = 50.times.map do
      post = Fabricate(:private_message_post, user: user)
      Fabricate(:secure_upload, user: user, access_control_post: post)
    end
    query = 'query URLs($urls: [String!]!) { lookupUploadUrls(shortUrls: $urls) { shortUrl } }'
    counts = [1, 50].map do |limit|
      ActiveRecord::Base.connection_pool.with_connection { |connection| connection.clear_query_cache }
      queries = track_sql_queries do
        post "/discourse-graphql/graphql", params: { query: query, variables: { urls: uploads.first(limit).map(&:short_url) } }, headers: { "Api-Key" => key.key, "Api-Username" => user.username }, as: :json
      end
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "lookupUploadUrls").map { |upload| upload.fetch("shortUrl") }).to match_array(uploads.first(limit).map(&:short_url))
      queries.size
    end
    native_counts = [1, 50].map do |limit|
      ActiveRecord::Base.connection_pool.with_connection { |connection| connection.clear_query_cache }
      queries = track_sql_queries do
        post "/uploads/lookup-urls.json", params: { short_urls: uploads.first(limit).map(&:short_url) }, headers: { "Api-Key" => key.key, "Api-Username" => user.username }
      end
      expect(response.status).to eq(200)
      expect(response.parsed_body.map { |upload| upload.fetch("short_url") }).to match_array(uploads.first(limit).map(&:short_url))
      queries.size
    end
    puts JSON.generate(graphql_sql: counts, native_sql: native_counts, collection_sizes: [1, 50], maximum_sql_growth: 2, growth_budget_met: counts.last <= counts.first + 2)
  end
end
