module DiscourseGraphQL
  class Engine < ::Rails::Engine
    engine_name "DiscourseGraphQL".freeze
    isolate_namespace DiscourseGraphQL

    config.after_initialize do
      Discourse::Application.routes.append do
        mount ::DiscourseGraphQL::Engine, at: "/discourse-graphql"
      end
    end
  end
end
