require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:admin)
  fab!(:user)
  fab!(:moderator)
  let!(:api_key) { Fabricate(:api_key, user: admin) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => admin.username } }
  let(:list_query) do
    "query Settings($first: Int, $after: String, $names: [String!], $plugin: String) { adminSiteSettings(first: $first, after: $after, names: $names, plugin: $plugin) { nodes { name displayName type category plugin valueWire defaultWire secret themeable } pageInfo { endCursor hasNextPage } } }"
  end
  let(:single_query) do
    "query Setting($name: String!) { adminSiteSetting(name: $name) { name valueWire type secret } currentUser { id } }"
  end
  let(:update_query) do
    "mutation Change($changes: [SiteSettingChangeInput!]!) { updateSiteSettings(changes: $changes) { success errors { code message } } }"
  end
  let(:count_query) do
    "query Count($name: String!, $value: String!) { siteSettingAffectedUserCount(name: $name, valueWire: $value) }"
  end

  describe "#execute" do
    it "reads native definitions and exact single settings without returning the locale sentinel" do
      names = %w[title checklist_enabled min_post_length]
      get "/admin/site_settings.json", params: { names: names }, headers: headers
      native = response.parsed_body.fetch("site_settings")
      result = graphql(query: list_query, variables: { names: names, first: 100 })
      expect(result["errors"]).to be_blank
      nodes = result.dig("data", "adminSiteSettings", "nodes")
      expect(nodes.map { |node| node.fetch("name") }).to eq(
        native.map { |node| node.fetch("setting") },
      )
      nodes.each do |node|
        source = native.find { |setting| setting.fetch("setting") == node.fetch("name") }
        expect(node).to include(
          "valueWire" => source["value"],
          "defaultWire" => source["default"],
          "type" => source["type"],
        )
      end
      result = graphql(query: single_query, variables: { name: "title" })
      expect(result.dig("data", "adminSiteSetting")).to include(
        "name" => "title",
        "valueWire" => SiteSetting.title,
      )
      expect(
        graphql(query: single_query, variables: { name: "max_category_nesting" }).dig(
          "data",
          "adminSiteSetting",
        ),
      ).to be_nil
      expect(
        graphql(query: single_query, variables: { name: "missing_setting" }).dig(
          "data",
          "adminSiteSetting",
        ),
      ).to be_nil
    end

    it "preserves native route denial for anonymous, member and moderator actors" do
      [
        {},
        *[user, moderator].map do |actor|
          { "Api-Key" => Fabricate(:api_key, user: actor).key, "Api-Username" => actor.username }
        end,
      ].each do |request_headers|
        result =
          graphql(
            query: single_query,
            variables: {
              name: "s3_secret_access_key",
            },
            request_headers: request_headers,
          )
        expect(result.dig("data", "adminSiteSetting")).to be_nil
        expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
        original = SiteSetting.title
        result =
          graphql(
            query: update_query,
            variables: {
              changes: [{ name: "title", valueWire: "Unauthorized title" }],
            },
            request_headers: request_headers,
          )
        expect(result.dig("data", "updateSiteSettings", "errors", 0, "code")).to eq("NOT_FOUND")
        expect(SiteSetting.title).to eq(original)
      end
    end

    it "retains custom staff and admin route constraints with native request metadata" do
      original = SiteSetting.title
      matcher =
        lambda do |request|
          request.path == "/admin/site_settings/bulk_update.json" && request.put? &&
            request.path_parameters[:controller] == "admin/site_settings" &&
            request.path_parameters[:action] == "update" && request.params["id"] == "bulk_update" &&
            request.params.dig("settings", "title", "value") == "Blocked by native hook"
        end
      AdminConstraint.any_instance.stubs(:custom_admin_check).with(&matcher).returns(false)
      result =
        graphql(
          query: update_query,
          variables: {
            changes: [{ name: "title", valueWire: "Blocked by native hook" }],
          },
        )
      expect(result.dig("data", "updateSiteSettings", "errors", 0, "code")).to eq("NOT_FOUND")
      expect(SiteSetting.title).to eq(original)
    end

    it "retains staff constraint hooks for administrators" do
      original = SiteSetting.title
      StaffConstraint.any_instance.stubs(:custom_staff_check).returns(false)

      result = graphql(query: single_query, variables: { name: "title" })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      result =
        graphql(
          query: update_query,
          variables: {
            changes: [{ name: "title", valueWire: "Denied by staff hook" }],
          },
        )
      expect(result.dig("data", "updateSiteSettings", "errors", 0, "code")).to eq("NOT_FOUND")
      expect(SiteSetting.title).to eq(original)
    end

    it "retains native paths and request bodies under a site subfolder" do
      set_subfolder "/forum"
      matcher =
        lambda do |request|
          request.path == "/forum/admin/site_settings/bulk_update.json" &&
            request.script_name == "/forum" && request.put? &&
            JSON.parse(request.raw_post).dig("settings", "title", "value") == "Subfolder update"
        end
      AdminConstraint.any_instance.stubs(:custom_admin_check).with(&matcher).returns(true)

      post "/discourse-graphql/graphql",
           params: {
             query: update_query,
             variables: {
               changes: [{ name: "title", valueWire: "Subfolder update" }],
             },
           },
           headers: headers,
           env: {
             "SCRIPT_NAME" => "/forum",
           },
           as: :json

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("data", "updateSiteSettings", "success")).to eq(true),
      response.parsed_body.inspect
      expect(SiteSetting.title).to eq("Subfolder update")
    end

    it "uses native wire parsing, staff logs, events and plugin enablement updates" do
      rules = [
        { "ground" => "Be considerate", "explanation" => "Explain disagreements respectfully" },
      ]
      changes = [
        { name: "title", valueWire: "Configured through GraphQL" },
        { name: "allow_user_locale", valueWire: "false" },
        { name: "suggested_topics", valueWire: "1,000" },
        { name: "top_menu", valueWire: "latest|new|top|categories" },
        { name: "dsa_community_rules", valueWire: rules.to_json },
      ]
      events =
        DiscourseEvent.track_events(:site_setting_changed) do
          graphql(query: update_query, variables: { changes: changes })
        end
      expect(response.parsed_body.dig("data", "updateSiteSettings", "success")).to eq(true),
      response.parsed_body.inspect
      expect(SiteSetting.title).to eq("Configured through GraphQL")
      expect(SiteSetting.allow_user_locale).to eq(false)
      expect(SiteSetting.suggested_topics).to eq(1000)
      expect(SiteSetting.top_menu).to eq("latest|new|top|categories")
      expect(JSON.parse(SiteSetting.dsa_community_rules)).to eq(rules)
      expect(events.map { |event| event.fetch(:params).first.to_s }).to include(
        "title",
        "dsa_community_rules",
      )
      expect(UserHistory.where(acting_user_id: admin.id, subject: "title").exists?).to eq(true)
      result = graphql(query: single_query, variables: { name: "title" })
      expect(result.dig("data", "adminSiteSetting", "valueWire")).to eq(
        "Configured through GraphQL",
      )
      result = graphql(query: single_query, variables: { name: "dsa_community_rules" })
      expect(JSON.parse(result.dig("data", "adminSiteSetting", "valueWire"))).to eq(rules)
    end

    it "retains hidden, unconfigurable and invalid setting policies" do
      original = SiteSetting.max_category_nesting
      result =
        graphql(
          query: update_query,
          variables: {
            changes: [{ name: "max_category_nesting", valueWire: "3" }],
          },
        )
      expect(result.dig("data", "updateSiteSettings", "success")).to eq(false)
      expect(SiteSetting.max_category_nesting).to eq(original)
      result =
        graphql(
          query: update_query,
          variables: {
            changes: [{ name: "clear_cache!", valueWire: "" }],
          },
        )
      expect(result.dig("data", "updateSiteSettings", "success")).to eq(false)
      result =
        graphql(
          query: update_query,
          variables: {
            changes: [{ name: "min_post_length", valueWire: "-10" }],
          },
        )
      expect(result.dig("data", "updateSiteSettings", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      Discourse.plugins_by_name.fetch("checklist").stubs(:configurable?).returns(false)
      expect(
        graphql(query: single_query, variables: { name: "checklist_enabled" }).dig(
          "data",
          "adminSiteSetting",
        ),
      ).to be_nil
      result =
        graphql(
          query: update_query,
          variables: {
            changes: [{ name: "checklist_enabled", valueWire: "false" }],
          },
        )
      expect(result.dig("data", "updateSiteSettings", "success")).to eq(false)
    end

    it "applies plugin disablement before a later root mutation in the same request" do
      SiteSetting.checklist_enabled = true
      checklist_post = Fabricate(:post, user: admin, raw: "- [ ] GraphQL setting boundary")
      checklist_post.rebake!
      original = checklist_post.raw
      query =
        'mutation Disable($input: ChecklistUpdateInput!) { configuration: updateSiteSettings(changes: [{ name: "checklist_enabled", valueWire: "false" }]) { success } later: updateChecklist(input: $input) { success } }'
      input = {
        postId: checklist_post.id.to_s,
        expectedRaw: original,
        expectedUpdatedAt: checklist_post.updated_at.iso8601(3),
        mutationId: "setting-disable",
        toggles: [{ checkboxIndex: 0, checkboxSource: "0:0", checked: true }],
      }

      result = graphql(query: query, variables: { input: input })

      expect(result.dig("data", "configuration", "success")).to eq(true)
      expect(result.dig("data", "later")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      expect(checklist_post.reload.raw).to eq(original)
      expect(checklist_post.revisions).to be_empty
      expect(SiteSetting.checklist_enabled).to eq(false)
    end

    it "retains native affected counts and explicit user preference backfill" do
      SiteSetting.default_email_in_reply_to = true
      user.user_option.update!(email_in_reply_to: true)
      result =
        graphql(
          query: count_query,
          variables: {
            name: "default_email_in_reply_to",
            value: "false",
          },
        )
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "siteSettingAffectedUserCount")).to eq(
        UserOption.human_users.where(email_in_reply_to: true).count.to_s,
      )
      result =
        graphql(
          query: update_query,
          variables: {
            changes: [{ name: "default_email_in_reply_to", valueWire: "false", backfill: false }],
          },
        )
      expect(result.dig("data", "updateSiteSettings", "success")).to eq(true)
      expect(user.user_option.reload.email_in_reply_to).to eq(true)
      graphql(
        query: update_query,
        variables: {
          changes: [{ name: "default_email_in_reply_to", valueWire: "true" }],
        },
      )
      result =
        graphql(
          query: update_query,
          variables: {
            changes: [{ name: "default_email_in_reply_to", valueWire: "false", backfill: true }],
          },
        )
      expect(result.dig("data", "updateSiteSettings", "success")).to eq(true)
      expect(user.user_option.reload.email_in_reply_to).to eq(false)
      result = graphql(query: count_query, variables: { name: "title", value: "Other title" })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
    end

    it "paginates native ordering and rejects changed cursor context" do
      variables = { names: %w[title site_description min_post_length], first: 2 }
      result = graphql(query: list_query, variables: variables)
      expect(result["errors"]).to be_blank
      first = result.dig("data", "adminSiteSettings")
      cursor = first.dig("pageInfo", "endCursor")
      expect(cursor).to be_present
      result = graphql(query: list_query, variables: variables.merge(after: cursor))
      second = result.dig("data", "adminSiteSettings")
      expect(
        (first.fetch("nodes") + second.fetch("nodes")).map { |node| node.fetch("name") },
      ).to contain_exactly("default_locale", "title", "site_description", "min_post_length")
      expect(second.fetch("pageInfo")).to eq("endCursor" => nil, "hasNextPage" => false)
      [
        variables.merge(first: 1, after: cursor),
        variables.merge(names: ["title"], after: cursor),
        variables.merge(after: "invalid"),
        variables.merge(first: 101),
      ].each do |invalid|
        result = graphql(query: list_query, variables: invalid)
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
    end

    it "uses native metadata modifiers without a value fallback" do
      plugin = Discourse.plugins_by_name.fetch("discourse-graphql")
      modifier = ->(setting) do
        setting[:setting].to_s == "title" ? setting.except(:value) : setting
      end
      DiscoursePluginRegistry.register_modifier(plugin, :site_setting_result, &modifier)
      begin
        result = graphql(query: single_query, variables: { name: "title" })
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "adminSiteSetting", "valueWire")).to be_nil
      ensure
        DiscoursePluginRegistry.unregister_modifier(plugin, :site_setting_result, &modifier)
      end
    end

    it "preserves valid browser CSRF headers and form tokens" do
      sign_in(admin)
      get "/session/csrf.json"
      token = response.parsed_body.fetch("csrf")
      ActionController::Base.allow_forgery_protection = true
      begin
        result =
          graphql(
            query: update_query,
            variables: {
              changes: [{ name: "title", valueWire: "Header token update" }],
            },
            request_headers: {
              "X-CSRF-Token" => token,
            },
          )
        expect(result.dig("data", "updateSiteSettings", "success")).to eq(true)
        post "/discourse-graphql/graphql",
             params: {
               query: update_query,
               variables: { changes: [{ name: "title", valueWire: "Form token update" }] }.to_json,
               authenticity_token: token,
             }
        expect(response.parsed_body.dig("data", "updateSiteSettings", "success")).to eq(true)
        expect(SiteSetting.title).to eq("Form token update")
      ensure
        ActionController::Base.allow_forgery_protection = false
      end
    end

    it "allows only native archive recovery selections before executing writes" do
      SiteSetting.site_archived = true
      begin
        original = SiteSetting.title
        result =
          graphql(
            query: update_query,
            variables: {
              changes: [{ name: "title", valueWire: "Blocked on archive" }],
            },
          )
        expect(result.dig("data", "updateSiteSettings", "success")).to eq(false)
        expect(SiteSetting.title).to eq(original)
        query =
          'mutation { recovery: updateSiteSettings(changes: [{ name: "site_archived", valueWire: "false" }]) { success } forbidden: createTopic(input: { title: "A topic while archived", raw: "A detailed topic which must never be published." }) { status } }'
        graphql(query: query)
        expect(response.status).to eq(503)
        expect(SiteSetting.site_archived).to eq(true)
        graphql(query: "mutation { __typename }")
        expect(response.status).to eq(503)
        query =
          'mutation Recovery($skip: Boolean!) { ...RecoveryFields __typename } fragment RecoveryFields on Mutation { ignored: createTopic(input: { title: "Skipped archived topic", raw: "This skipped mutation must not create any content." }) @skip(if: $skip) { status } restored: updateSiteSettings(changes: [{ name: "site_archived", valueWire: "false" }]) { success } }'
        result = graphql(query: query, variables: { skip: true })
        expect(response.status).to eq(200)
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "restored", "success")).to eq(true)
        expect(SiteSetting.site_archived).to eq(false)
        expect(Topic.where(title: "Skipped archived topic")).to be_empty
      ensure
        SiteSetting.site_archived = false
      end
    end

    it "keeps readonly, GET mutation and restricted credential protections" do
      get "/discourse-graphql/graphql",
          params: {
            query: update_query,
            variables: { changes: [{ name: "title", valueWire: "GET attempt" }] }.to_json,
          },
          headers: headers
      expect(response.status).to eq(400)
      Discourse.enable_readonly_mode
      begin
        graphql(
          query: update_query,
          variables: {
            changes: [{ name: "title", valueWire: "Readonly attempt" }],
          },
        )
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
      api_key.update!(
        scope_mode: :read_only,
        api_key_scopes: [ApiKeyScope.new(resource: "global", action: "read")],
      )
      graphql(query: single_query, variables: { name: "title" })
      expect(response.status).to eq(403)
      get "/discourse-graphql/graphql",
          params: {
            query: single_query,
            variables: { name: "title" }.to_json,
          },
          headers: headers
      expect(response.parsed_body.dig("data", "adminSiteSetting", "name")).to eq("title")
      put "/admin/site_settings/default_email_in_reply_to/user_count.json",
          params: {
            default_email_in_reply_to: "false",
          },
          headers: headers
      expect(response.status).to eq(404)
      get "/discourse-graphql/graphql",
          params: {
            query: count_query,
            variables: { name: "default_email_in_reply_to", value: "false" }.to_json,
          },
          headers: headers
      expect(response.parsed_body.dig("data", "siteSettingAffectedUserCount")).to be_nil
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
    end

    it "filters secret literals, variable objects, legacy variable strings and native child parameters" do
      secret = "graphqlauditsecret93847"
      captured = []
      subscriber =
        ActiveSupport::Notifications.subscribe(
          /(?:start_processing|process_action)\.action_controller/,
        ) do |*arguments|
          payload = arguments.last
          captured << payload.slice(:params, :path)
        end
      begin
        result =
          graphql(
            query: update_query,
            variables: {
              changes: [{ name: "s3_secret_access_key", valueWire: secret }],
            },
          )
        expect(result.dig("data", "updateSiteSettings", "success")).to eq(true)
        post "/discourse-graphql/graphql",
             params: {
               query: update_query,
               variables: {
                 changes: [{ name: "s3_secret_access_key", valueWire: secret }],
               }.to_json,
             },
             headers: headers
        literal =
          'mutation { updateSiteSettings(changes: [{ name: "s3_secret_access_key", valueWire: "' +
            secret + '" }]) { success } }'
        get "/discourse-graphql/graphql", params: { query: literal }, headers: headers
        expect(response.status).to eq(400)
        expect(captured).to be_present
        expect(captured.to_json).not_to include(secret)
        expect(captured.to_json).to include("[FILTERED]")
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end

    it "rechecks administrator role before exposing current values" do
      expect(
        graphql(query: single_query, variables: { name: "title" }).dig("data", "adminSiteSetting"),
      ).to be_present
      admin.update!(admin: false)
      result = graphql(query: single_query, variables: { name: "s3_secret_access_key" })
      expect(result.dig("data", "adminSiteSetting")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
    end

    it "bounds changes, filter sizes and expensive aliases before native writes" do
      original = SiteSetting.title
      [
        [],
        [{ name: "title", valueWire: "One" }, { name: "title", valueWire: "Two" }],
        51.times.map { |index| { name: "setting_#{index}", valueWire: "value" } },
      ].each do |changes|
        result = graphql(query: update_query, variables: { changes: changes })
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      result =
        graphql(
          query: list_query,
          variables: {
            names: 101.times.map { |index| "setting_#{index}" },
          },
        )
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      query =
        '{ one: adminSiteSetting(name: "title") { name } two: adminSiteSetting(name: "title") { name } three: adminSiteSetting(name: "title") { name } }'
      result = graphql(query: query)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(SiteSetting.title).to eq(original)
    end
  end

  private

  def graphql(query:, variables: {}, request_headers: headers)
    post "/discourse-graphql/graphql",
         params: {
           query: query,
           variables: variables,
         },
         headers: request_headers,
         as: :json
    response.parsed_body
  end
end
