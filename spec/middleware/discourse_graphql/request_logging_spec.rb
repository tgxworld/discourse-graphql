require "rails_helper"

RSpec.describe DiscourseGraphQL::RequestBodyLimit do
  it "filters GraphQL documents before the native request logger while retaining existing filters" do
    skip "Lograge replaces the native request logger." if DiscourseLograge.enabled?

    secret = "graphqlrequestsecret94736"
    query = '{ adminSiteSetting(name: "' + secret + '") { valueWire } }'
    output = StringIO.new
    sink = Logger.new(output)
    request_logger =
      SilenceLogger.new(
        ->(_environment) { [200, { "Content-Type" => "application/json" }, ["{}"]] },
      )
    request_logger.stubs(:logger).returns(sink)
    middleware = described_class.new(request_logger)
    client = Rack::MockRequest.new(middleware)
    parameters = {
      query: query,
      variables: { secret: secret }.to_json,
      password: secret,
      audit_marker: "visible",
    }

    response =
      client.get(
        "/discourse-graphql/graphql?#{Rack::Utils.build_query(parameters)}",
        "action_dispatch.parameter_filter" => Rails.application.config.filter_parameters,
      )

    expect(response.status).to eq(200)
    expect(output.string).to include("Started GET", "audit_marker=visible")
    expect(output.string).not_to include(secret)
    expect(output.string).to include("FILTERED")
    middlewares = Rails.application.config.middleware.middlewares
    expect(middlewares.index(described_class)).to be < middlewares.index(SilenceLogger)

    output.truncate(0)
    output.rewind
    client.get(
      "/unrelated?query=visible",
      "action_dispatch.parameter_filter" => Rails.application.config.filter_parameters,
    )
    expect(output.string).to include("query=visible")
  end
end
