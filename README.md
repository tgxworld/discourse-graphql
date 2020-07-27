# DiscourseGraphQL

Unofficial Discourse GraphQL API.

## Installation

Follow [Install a Plugin](https://meta.discourse.org/t/install-a-plugin/19157)
how-to from the official Discourse Meta, using `git clone https://github.com/tgxworld/discourse-graphql.git`
as the plugin command.

## Usage

```
require "graphql/client"
require "graphql/client/http"

module DiscourseAPI
  HTTP = GraphQL::Client::HTTP.new("http://localhost:3000/discourse-graphql/graphql") do
    def headers(context)
      { "Api-Key": 'ef984ff3d0d242998b7df8eaa975229e4ce07c19500b55baa181fc7abd2fd04b', "Api-Username": 'system' }
    end
  end

  Schema = GraphQL::Client.load_schema(HTTP)

  Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
end

Query = DiscourseAPI::Client.parse(<<~QUERY)
query {
  latestTopics {
    fancyTitle
  }
}
QUERY

DiscourseAPI::Client.query(Query).latest_topics.each do |topic|
  puts topic.fancy_title
end
```

## Feedback

If you have issues or suggestions for the plugin, please bring them up on
[Discourse Meta](https://meta.discourse.org).
