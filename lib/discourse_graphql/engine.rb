module DiscourseGraphQL
  class Engine < ::Rails::Engine
    engine_name "DiscourseGraphQL".freeze
    isolate_namespace DiscourseGraphQL

    initializer "discourse_graphql.optional_adapters", before: :setup_main_autoloader do
      if !Discourse.plugins_by_name.key?("chat")
        Rails.autoloaders.main.ignore(config.root.join("app/graphql/discourse_graphql/chat"))
      end
    end

    config.after_initialize do
      Discourse::Application.routes.append do
        mount ::DiscourseGraphQL::Engine, at: "/discourse-graphql"
      end
    end
  end
end
