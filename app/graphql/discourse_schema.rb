# frozen_string_literal: true

require_relative 'loaders/record_loader'

class DiscourseSchema < GraphQL::Schema
  # mutation(Types::MutationType)
  query(Types::QueryType)

  # Opt in to the new runtime (default in future graphql-ruby versions)
  use GraphQL::Execution::Interpreter
  use GraphQL::Analysis::AST

  # Add built-in connections for pagination
  use GraphQL::Pagination::Connections
  use GraphQL::Execution::Errors

  use GraphQL::Batch
end
