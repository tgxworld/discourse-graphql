require "rails_helper"
require "open3"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:admin)
  let!(:api_key) { Fabricate(:api_key, user: admin) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => admin.username } }

  describe "#execute" do
    it "matches visible native definitions and scalar metadata across every bundled plugin" do
      tracked, status = Open3.capture2("git", "ls-files", "plugins/*/plugin.rb", chdir: Rails.root.to_s)
      expect(status.success?).to eq(true)
      names = tracked.lines.map { |path| path.split("/")[1] }.sort
      expect(names.size).to eq(47)
      plugins = names.map { |name| Discourse.plugins.find { |plugin| plugin.directory_name == name } }
      expect(plugins).not_to include(nil)
      query = <<~GRAPHQL
        query PluginSettings($plugin: String!, $after: String) {
          adminSiteSettings(plugin: $plugin, first: 25, after: $after) {
            nodes {
              name displayName type category primaryArea plugin description
              valueWire defaultWire secret themeable keywords preview textarea disabled
              allowAny listType translateNames minimum maximum mandatoryValuesWire
              disallowedGroupsWire requiresConfirmation dependsBehavior
              dependentSettingDisplay authorizedExtensions maxFileSizeKb
            }
            pageInfo { endCursor hasNextPage }
          }
        }
      GRAPHQL
      summaries = plugins.map do |plugin|
        get "/admin/site_settings.json", params: { plugin: plugin.name }, headers: headers
        expect(response.status).to eq(200), plugin.directory_name
        native = response.parsed_body.fetch("site_settings")
        expected = native.map do |setting|
          {
            "name" => setting["setting"],
            "displayName" => setting["humanized_name"],
            "type" => setting["type"],
            "category" => setting["category"],
            "primaryArea" => setting["primary_area"],
            "plugin" => setting["plugin"],
            "description" => setting["description"],
            "valueWire" => setting["value"],
            "defaultWire" => setting["default"],
            "secret" => setting["secret"],
            "themeable" => setting["themeable"],
            "keywords" => setting["keywords"],
            "preview" => setting["preview"],
            "textarea" => setting["textarea"],
            "disabled" => setting["disabled"],
            "allowAny" => setting["allow_any"],
            "listType" => setting["list_type"],
            "translateNames" => setting["translate_names"],
            "minimum" => setting["min"]&.to_s,
            "maximum" => setting["max"]&.to_s,
            "mandatoryValuesWire" => setting["mandatory_values"],
            "disallowedGroupsWire" => setting["disallowed_groups"],
            "requiresConfirmation" => setting["requires_confirmation"],
            "dependsBehavior" => setting["depends_behavior"],
            "dependentSettingDisplay" => setting["dependent_setting_display"],
            "authorizedExtensions" => setting["authorized_extensions"],
            "maxFileSizeKb" => setting["max_file_size_kb"]&.to_s,
          }
        end
        actual = []
        cursors = Set.new
        cursor = nil
        pages = 0
        loop do
          post "/discourse-graphql/graphql", params: { query: query, variables: { plugin: plugin.name, after: cursor } }, headers: headers, as: :json
          expect(response.status).to eq(200), plugin.directory_name
          result = response.parsed_body
          expect(result["errors"]).to be_blank, { plugin: plugin.directory_name, errors: result["errors"] }.inspect
          page = result.dig("data", "adminSiteSettings")
          expect(page).to be_present, plugin.directory_name
          actual.concat(page.fetch("nodes"))
          pages += 1
          break unless page.dig("pageInfo", "hasNextPage")
          cursor = page.dig("pageInfo", "endCursor")
          expect(cursor).to be_present, plugin.directory_name
          expect(cursors.add?(cursor)).to be_truthy, plugin.directory_name
          expect(pages).to be <= native.size / 25 + 1
        end
        expect(actual).to eq(expected), plugin.directory_name
        expect(actual.map { |setting| setting.fetch("name") }.uniq.size).to eq(actual.size)
        { plugin: plugin.directory_name, registered_name: plugin.name, visible_settings: actual.size, pages: pages, types: actual.map { |setting| setting.fetch("type") }.uniq.sort, result: "native parity" }
      end
      expect(summaries.sum { |summary| summary.fetch(:visible_settings) }).to be > 500
      puts JSON.generate(plugins: summaries.size, visible_settings: summaries.sum { |summary| summary.fetch(:visible_settings) }, summaries: summaries)
    end
  end
end
