require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:admin)
  let!(:api_key) { Fabricate(:api_key, user: admin) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => admin.username } }
  let(:choice_query) { 'query Options($name: String!, $first: Int!, $after: String) { adminSiteSetting(name: $name) { choices(first: $first, after: $after) { totalCount nodes { name valueWire nativeName id } pageInfo { endCursor hasNextPage } } validValues(first: $first) { totalCount nodes { name valueWire nativeName id } } } }' }

  describe "#execute" do
    it "returns native scalar editor hints, upload metadata and placeholder forms" do
      SiteSetting.logo = Fabricate(:upload)
      SiteSetting.ai_discover_enabled = false
      names = %w[title min_post_length min_password_length tag_style llms_txt logo top_menu discourse_connect_provider_secrets ai_discover_enabled]
      native = native_settings(names: names)
      query = 'query Editor($name: String!) { adminSiteSetting(name: $name) { name keywords preview textarea disabled allowAny listType translateNames minimum maximum mandatoryValuesWire disallowedGroupsWire requiresConfirmation dependsBehavior dependentSettingDisplay authorizedExtensions maxFileSizeKb placeholder { text key value } upload { originalFilename humanFilesize width height } defaultOverride { oldDefault newDefault changeSettingName } } }'

      names.each do |name|
        source = native.find { |setting| setting.fetch("setting") == name }
        expect(source).to be_present
        result = graphql(query: query, variables: { name: name })
        expect(result["errors"]).to be_blank
        setting = result.dig("data", "adminSiteSetting")
        expect(setting["disabled"]).to eq(source["disabled"])
        expect(setting).to include("name" => name, "keywords" => source["keywords"], "preview" => source["preview"], "textarea" => source["textarea"], "allowAny" => source["allow_any"], "listType" => source["list_type"], "translateNames" => source["translate_names"], "minimum" => source["min"]&.to_s, "maximum" => source["max"]&.to_s, "mandatoryValuesWire" => source["mandatory_values"], "disallowedGroupsWire" => source["disallowed_groups"], "requiresConfirmation" => source["requires_confirmation"], "dependsBehavior" => source["depends_behavior"], "dependentSettingDisplay" => source["dependent_setting_display"], "authorizedExtensions" => source["authorized_extensions"], "maxFileSizeKb" => source["max_file_size_kb"]&.to_s)
        if source["placeholder"].is_a?(Hash)
          expect(setting["placeholder"]).to eq("text" => nil, "key" => source.dig("placeholder", "key"), "value" => source.dig("placeholder", "value"))
        elsif source["placeholder"]
          expect(setting["placeholder"]).to eq("text" => source["placeholder"], "key" => nil, "value" => nil)
        else
          expect(setting["placeholder"]).to be_nil
        end
        if source["upload"]
          expect(setting["upload"]).to eq("originalFilename" => source.dig("upload", "original_filename"), "humanFilesize" => source.dig("upload", "human_filesize"), "width" => source.dig("upload", "width"), "height" => source.dig("upload", "height"))
        end
        if source["upcoming_change_default_override_metadata"]
          expect(setting["defaultOverride"]).to eq("oldDefault" => source.dig("upcoming_change_default_override_metadata", "old_default"), "newDefault" => source.dig("upcoming_change_default_override_metadata", "new_default"), "changeSettingName" => source.dig("upcoming_change_default_override_metadata", "change_setting_name"))
        end
      end
    end

    it "paginates every native language choice and preserves locale option metadata" do
      native = native_settings(names: %w[highlighted_languages default_locale])
      languages = native.find { |setting| setting["setting"] == "highlighted_languages" }.fetch("choices")
      expect(languages.size).to be > 100
      result = graphql(query: choice_query, variables: { name: "highlighted_languages", first: 100 })
      expect(result["errors"]).to be_blank
      page = result.dig("data", "adminSiteSetting", "choices")
      expect(page["totalCount"]).to eq(languages.size)
      expect(page.fetch("nodes").map { |choice| choice.fetch("valueWire") }).to eq(languages.first(100))
      result = graphql(query: choice_query, variables: { name: "highlighted_languages", first: 100, after: page.dig("pageInfo", "endCursor") })
      page = result.dig("data", "adminSiteSetting", "choices")
      expect(page.fetch("nodes").map { |choice| choice.fetch("valueWire") }).to eq(languages.drop(100))
      expect(page["pageInfo"]).to eq("endCursor" => nil, "hasNextPage" => false)

      result = graphql(query: choice_query, variables: { name: "default_locale", first: 100 })
      values = result.dig("data", "adminSiteSetting", "validValues", "nodes")
      locales = native.find { |setting| setting["setting"] == "default_locale" }.fetch("valid_values")
      expect(values).to eq(locales.map { |locale| { "name" => locale["name"], "valueWire" => locale["value"], "nativeName" => locale["native_name"], "id" => nil } })
    end

    it "preserves native omissions, empty choices, zero and false without model fallbacks" do
      with_modifier do |setting|
        next setting unless setting[:setting].to_s == "title"
        setting.except(:min, :placeholder).merge(choices: [0, false, "", { name: "Zero", value: 0, id: "zero" }, { name: "False", value: false }, { name: "No supplied value" }], valid_values: [], min: 0, textarea: false)
      end
      query = 'query { adminSiteSetting(name: "title") { minimum textarea placeholder { text } choices { nodes { name valueWire id } } validValues { totalCount nodes { valueWire } pageInfo { hasNextPage endCursor } } } }'

      result = graphql(query: query)

      expect(result["errors"]).to be_blank
      setting = result.dig("data", "adminSiteSetting")
      expect(setting).to include("minimum" => "0", "textarea" => false, "placeholder" => nil)
      expect(setting.dig("choices", "nodes")).to eq([
        { "name" => "0", "valueWire" => "0", "id" => nil },
        { "name" => "false", "valueWire" => "false", "id" => nil },
        { "name" => "", "valueWire" => "", "id" => nil },
        { "name" => "Zero", "valueWire" => "0", "id" => "zero" },
        { "name" => "False", "valueWire" => "false", "id" => nil },
        { "name" => "No supplied value", "valueWire" => nil, "id" => nil },
      ])
      expect(setting["validValues"]).to eq("totalCount" => 0, "nodes" => [], "pageInfo" => { "hasNextPage" => false, "endCursor" => nil })
    end

    it "returns native dependency descriptors without applying their policy" do
      native = native_settings(names: ["mcp_oauth_client_id_metadata_domains"]).find { |setting| setting["setting"] == "mcp_oauth_client_id_metadata_domains" }
      query = 'query { adminSiteSetting(name: "mcp_oauth_client_id_metadata_domains") { dependsBehavior dependentSettingDisplay dependencies { totalCount nodes { name displayName allowedValuesWire } } } }'

      result = graphql(query: query)

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "adminSiteSetting", "dependsBehavior")).to eq(native["depends_behavior"])
      expect(result.dig("data", "adminSiteSetting", "dependencies", "nodes")).to eq(native.fetch("depends_on").each_with_index.map { |name, index| { "name" => name, "displayName" => native.fetch("depends_on_humanized_names")[index], "allowedValuesWire" => native.fetch("depends_on_values")[name].map(&:to_s) } })
    end

    it "exposes every native objects schema through named typed property pages" do
      names = %w[dsa_community_rules oauth2_user_field_mappings openid_connect_user_field_mappings]
      native = native_settings(names: names)
      query = 'query Objects($name: String!) { adminSiteSetting(name: $name) { objectSchema { name identifier properties(first: 100) { totalCount nodes { name definition { type required textarea validations { minLength maxLength } } } pageInfo { hasNextPage } } } } }'

      names.each do |name|
        source = native.find { |setting| setting["setting"] == name }.fetch("schema")
        result = graphql(query: query, variables: { name: name })
        expect(result["errors"]).to be_blank
        schema = result.dig("data", "adminSiteSetting", "objectSchema")
        expect(schema).to include("name" => source["name"], "identifier" => source["identifier"])
        expect(schema.dig("properties", "totalCount")).to eq(source.fetch("properties").size)
        expect(schema.dig("properties", "nodes")).to eq(source.fetch("properties").map do |property_name, definition|
          validations = definition["validations"]
          { "name" => property_name, "definition" => { "type" => definition["type"], "required" => definition["required"], "textarea" => definition["textarea"], "validations" => validations && { "minLength" => validations["min_length"]&.to_s, "maxLength" => validations["max_length"]&.to_s } } }
        end)
      end
    end

    it "exposes every bundled JSON schema without serializing a generic JSON field" do
      names = %w[ai_sentiment_model_configs map_events_to_color map_events_title]
      native = native_settings(names: names)
      query = 'query Schema($name: String!) { adminSiteSetting(name: $name) { jsonSchema { type uniqueItems items { type title format required properties(first: 10) { nodes { name definition { type description format enumValuesWire defaultWire } } } } } } }'

      names.each do |name|
        source = native.find { |setting| setting["setting"] == name }.fetch("json_schema")
        result = graphql(query: query, variables: { name: name })
        expect(result["errors"]).to be_blank
        schema = result.dig("data", "adminSiteSetting", "jsonSchema")
        expect(schema).to include("type" => source["type"], "uniqueItems" => source["uniqueItems"])
        expect(schema.fetch("items")).to include("type" => source.dig("items", "type"), "title" => source.dig("items", "title"), "format" => source.dig("items", "format"), "required" => source.dig("items", "required"))
        expect(schema.dig("items", "properties", "nodes")).to eq(source.dig("items", "properties").map { |property_name, definition| { "name" => property_name, "definition" => { "type" => definition["type"], "description" => definition["description"], "format" => definition["format"], "enumValuesWire" => definition["enum"], "defaultWire" => definition["default"] } } })
      end
    end

    it "rejects changed metadata cursors and oversized or excessive nested selections" do
      result = graphql(query: choice_query, variables: { name: "highlighted_languages", first: 2 })
      expect(result["errors"]).to be_blank
      cursor = result.dig("data", "adminSiteSetting", "choices", "pageInfo", "endCursor")
      expect(cursor).to be_present
      [0, 101].each do |first|
        result = graphql(query: choice_query, variables: { name: "highlighted_languages", first: first })
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      result = graphql(query: choice_query, variables: { name: "highlighted_languages", first: 3, after: cursor })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      variant = :changed
      with_modifier do |setting|
        next setting unless setting[:setting].to_s == "highlighted_languages"
        case variant
        when :changed
          setting.merge(choices: ["changed"])
        when :reordered
          setting.merge(choices: setting.fetch(:choices).reverse)
        when :removed
          setting.except(:choices)
        end
      end
      %i[changed reordered removed].each do |current_variant|
        variant = current_variant
        result = graphql(query: choice_query, variables: { name: "highlighted_languages", first: 2, after: cursor })
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      query = '{ adminSiteSettings(first: 100) { nodes { choices(first: 100) { nodes { name valueWire nativeName } } } } }'
      result = graphql(query: query)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
    end

    it "retains administrator access checks for nested metadata" do
      query = '{ adminSiteSetting(name: "ai_sentiment_model_configs") { jsonSchema { items { properties { nodes { name } } } } } }'
      [{}, { "Api-Key" => Fabricate(:api_key, user: Fabricate(:user)).key }].each do |request_headers|
        result = graphql(query: query, request_headers: request_headers)
        expect(result.dig("data", "adminSiteSetting")).to be_nil
        expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      end
    end

    it "rejects oversized constraint arrays visibly instead of truncating them" do
      values = 101.times.map { |index| "constraint_#{index}" }
      with_modifier do |setting|
        next setting unless setting[:setting].to_s == "title"
        setting.merge(keywords: values, json_schema: { type: "object", required: values, enum: values })
      end
      query = '{ adminSiteSetting(name: "title") { keywords jsonSchema { type required enumValuesWire } } }'

      result = graphql(query: query)

      expect(result.dig("data", "adminSiteSetting", "keywords")).to be_nil
      expect(result.dig("data", "adminSiteSetting", "jsonSchema")).to eq("type" => "object", "required" => nil, "enumValuesWire" => nil)
      expect(result.fetch("errors").map { |error| error.dig("extensions", "code") }).to eq(["BAD_USER_INPUT"] * 3)
    end

    it "binds metadata cursors to their collection kind and administrator" do
      with_modifier { |setting| setting[:setting].to_s == "title" ? setting.merge(choices: %w[first second third], valid_values: %w[first second third]) : setting }
      result = graphql(query: choice_query, variables: { name: "title", first: 2 })
      expect(result["errors"]).to be_blank
      cursor = result.dig("data", "adminSiteSetting", "choices", "pageInfo", "endCursor")
      query = 'query Other($after: String!) { adminSiteSetting(name: "title") { validValues(first: 2, after: $after) { nodes { valueWire } } } }'

      result = graphql(query: query, variables: { after: cursor })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")

      other_admin = Fabricate(:admin)
      other_key = Fabricate(:api_key, user: other_admin)
      result = graphql(query: choice_query, variables: { name: "title", first: 2, after: cursor }, request_headers: { "Api-Key" => other_key.key, "Api-Username" => other_admin.username })
      expect(result.dig("data", "adminSiteSetting", "choices")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "retains aliased fragment cursors and validates count only continuations" do
      query = 'query Cursor($include: Boolean!) { adminSiteSetting(name: "highlighted_languages") { options: choices(first: 2) { totalCount status: pageInfo { ...MetadataCursor } } } } fragment MetadataCursor on PageInfo { cursor: endCursor @include(if: $include) more: hasNextPage }'
      result = graphql(query: query, variables: { include: true })
      expect(result["errors"]).to be_blank
      page = result.dig("data", "adminSiteSetting", "options")
      cursor = page.dig("status", "cursor")
      expect(cursor).to be_present
      expect(page.dig("status", "more")).to eq(true)
      result = graphql(query: query, variables: { include: false })
      expect(result.dig("data", "adminSiteSetting", "options", "status")).to eq("more" => true)

      query = 'query Count($after: String!) { adminSiteSetting(name: "highlighted_languages") { choices(first: 2, after: $after) { totalCount } } }'
      result = graphql(query: query, variables: { after: cursor })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "adminSiteSetting", "choices", "totalCount")).to eq(page["totalCount"])
      result = graphql(query: query, variables: { after: "invalid" })
      expect(result.dig("data", "adminSiteSetting", "choices")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "accepts the established metadata cursor format after shared paging changes" do
      values = %w[first second third]
      with_modifier { |setting| setting[:setting].to_s == "title" ? setting.merge(choices: values) : setting }
      payload = { "kind" => "choices", "digest" => Digest::SHA256.hexdigest(JSON.generate(values)), "first" => 1, "actor_id" => admin.id, "site" => RailsMultisite::ConnectionManagement.current_db, "offset" => 1 }
      cursor = Rails.application.message_verifier("discourse_graphql_setting_metadata").generate(payload)

      result = graphql(query: choice_query, variables: { name: "title", first: 1, after: cursor })

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "adminSiteSetting", "choices", "nodes").map { |choice| choice["valueWire"] }).to eq(["second"])
    end
  end

  after do
    if @modifier
      DiscoursePluginRegistry.unregister_modifier(Discourse.plugins_by_name.fetch("discourse-graphql"), :site_setting_result, &@modifier)
    end
  end

  private

  def with_modifier(&block)
    @modifier = block
    DiscoursePluginRegistry.register_modifier(Discourse.plugins_by_name.fetch("discourse-graphql"), :site_setting_result, &block)
  end

  def native_settings(names:)
    get "/admin/site_settings.json", params: { names: names }, headers: headers
    expect(response.status).to eq(200)
    response.parsed_body.fetch("site_settings")
  end

  def graphql(query:, variables: {}, request_headers: headers)
    post "/discourse-graphql/graphql", params: { query: query, variables: variables }, headers: request_headers, as: :json
    response.parsed_body
  end
end
