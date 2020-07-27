require 'rails_helper'

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:api_key) { Fabricate(:api_key).key }
  let(:api_username) { 'system' }

  describe '#execute' do
    it 'should return 403 if API headers are not present' do
      post '/discourse-graphql/graphql'

      expect(response.status).to eq(403)
    end

    it 'should return the right results when API headers are present' do
      query = <<~QUERY
      query {
        __schema {
          queryType {
            name
            description
          }
        }
      }
      QUERY

      post '/discourse-graphql/graphql',
        params: { query: query },
        headers: {
          'Api-Key': api_key,
          'Api-Username': api_username
        }

      expect(response.status).to eq(200)
      expect(response.parsed_body["data"]).to be_present
    end
  end
end
