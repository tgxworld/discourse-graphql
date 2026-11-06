# Discourse GraphQL

A typed GraphQL adapter for Discourse and its bundled plugins. Native Discourse remains responsible for permissions, validation, rendering, rate limits and side effects.

This revival is in progress. The [coverage ledger](docs/coverage.md) and [native dependencies](docs/native-dependencies.md) describe required work that remains incomplete. The current implementation is not a completed production release.

## Compatibility and installation

The supported Discourse commit is recorded in [.discourse-version](.discourse-version). CI checks that exact revision with all bundled plugins loaded. Other revisions remain unverified.

Add `git clone https://github.com/tgxworld/discourse-graphql.git` to your Discourse plugin installation configuration and rebuild. The `discourse_graphql_enabled` site setting controls the endpoint. Dependencies are pinned in Gemfile.lock, including graphql-ruby and its compiled C parser.

## Requests

The endpoint is `/discourse-graphql/graphql`. Use existing Discourse credentials. Set DISCOURSE_URL, DISCOURSE_API_KEY and DISCOURSE_API_USERNAME in your environment, then run:

```bash
curl --get "$DISCOURSE_URL/discourse-graphql/graphql" \
  --header "Api-Key: $DISCOURSE_API_KEY" \
  --header "Api-Username: $DISCOURSE_API_USERNAME" \
  --data-urlencode 'query={ currentUser { id username } capabilities { id available } }'
```

GET executes queries. Mutations require POST. Browser sessions retain native CSRF protection. Credential restrictions remain enforced, and unsupported granular scopes fail closed. Public reads retain their native visibility rules.

See [API conventions and operations](docs/api.md) for inputs, pagination, typed errors, uploads, optional plugin behavior and recovery after ambiguous mutation responses. Standard GraphQL introspection provides the current schema.

## Verification

From the supported Discourse checkout with the plugin installed:

```bash
RAILS_ENV=test LOAD_PLUGINS=1 ENABLE_LOGSTASH_LOGGER=0 bin/rspec plugins/discourse-graphql/spec
```

This discovers request, middleware and performance cases. Performance observations that expose unresolved native limitations remain explicitly marked as incomplete in the coverage and dependency records. Passing these characterization cases does not establish final latency, allocation, memory or concurrent throughput budgets.

The CI workflow also checks fresh processes with optional adapters enabled, disabled and absent, then regenerates the native operation inventory and rejects drift. The workflow pins its Discourse revision, test container and checkout action.

For an owned TGX development environment, run the same suite with `tgx-dv test --name <owned-container> --env LOAD_PLUGINS=1 --env ENABLE_LOGSTASH_LOGGER=0 plugins/discourse-graphql/spec`. Existing `script/measure_*_spec.rb` commands remain available as wrappers around the discovered performance cases.
