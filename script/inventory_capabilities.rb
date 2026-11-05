require "json"
require "open3"
require "prism"
require "digest"
require "yaml"
require "fileutils"

abort "Run this inventory in test with LOAD_PLUGINS=1." unless Rails.env.test? && ENV["LOAD_PLUGINS"] == "1"
abort "Provide one destination JSONL path." unless ARGV.one?

module DiscourseGraphQL
  class CapabilityInventory
    def self.summary(inventory:)
      operations = inventory.fetch(:operations)
      counts = operations.group_by { |operation| operation.fetch(:owner) }.transform_values(&:size)
      lines = [
        "# Native capability inventory",
        "",
        "Supported Discourse revision: `#{inventory.fetch(:discourse_revision)}`.",
        "",
        "This snapshot contains #{operations.size} routed action names, #{inventory.fetch(:controllers).size} controllers and #{inventory.fetch(:other_endpoints).size} other endpoints. Counts describe investigation surfaces. Capability acceptance requires reviewed contracts and executed evidence.",
        "",
        "## Owners and shared surfaces",
        "",
        "| Owner | Routed actions | Settings | Shared surfaces |",
        "|---|---|---|---|",
        "| Core | #{counts.fetch("core", 0)} | #{inventory.fetch(:core).fetch(:settings).size} | Core capabilities and native protocols |",
      ]
      inventory.fetch(:plugins).each do |plugin|
        assessment = plugin.fetch(:shared_assessment)
        surfaces = assessment ? assessment.fetch("required_surfaces").join(", ") : "Shared source audit pending"
        lines << "| `#{plugin.fetch(:id)}` | #{counts.fetch(plugin.fetch(:id), 0)} | #{plugin.fetch(:settings).size} | #{surfaces} |"
      end
      lines.concat([
        "",
        "## Existing GraphQL mappings",
        "",
        "These links cover declared adapter slices. The remaining native action capabilities stay incomplete.",
        "",
        "| Native action | GraphQL fields | Status |",
        "|---|---|---|",
      ])
      operations.select { |operation| operation.fetch(:graphql_operations).any? }.each do |operation|
        fields = operation.fetch(:graphql_operations).map { |field| "`#{field}`" }.join(", ")
        lines << "| `#{operation.fetch(:id)}` | #{fields} | #{operation.fetch(:status)} |"
      end
      lines.concat([
        "",
        "## Native route resolution",
        "",
        "These entries need their native capability assessment retained. A resource route with no Ruby action does not establish a GraphQL operation.",
        "",
        "| Native route | Resolution name | Assessment |",
        "|---|---|---|",
      ])
      operations.select { |operation| operation.key?(:resolution_error) }.each do |operation|
        lines << "| `#{operation.fetch(:id)}` | `#{operation.fetch(:resolution_error).fetch(:name)}` | #{operation.fetch(:native_assessment).fetch("classification")} |"
      end
      lines.join("\n") + "\n"
    end

    def initialize
      @root = Rails.root.to_s
      @plugins = git_output(arguments: ["ls-files", "plugins/*/plugin.rb"]).lines.map { |line| line.split("/")[1] }.sort
      @operations = {}
      @controllers = {}
      @callbacks = {}
      @other_endpoints = []
      @definitions = {}
    end

    def call
      missing = @plugins - Discourse.plugins.map(&:directory_name)
      raise "Bundled plugins are not loaded: #{missing.join(", ")}" if missing.any?

      ActionDispatch::Routing::Mapper.route_source_locations = true
      Rails.application.reload_routes!
      collect_routes(route_set: Rails.application.routes, mounts: [], constraints: [], ancestors: [], owner_hint: "core")
      revision = git_output(arguments: ["rev-parse", "HEAD"]).strip
      coverage = reviewed_coverage(revision: revision)
      coverage.fetch("operations").each { |id, mapping| @operations.fetch(id).merge!(mapping.transform_keys(&:to_sym)) }
      coverage.fetch("native_route_assessments").each { |id, assessment| @operations.fetch(id)[:native_assessment] = assessment }
      {
        format_version: 1,
        discourse_revision: revision,
        scope: "Native operation and source inventory. Authorization and GraphQL coverage require review.",
        core: {
          service_files: Dir[File.join(@root, "app/services/**/*.rb")].sort.map { |file| relative_source(file) },
          model_files: Dir[File.join(@root, "app/models/**/*.rb")].sort.map { |file| relative_source(file) },
          serializer_files: Dir[File.join(@root, "app/serializers/**/*.rb")].sort.map { |file| relative_source(file) },
          api_schema_files: Dir[File.join(@root, "spec/requests/api/schemas/**/*.{rb,json}")].sort.map { |file| relative_source(file) },
          provider_files: Dir[File.join(@root, "lib/auth/**/*.rb")].sort.map { |file| relative_source(file) },
          api_scope_files: Dir[File.join(@root, "{app,lib}/**/*api_key_scop*.rb")].sort.map { |file| relative_source(file) },
          settings: setting_sources(directory: @root, filename: "site_settings.yml"),
        },
        plugins: @plugins.map { |name| plugin_sources(name).merge(shared_assessment: coverage.fetch("shared_plugin_assessments")[name]) },
        controllers: @controllers.sort.to_h,
        callbacks: @callbacks.sort.to_h,
        operations: @operations.sort.map { |_key, operation| operation },
        other_endpoints: @other_endpoints.sort_by { |endpoint| [endpoint.fetch(:owner), endpoint.fetch(:path)] },
      }
    end

    private

    def git_output(arguments:)
      output, status = Open3.capture2("git", "-C", @root, *arguments)
      raise "Git inventory command failed." unless status.success?
      output
    end

    def collect_routes(route_set:, mounts:, constraints:, ancestors:, owner_hint:)
      raise "A recursive engine mount requires review." if ancestors.include?(route_set.object_id)

      route_set.routes.each do |route|
        owner = route.source_location ? owner_for(route.source_location) : owner_hint
        next unless owner == "core" || @plugins.include?(owner)

        app = route.app
        guards = constraints + route_guards(app)
        route_data = {
          verb: route.verb,
          path: route.path.spec.to_s,
          mounts: mounts,
          source: relative_source(route.source_location),
          owner: owner,
          owner_evidence: route.source_location ? "route_source" : "inherited_mount",
          constraints: guards,
          parameter_constraints: route.requirements.except(:controller, :action).transform_values { |value| route_parameter(value) },
          internal: !!route.internal,
        }
        if app.engine?
          collect_routes(
            route_set: app.rack_app.routes,
            mounts: mounts + [{ path: route_data.fetch(:path), source: route_data.fetch(:source) }],
            constraints: guards,
            ancestors: ancestors + [route_set.object_id],
            owner_hint: owner,
          )
        elsif route.requirements[:controller].is_a?(String) && route.requirements[:action].is_a?(String)
          collect_operation(route: route, owner: owner, route_data: route_data)
        else
          endpoint = app.rack_app
          source = endpoint.respond_to?(:source_location) ? endpoint.source_location : endpoint.method(:call).source_location
          @other_endpoints << route_data.merge(
            owner: owner,
            endpoint_class: endpoint.is_a?(Module) ? endpoint.name : endpoint.class.name,
            endpoint_source: source && source_reference(source),
            assessment: "pending",
          )
        end
      end
    end

    def collect_operation(route:, owner:, route_data:)
      controller_path = route.requirements.fetch(:controller)
      action = route.requirements.fetch(:action)
      key = "#{controller_path}##{action}"
      operation =
        @operations[key] ||= {
          id: key,
          owner: owner,
          controller: "#{controller_path.camelize}Controller",
          action: action,
          routes: [],
          authorization_audit: "pending",
          graphql_operations: [],
          graphql_tests: [],
          status: "incomplete",
        }
      operation.fetch(:routes) << route_data

      controller = operation.fetch(:controller).constantize
      metadata = @controllers[controller.name] ||= controller_metadata(controller)
      return if metadata.fetch(:actions).key?(action)

      method = controller.instance_method(action)
      source = method.source_location
      metadata.fetch(:actions)[action] = {
        source: source && source_reference(source),
        public_action: controller.action_methods.include?(action),
        references: source ? method_references(source: source, name: method.original_name.to_s) : {},
      }
    rescue NameError => error
      operation[:resolution_error] = { class: error.class.name, name: error.name.to_s }
    end

    def reviewed_coverage(revision:)
      plugin_root = File.expand_path("..", __dir__)
      coverage = JSON.parse(File.read(File.join(plugin_root, "docs/capabilities/coverage.json")))
      raise "Coverage targets another native revision." unless coverage.fetch("discourse_revision") == revision

      roots = { "query" => DiscourseGraphQL::Schema.query, "mutation" => DiscourseGraphQL::Schema.mutation }
      coverage.fetch("operations").each do |id, mapping|
        raise "Unknown native operation: #{id}" unless @operations.key?(id)
        raise "Mapped native operation has no Ruby action: #{id}" if @operations.fetch(id).key?(:resolution_error)

        mapping.fetch("graphql_operations").each do |operation|
          root, field = operation.split(".", 2)
          raise "Unknown GraphQL operation: #{operation}" unless roots.fetch(root).fields.key?(field)
        end
        mapping.fetch("graphql_tests").each do |file|
          raise "Missing GraphQL evidence file: #{file}" unless File.file?(File.join(plugin_root, file))
        end
      end

      assessments = coverage.fetch("shared_plugin_assessments")
      owners = @operations.values.map { |operation| operation.fetch(:owner) }
      (@plugins - owners).each do |name|
        raise "Missing shared capability assessment: #{name}" unless assessments.key?(name)
      end
      assessments.each do |name, assessment|
        raise "Unknown bundled plugin: #{name}" unless @plugins.include?(name)
        if assessment.fetch("dedicated_controller_actions") != owners.include?(name)
          raise "Controller surface changed for #{name}, review its shared assessment."
        end
        assessment.fetch("native_source_files").each do |file|
          raise "Missing native assessment source: #{file}" unless File.file?(File.join(@root, file))
        end
      end
      route_assessments = coverage.fetch("native_route_assessments")
      @operations.each do |id, operation|
        if operation.key?(:resolution_error) && !route_assessments.key?(id)
          raise "Missing native route assessment: #{id}"
        end
      end
      route_assessments.each do |id, assessment|
        raise "Native route resolution changed: #{id}" unless @operations.fetch(id).key?(:resolution_error)
        assessment.fetch("native_source_files").each do |file|
          raise "Missing native route source: #{file}" unless File.file?(File.join(@root, file))
        end
      end
      coverage
    end

    def controller_metadata(controller)
      {
        superclass: controller.superclass.name,
        login_requirement: controller.respond_to?(:requires_login_arg) ? controller.requires_login_arg : nil,
        callbacks: controller._process_action_callbacks.map { |callback| register_callback(callback: callback, controller: controller) },
        native_request_specs: request_specs_for(controller.name),
        actions: {},
      }
    end

    def register_callback(callback:, controller:)
      filter = callback.filter
      definition =
        if filter.is_a?(Symbol)
          method = controller.instance_method(filter)
          { method: filter.to_s, owner: method.owner.name, source: method.source_location && source_reference(method.source_location) }
        else
          callable_reference(filter)
        end
      if filter.is_a?(Proc) && filter.source_location&.first == ApplicationController.method(:requires_plugin).source_location&.first &&
           filter.binding.local_variable_defined?(:plugin_name)
        plugin_name = filter.binding.local_variable_get(:plugin_name)
        definition[:required_plugin] = plugin_name if plugin_name.is_a?(String) && Discourse.plugins_by_name.key?(plugin_name)
      end
      descriptor = {
        phase: callback.kind.to_s,
        filter: definition,
        if: callback.instance_variable_get(:@if).map { |condition| condition_reference(condition) },
        unless: callback.instance_variable_get(:@unless).map { |condition| condition_reference(condition) },
      }
      key = "#{callback.kind}:#{definition[:method] || definition[:source] || definition[:class]}:#{Digest::SHA256.hexdigest(JSON.generate(descriptor))[0, 12]}"
      @callbacks[key] = descriptor
      key
    end

    def condition_reference(condition)
      if condition.is_a?(Symbol)
        { method: condition.to_s }
      elsif condition.is_a?(AbstractController::Callbacks::ActionFilter)
        {
          action_filter: condition.instance_variable_get(:@conditional_key).to_s,
          actions: condition.instance_variable_get(:@actions).to_a.sort,
        }
      else
        callable_reference(condition)
      end
    end

    def callable_reference(callable)
      { class: callable.class.name, source: callable.respond_to?(:source_location) ? source_reference(callable.source_location) : nil }
    end

    def route_guards(app)
      return [] unless app.respond_to?(:constraints)

      app.constraints.map do |constraint|
        method = constraint.respond_to?(:matches?) ? constraint.method(:matches?) : constraint.method(:call)
        source = constraint.is_a?(Proc) ? constraint.source_location : method.source_location
        entry = { class: constraint.class.name, source: source && source_reference(source) }
        entry[:require_master] = !!constraint.instance_variable_get(:@require_master) if constraint.is_a?(AdminConstraint)
        entry
      end
    end

    def route_parameter(value)
      case value
      when String, Numeric, NilClass, TrueClass, FalseClass
        value
      when Symbol
        value.to_s
      when Regexp
        { regexp: value.source, options: value.options }
      else
        { class: value.class.name, assessment: "non_scalar_route_default, not an executable route constraint" }
      end
    end

    def method_references(source:, name:)
      file, line = source
      definitions =
        @definitions[file] ||= begin
          methods = {}
          walk(Prism.parse_file(file).value) do |node|
            methods[[node.name.to_s, node.location.start_line]] = node if node.is_a?(Prism::DefNode)
          end
          methods
        end
      definition = definitions[[name, line]]
      return { extraction: "dynamic definition requires review" } unless definition

      calls = []
      permission_calls = []
      local_calls = []
      walk(definition.body) do |node|
        next unless node.is_a?(Prism::CallNode)

        if node.receiver.is_a?(Prism::ConstantReadNode) || node.receiver.is_a?(Prism::ConstantPathNode)
          calls << "#{node.receiver.location.slice.gsub(/\s+/, "")}.#{node.name}" if %i[call new run run! execute].include?(node.name)
        end
        permission_calls << node.location.start_line if node.name.to_s.match?(/\A(?:can_|ensure_|authorize|require_)/)
        local_calls << node.name.to_s if node.receiver.nil?
      end
      { constant_calls: calls.uniq.sort, permission_call_lines: permission_calls.uniq.sort, local_calls: local_calls.uniq.sort }
    end

    def walk(node, &block)
      return unless node
      yield node
      node.child_nodes.compact.each { |child| walk(child, &block) }
    end

    def plugin_sources(name)
      directory = File.join(@root, "plugins", name)
      plugin = Discourse.plugins.find { |instance| instance.directory_name == name }
      source_files = Dir[File.join(directory, "{app,lib,config,spec}", "**", "*.{rb,yml,json}")].sort
      extensions = extension_sources(directory)
      providers = source_files.grep(/authenticator|auth_provider|omniauth/).map { |file| relative_source(file) }
      providers << "plugins/#{name}/plugin.rb" if extensions.any? { |extension| extension[:hook] == "auth_provider" }
      {
        id: name,
        registered_name: plugin.name,
        enabled_setting: plugin.enabled_site_setting,
        controller_files: source_files.grep(%r{/app/controllers/}).map { |file| relative_source(file) },
        service_files: source_files.grep(%r{/app/services/}).map { |file| relative_source(file) },
        model_files: source_files.grep(%r{/app/models/}).map { |file| relative_source(file) },
        serializer_files: source_files.grep(%r{/app/serializers/}).map { |file| relative_source(file) },
        provider_files: providers.sort,
        api_schema_files: source_files.grep(%r{/schemas/}).map { |file| relative_source(file) },
        route_files: source_files.grep(%r{/(?:config/routes\.rb|app/routes/)}).map { |file| relative_source(file) },
        extension_sources: extensions,
        settings: setting_sources(directory: directory),
        non_route_assessment: "pending, rendering, providers, preferences, live behavior and internal services require review",
      }
    end

    def extension_sources(directory)
      ruby_hooks = Plugin::Instance.public_instance_methods(false).select { |name| name.to_s.match?(/\A(?:register_|add_)/) }
      ruby_hooks = (ruby_hooks + %i[auth_provider add_admin_route on]).uniq - [:register_svg_icon]
      ruby_sources = Dir[File.join(directory, "{plugin.rb,lib/**/*.rb}")].sort.flat_map do |file|
        references = []
        walk(Prism.parse_file(file).value) do |node|
          next unless node.is_a?(Prism::CallNode) && ruby_hooks.include?(node.name)

          arguments = node.arguments&.arguments || []
          names = arguments.first(2).filter_map do |argument|
            argument.unescaped if argument.is_a?(Prism::SymbolNode) || argument.is_a?(Prism::StringNode)
          end
          references << { source: source_reference([file, node.location.start_line]), hook: node.name.to_s, names: names, kind: "ruby_call_candidate" }
        end
        references
      end
      pattern = /\b(decorateCooked|decorateCookedElement|modifyClass|addPostMenuButton|registerToolbar|registerRichEditorExtension|registerMarkdownItPlugin|registerOption|setupMarkdownIt)\s*\(/
      frontend_sources = Dir[File.join(directory, "{assets,frontend}/**/*.{js,gjs,ts,gts}")].sort.flat_map do |file|
        File.readlines(file).each_with_index.filter_map do |line, index|
          hooks = line.scan(pattern).flatten.uniq.sort
          { source: source_reference([file, index + 1]), hooks: hooks, kind: "frontend_call_candidate" } if hooks.any?
        end
      end
      ruby_sources + frontend_sources
    end

    def setting_sources(directory:, filename: "settings.yml")
      file = File.join(directory, "config", filename)
      return [] unless File.file?(file)

      YAML.safe_load_file(file, permitted_classes: [Date], aliases: true).flat_map do |section, settings|
        next [] unless settings.is_a?(Hash)
        settings.keys.sort.map { |name| { name: name.to_s, section: section.to_s, source: relative_source(file) } }
      end
    end

    def request_specs_for(controller_name)
      @request_specs ||= Dir[File.join(@root, "{spec,plugins/*/spec}", "requests", "**", "*.rb")].sort.group_by do |file|
        File.read(file)[/RSpec\.describe\s+(?:::)?([\w:]+Controller)\b/, 1]
      end
      Array(@request_specs[controller_name]).map { |file| relative_source(file) }
    end

    def owner_for(source)
      relative_source(source).to_s[%r{\Aplugins/([^/]+)/}, 1] || "core"
    end

    def source_reference(source)
      source && "#{relative_source(source[0])}:#{source[1]}"
    end

    def relative_source(source)
      return nil if source.nil?
      source = source.to_s
      return source.delete_prefix("#{@root}/") if source.start_with?("#{@root}/")
      return "gems/#{source.split("/gems/").last}" if source.include?("/gems/")
      return source unless source.start_with?("/")
      File.basename(source)
    end
  end
end

destination = Pathname.new(ARGV.fetch(0)).expand_path
inventory = DiscourseGraphQL::CapabilityInventory.new.call
FileUtils.mkdir_p(destination.dirname)
File.open(destination, "w") do |file|
  file.puts JSON.generate(kind: "inventory", format_version: inventory.fetch(:format_version), discourse_revision: inventory.fetch(:discourse_revision), scope: inventory.fetch(:scope))
  file.puts JSON.generate(kind: "core_sources", **inventory.fetch(:core))
  inventory.fetch(:plugins).each { |plugin| file.puts JSON.generate(kind: "plugin_sources", **plugin) }
  inventory.fetch(:controllers).each { |name, controller| file.puts JSON.generate(kind: "controller", name: name, **controller) }
  inventory.fetch(:callbacks).each { |id, callback| file.puts JSON.generate(kind: "callback", id: id, **callback) }
  inventory.fetch(:operations).each { |operation| file.puts JSON.generate(kind: "operation", **operation) }
  inventory.fetch(:other_endpoints).each { |endpoint| file.puts JSON.generate(kind: "other_endpoint", **endpoint) }
end
File.write(destination.sub_ext(".md"), DiscourseGraphQL::CapabilityInventory.summary(inventory: inventory))
puts JSON.generate(path: destination.to_s, plugins: inventory.fetch(:plugins).size, operations: inventory.fetch(:operations).size, controllers: inventory.fetch(:controllers).size, unresolved_native_routes: inventory.fetch(:operations).count { |operation| operation.key?(:resolution_error) })
