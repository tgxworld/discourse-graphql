DiscourseGraphQL::Engine.routes.draw do
  get "/graphql" => "graphql#execute"
  post "/graphql" => "graphql#execute"
end
