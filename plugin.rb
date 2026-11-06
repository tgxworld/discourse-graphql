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

ActiveSupport::Inflector.inflections(:en) { |inflect| inflect.acronym("GraphQL") }

require_relative "lib/discourse_graphql/engine"
