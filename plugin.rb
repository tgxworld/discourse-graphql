# frozen_string_literal: true

# name: discourse-graphql
# about: Adds a GraphQL endpoint to Discourse
# version: 0.1
# authors: tgxworld
# url: https://github.com/tgxworld
# gemfile: true

require "graphql"
require "graphql/c_parser"

enabled_site_setting :discourse_graphql_enabled

module ::DiscourseGraphQL
  PLUGIN_NAME = "discourse-graphql"
end

ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym("GraphQL")
end

load File.expand_path('lib/discourse_graphql/engine.rb', __dir__)

after_initialize do
end
