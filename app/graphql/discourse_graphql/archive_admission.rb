module DiscourseGraphQL
  class ArchiveAdmission
    def self.allowed?(query)
      return false unless query.valid? && query.selected_operation&.operation_type == "mutation"

      root = query.schema.mutation
      pending = query.selected_operation.selections.dup
      visited = Set.new
      fragments = Set.new
      substantive = false
      until pending.empty?
        node = pending.pop
        next unless visited.add?(node.object_id)
        included = GraphQL::Execution::DirectiveChecks.include?(node.directives, query)
        next unless included

        case node
        when GraphQL::Language::Nodes::Field
          next if node.name == "__typename"
          field = query.get_field(root, node.name)
          unless field.respond_to?(:allows_archived_requests?) && field.allows_archived_requests?
            return false
          end
          substantive = true
        when GraphQL::Language::Nodes::FragmentSpread
          pending << query.fragments.fetch(node.name) if fragments.add?(node.name)
        when GraphQL::Language::Nodes::InlineFragment, GraphQL::Language::Nodes::FragmentDefinition
          if node.type
            type = query.get_type(node.type.name)
            compatible =
              type == root || (type&.kind&.abstract? && query.possible_types(type).include?(root))
            next unless compatible
          end
          pending.concat(node.selections)
        end
      end
      substantive
    end
  end
end
