# API contracts

These contracts define intended behavior. Implementation and runtime verification remain in progress. The capability ledger records delivery status.

## Transport and identity

The endpoint is `/discourse-graphql/graphql`. POST accepts a single JSON object containing `query`, optional `variables`, and optional `operationName`. Existing form requests and JSON strings for variables remain supported. Variables must decode to an object. Request arrays are rejected.

GET accepts query operations only, using the same parameters. A mutation sent through GET is rejected before execution. Anonymous queries use the same public access rules as Discourse. `currentUser` is nullable and returns null for an anonymous actor. A private site still requires authentication.

Browser sessions retain Discourse CSRF verification for POST. API credentials retain their existing exemption only when Discourse authenticates them. An invalid or revoked credential never falls back to anonymous access or a browser session. Credentials restricted to existing controller actions do not automatically gain GraphQL access. Existing read credentials may use GET where their existing method rules allow it. POST does not become permitted merely because the operation is a query.

Authenticated responses are private. A disabled GraphQL plugin returns HTTP 404. Invalid transport input returns HTTP 400. Authentication and CSRF failures return HTTP 403. Executed GraphQL operations return HTTP 200 with the standard `data` and `errors` envelope, including validation failures that prevent execution.

## Errors and partial results

GraphQL errors expose a human readable message and a stable `extensions.code`. Initial codes are `BAD_REQUEST`, `GRAPHQL_PARSE_FAILED`, `GRAPHQL_VALIDATION_FAILED`, `BAD_USER_INPUT`, `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `FEATURE_DISABLED`, `QUERY_TOO_COMPLEX`, `QUERY_TOO_DEEP`, `RATE_LIMITED`, `UNAVAILABLE`, and `INTERNAL_ERROR`. Error responses must not expose backtraces, exception class names, secrets or hidden resource details.

Execution errors include the GraphQL response path where available. A denied resource follows the existing Discourse distinction between forbidden and not found. Nullable fields allow unrelated permitted selections to succeed. A required field propagates null according to GraphQL semantics. Validation and cost rejection occur before execution and return no data.

Mutation contracts must distinguish successful persistence, approval pending, invalid input and rate limiting. Expected domain failures use typed mutation errors with `code`, `message`, optional `field` segments and optional `retryAfterSeconds`. Unexpected failures use the top level GraphQL error envelope. A client must not retry a mutation automatically unless the owning Discourse operation guarantees that retry is safe. Each mutation slice defines its success payload and reconciliation behavior before implementation.

## Collections

The original `categories`, `latestTopics` and `search` fields retain their array response shape. `latestTopics` retains zero based `page` continuation and adds an optional `limit`, with default 30 and maximum 50. Each page uses the same limit. An empty page establishes completion. Ordering and filtering follow the owning Discourse query, so a changing topic list can move between requests. Clients reconcile repeated records by ID.

Search uses the native one based full page convention and native search page size. Omitted or null pages start at 1, pages below 1 normalize to 1, and values above SearchController::PAGE_LIMIT are rejected. Search reuses the native anonymous permission, shared rate limits and overload checks. Logging, request metadata and search events retain their native behavior. An overloaded search returns UNAVAILABLE before executing the search. Categories follow the existing permitted category list behavior. Their detailed bounds remain part of the discovery audit.

New collections use a consistent connection shape with `nodes` and `pageInfo`, including `endCursor` and `hasNextPage`. Each collection defines its filters, ordering, maximum page size, cursor validity and empty state before implementation. Cursors are opaque and tied to the operation and filters. The API does not promise a database snapshot across live changes.

The foundation accepts `latestTopics(limit: 1, page: 0)` and continuation at page 1. Omitted or null page and limit arguments use their defaults. It rejects zero, negative and greater than 50 limits with `BAD_USER_INPUT`. Negative pages are invalid. Bounds are validated before loading collections.

## Query work

Every collection contributes its maximum selected breadth to query cost. Aliases and distinct argument selections count toward total work. The initial depth limit is 12 and the initial complexity limit is 10,000. These are admission limits, not measured latency budgets, and may be tightened based on benchmark evidence before release.

Standard schema introspection is exempt from the application field depth limit. Native post creation carries a base cost of 1,000 plus selected response fields, so a request cannot bundle ten creation operations even if it selects only their status.

The implementation must demonstrate that rejected operations do not perform their protected collection loading work. Successful nested requests are measured separately at small and large page sizes, including authorization queries. Numerical latency, memory and throughput budgets remain mandatory and will be frozen after the baseline is measured.

## Optional capabilities

The intended discovery field is `capabilities`, exposing capability IDs, availability and supported operation names without revealing protected settings or resource details. Plugin fields are registered only when their owning plugin is installed and loaded. A loaded plugin's fields remain stable while its site setting changes. Disabled execution returns `FEATURE_DISABLED`, with nullable results preserving unrelated selections. Disabling the GraphQL plugin itself disables the endpoint.

This is a required future slice. No optional adapter is verified until its schema, discovery, enabled, disabled and absent installation cases pass.

## Uploads and live delivery

Upload contracts must identify the reusable upload reference, existing transport, validation and processing outcomes. The forum journey must include an upload followed by a rejected submission and a corrected submission that reuses the permitted upload. A lost mutation response requires an explicit reconciliation path rather than an assumed safe retry.

The live contract remains incomplete. Before live implementation, define transport, subscription authorization, event identity, ordering, resume tokens, replay bounds, duplicate handling, gap recovery, terminal states, queue limits and disconnect cleanup. A replay gap must instruct the client to reload authoritative content and unread state. Access changes are checked again at delivery and replay boundaries. Existing MessageBus request identity caching does not prove that requirement.

## Topic lookup

`topic(id: ID!)` returns typed topic metadata. Missing and inaccessible resources both return null without exposing existence or interrupting permitted sibling fields. Personal messages return a null category. Record loading and authorization are batched separately through the existing ActiveRecord source and Guardian bulk topic permission interface. Authorization results are cached within one request only, and a later request rechecks changed membership. Mutation slices must invalidate affected loader state before a subsequent mutation or selection can observe it.

## Topic post pages

`topicPosts(topicId: ID!, first: Int, after: String)` returns `nodes` and `pageInfo`. It uses the native TopicView page ordering and filters. The default page size is 20, the maximum is 50, and omitted or null size uses the default. Invalid sizes return BAD_USER_INPUT.

The end cursor is signed and binds the native next page number, page size, topic, actor and site. Continuing requires the same page size. A cursor for another topic or actor, a malformed cursor, or a changed page size returns BAD_USER_INPUT. An empty terminal page has no cursor and hasNextPage is false. Native filtering can produce a page with fewer visible nodes, so clients follow hasNextPage rather than assuming a short page is terminal.

Every page constructs the native topic view and rechecks its access. Inaccessible topic pages retain native access errors, represented by GraphQL errors at topicPosts. Permitted sibling selections can still succeed. Post content, raw visibility and displayed author fields delegate to the existing serializers. Hidden or ignored content and whispers retain their native protections.

## Topic and reply creation

`createTopic(input: CreateTopicInput!)` and `createPost(input: CreatePostInput!)` use the native post creation action. Their payload exposes status, native action, permitted post data, pending count and typed errors. Status is PUBLISHED for an immediate post, PENDING for native approval queues, HANDLED for another successful native handler without an immediate post, and FAILED for a native rejection.

Creation preserves NewPostManager, plugin parameter and actor modifiers, validation, restrictions, rate limits, events and native API memoization. It does not accept bypass flags. Native API memoization remains the only retry guarantee: an identical native API creation request inside its native memoization window can return the original result. Browser and user API clients must reconcile uncertain outcomes rather than assume retry safety.

The adapter processes one fixed native action and accepts only explicitly typed creation inputs. The outer GraphQL controller owns notification clearing and session refresh. Native child processing skips those two shared callbacks while retaining the native action's other callbacks and owned logic. Browser cookie and server session objects remain attached to the real request lifecycle. The adapter explicitly delegates login requirement metadata to its native superclass because the native class instance metadata is not inherited automatically. All request dependent owner behavior used by this action must have an HTTP contract.

Request loader caches clear between serial creation mutations. Native validation and policy failures become typed payload errors, including retry guidance when native rate limiting supplies it. An outer transport rejection, including CSRF or readonly rejection, keeps its native HTTP status.
