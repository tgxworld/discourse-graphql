DiscourseGraphQL::Engine.routes.draw do
  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/discourse-graphql/graphql"
  end

  post "/graphql" => "graphql#execute"
end
