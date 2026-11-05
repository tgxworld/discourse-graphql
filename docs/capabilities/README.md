# Capability inventory and coverage

The supported revision and generated operation surface are recorded in [native-operations.md](native-operations.md). The complete records are in [native-operations.jsonl](native-operations.jsonl). [coverage.json](coverage.json) records reviewed links between native actions, implemented GraphQL fields, authorization requirements, request evidence and remaining work.

All broad feature families remain incomplete in the [delivery ledger](../coverage.md). A native route, schema field or evidence filename alone does not prove a capability complete. Several GraphQL fields can cover parts of one native action. One native protocol can also support several capabilities without becoming a GraphQL field itself.

## Reproduction

Run the generator through the session DV against the pinned Discourse checkout with every bundled plugin loaded:

```bash
dv run --name graphql-revival-01a1aaad -- env RAILS_ENV=test LOAD_PLUGINS=1 bin/rails runner plugins/discourse-graphql/script/inventory_capabilities.rb /var/www/discourse/plugins/discourse-graphql/docs/capabilities/native-operations.jsonl
```

It writes the JSONL inventory and a Markdown summary beside it. It rejects a native revision that differs from the reviewed coverage file, unknown GraphQL fields, missing evidence files, missing bundled plugins and stale shared capability assessments. These checks establish structural consistency. The request suites and client journeys establish behavior separately.

The generator runs in a fresh test process. It enables route source capture and reloads the route definitions within that process. It reads metadata and source files without executing controller actions or permission predicates. Setting names and sections are recorded without live setting values.

## Records

Each JSONL line is an independent object with a `kind`:

Native source paths use the Discourse checkout root. GraphQL evidence paths use this plugin's root.

| Kind | Contents |
|---|---|
| `inventory` | Native revision, format and scope |
| `core_sources` | Core service, model, serializer, provider, API scope, API schema and setting sources |
| `plugin_sources` | Every bundled plugin's source surface, setting names, registration candidates and shared assessment |
| `controller` | Routed action definitions, native request spec references, login metadata and ordered callback references |
| `callback` | Native filter source, phase, conditions and known required plugin |
| `operation` | Native controller and action, every route alias, mounts, router guards, parameter metadata, GraphQL mappings and status |
| `other_endpoint` | Mounted Rack applications and other handlers requiring native protocol assessment |

Child engine paths retain their mount list. For example, `/api/channels` mounted under `/chat` identifies `/chat/api/channels`. Router guards remain distinct from default parameter objects. A `StaffConstraint` object placed in route defaults does not become an executable router guard. Native controller callbacks still require their own audit.

Ruby call references and frontend registration candidates identify source locations for review. They do not establish that a branch executes or that all transitive helper policies have been audited. Some provider engines compiled before route source capture retain a null route source with their inherited mount ownership. Their controller definitions and plugin route files remain available for review.

## Shared capabilities and native routes

Plugins without dedicated controller actions remain in scope. Their explicit assessments cover rendering, provider protocols, configuration, calendar behavior and presence through shared native entry points. Styleguide has a native developer page and shared site capability metadata. Its access restrictions still require verification.

Unresolved Ruby action names remain visible in the inventory. Some come from resource scaffolds. MessageBus polling is served by middleware configured before routing, so its missing named Ruby controller does not establish a missing transport. Each entry retains a source assessment instead of causing a fabricated GraphQL field.

The native anonymous Chat anchor defect remains separately recorded in [native dependencies](../native-dependencies.md). Generic error containment does not satisfy that recovery requirement.

## Inspect one operation

Use Python's standard JSON module to inspect a record without requiring additional command line tools:

```bash
python3 - <<'PY'
import json
from pathlib import Path

inventory = Path("plugins/discourse-graphql/docs/capabilities/native-operations.jsonl")
for line in inventory.open():
    record = json.loads(line)
    if record["kind"] == "operation" and record["id"] == "chat/api/channels#index":
        print(json.dumps(record, indent=2))
PY
```


## Bundled configuration discovery

[plugin-settings.json](plugin-settings.json) records a value free native HTTP comparison for every bundled plugin. Reproduce it with `tgx-dv test --name <owned-container> --env LOAD_PLUGINS=1 --seed 23293 plugins/discourse-graphql/spec/requests/discourse_graphql/bundled_settings_spec.rb`. The case derives its 47 plugin inputs from the pinned core tracked files, verifies every loaded owner and compares all visible definitions through complete GraphQL page traversal. It emits counts and setting type names without saving current values. This establishes shared configuration discovery. Configuration writes and plugin feature completion remain separately required.
