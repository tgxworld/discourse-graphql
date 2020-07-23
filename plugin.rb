# frozen_string_literal: true

# name: DiscourseGraphQL
# about: Adds a GraphQL endpoint to Discourse
# version: 0.1
# authors: tgxworld
# url: https://github.com/tgxworld

gem 'graphql', '1.11.1'
gem 'graphiql-rails', '1.7.0', require_name: "graphiql/rails"

enabled_site_setting :discourse_graphql_enabled

PLUGIN_NAME ||= 'DiscourseGraphQL'

ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym("GraphQL")
end

load File.expand_path('lib/discourse_graphql/engine.rb', __dir__)

after_initialize do
end
