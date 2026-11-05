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

`capabilities` returns `id`, `available`, `queryFields` and `mutationFields` for implemented adapters. Availability reflects global plugin enablement, not the actor's permission to execute an operation. Core discovery lists only fields actually exposed by this schema. The first Chat capability is `chat.channelDiscovery`. It does not imply coverage of direct messages or other Chat operations.

Extensions declare their fields through a query module selected only when the owning plugin is loaded. Disabled plugins keep their fields. An absent plugin contributes no fields or reachable types. No optional adapter is verified until its schema, discovery, enabled, disabled and absent installation cases pass.

## Public Chat channel discovery

`chatChannels(first: Int, after: String, filter: String)` discovers permitted public channels through the native Chat channel index. It excludes direct message channels. Nodes expose `id`, `title`, `slug`, `description`, `status`, `threadingEnabled` and `membershipsCount` from native serialization. Native login, Chat group restrictions, category permissions, serializer modifiers and public channel enablement remain authoritative.

The adapter selects only these declared scalar attributes through the native serializer's `only` option. It intersects any existing `only` restriction and preserves `except` and inclusion predicates. This avoids evaluating unused permission metadata and message associations. A suppressed required field fails through GraphQL nullability rather than being recovered from a model.

Omitted or null `first` uses 25, with a maximum of 50 and minimum of 1. Omitted or null `filter` applies no text filter. A supplied filter follows native channel discovery matching, including category names. Continuation retains the exact filter and page size.

The signed cursor binds native offset, filter, page size, actor and site. Invalid, tampered or mismatched cursors return `BAD_USER_INPUT` at the nullable connection. To recover, restart without `after` using the intended filters and page size. Every request checks current authorization.

`hasNextPage` indicates an offered continuation. Native discovery provides no total, so a full page offers continuation even when the next page is empty. An empty terminal page returns no cursor and false `hasNextPage`. A short page also ends continuation. Ordering is native and may change between requests. Clients reconcile repeated channel IDs.

Disabling Chat returns `FEATURE_DISABLED` for this connection and preserves permitted sibling fields. Capability availability does not imply actor access. For example, Chat may be enabled while a member outside the allowed groups receives `FORBIDDEN`.

The absent plugin boot check is reproducible in the supported Discourse checkout:

```bash
RAILS_ENV=test LOAD_PLUGINS=discourse-graphql bin/rails runner plugins/discourse-graphql/script/verify_optional_schema.rb
```

It eagerly loads the application and exercises schema discovery through a real HTTP request. The ordinary request suite runs with `LOAD_PLUGINS=1`.

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

## Chat message creation

`createChatMessage(input: CreateChatMessageInput!)` accepts required `channelId` and `message`, with optional `inReplyToId`, `threadId` and `stagedId`. Its nullable payload exposes `status`, `messageId` and typed `errors`. `CREATED` means the native action returned success and a message ID. `FAILED` means the native action returned an error, with native error messages and retry guidance where supplied.

This is a text creation contract. Upload inputs, GraphQL message reading and other Chat operations remain required later slices. Clients can currently inspect authoritative history through the native Chat message endpoint.

The adapter invokes the native Chat message creation action. Native Chat groups, silencing, membership, channel status, recipient preferences, reply and thread consistency, validation, rate limiting, automatic silencing, persistence, tracking, publishing and jobs remain authoritative. No caller controlled service options or bypass flags are accepted. Root and thread replies preserve their native reading state and channel activity effects. Request loader state clears around each mutation.

The installed capability is `chat.messageCreation`, with `createChatMessage` as its mutation field. Global availability remains distinct from actor permission. Disabled Chat returns `FEATURE_DISABLED` at this nullable field and permits unrelated mutation results. Creation carries a base complexity of 1,000, so ten creations cannot execute in one request.

`stagedId` provides native event correlation. It is not a persisted unique key and does not provide deduplication. Native event processing follows persistence, so a failed or lost response does not prove that no message was committed. Do not retry automatically after an ambiguous outcome. Inspect authoritative history and keep uncertainty visible when identical messages cannot be distinguished. A `RATE_LIMITED` retry delay does not turn an otherwise ambiguous failure into a safe retry.

## Chat message history

`chatMessages(channelId: ID!, last: Int, before: String)` reads the latest channel messages and continues toward older history. Omitted or null `last` uses 25, with bounds of 1 through 50. Omitted or null `before` starts at the latest page. Each page retains native ascending chronological ordering. Clients prepend preceding pages.

The shared `pageInfo` adds `startCursor` and `hasPreviousPage`. Existing forward collections return null and false for these fields. Chat history returns a signed start cursor for each nonempty page and uses native `can_load_more_past` for `hasPreviousPage`. Its `endCursor` is null and `hasNextPage` is false, indicating that this operation navigates older history only. These values do not establish whether newer messages exist. Empty pages have no cursor.

Cursors bind the channel, page size, actor, site and exact native message ordering boundary. Changed or invalid cursors return `BAD_USER_INPUT`. A physically removed anchor follows native `NOT_FOUND` behavior. Restart without `before` using the intended channel and page size. Every page rechecks native channel permission. If native recovery resets to the latest page after an anchor becomes hidden, the adapter rejects the overlapping page with `BAD_USER_INPUT`. It never presents that page as older history. Clients reload the latest page after that error, replacing their current window rather than prepending it. No snapshot is promised across content changes.

Nodes expose native serialized content, timestamps, channel and thread IDs, streaming state and author display data. The author has a nullable ID, preserving native deleted author display without inventing identity. Native deleted message visibility and thread filtering remain authoritative. Native public anonymous preview follows the message endpoint's own rules, which differ from public channel discovery. Native viewed state updates are retained.

The installed capability is `chat.messageHistory`. Disabled Chat returns `FEATURE_DISABLED` while permitted sibling fields remain available. Native serializer field selection preserves inclusion predicates and existing restrictions. Unexpected field failures are logged on the server and return a generic `INTERNAL_ERROR` without diagnostics. They provide no rollback or retry guarantee.

The pinned native implementation has a reproduced defect when an anonymous reader continues after deletion of its anchor. The native endpoint returns HTTP 500 from `Chat::Channel::Policy::MessageExistence`. GraphQL contains that failure as `INTERNAL_ERROR`, and clients may restart this reading query without `before`. Containment does not repair the native defect. This case remains incomplete for final acceptance and requires a native correction. The native reproduction and dependency are recorded in `docs/native-dependencies.md`.

## Chat membership and reading preferences

`chatChannel(id: ID!)` returns the declared channel fields through native channel lookup and serialization. `currentUserMembership` on channel results exposes the current actor's native following, muted, notification level, star, reading and optional pin state. It is null when native serialization has no membership. These channel queries retain native login and channel access rules. Unselected membership data is omitted from channel serialization.

`joinChatChannel(channelId: ID!)`, `leaveChatChannel(channelId: ID!)`, `unfollowChatChannel(channelId: ID!)`, `starChatChannel(channelId: ID!, starred: Boolean!)`, `updateChatNotifications(input: ChatNotificationInput!)`, `markChatRead(channelId: ID!, messageId: ID!)` and `markAllChatRead` invoke fixed native actions. Their nullable payload exposes `success`, optional native `membership`, optional `updatedCount` and typed `errors`. No caller chooses the native class, action, path or HTTP method. Native verbs are fixed internally after outer GraphQL credential and CSRF checks. GET never executes these mutations.

Join follows an existing membership without duplicating it. Leaving public channels and pair direct messages preserves native unfollow behavior. Leaving a group direct message removes the actor's membership and participation. Unfollow retains native membership. Native cleanup remains available after category access loss, while joins, stars, notifications and read updates preserve their own native access checks. An acknowledgement does not manufacture membership data.

Notification inputs accept required `channelId`, optional `muted` and optional `notificationLevel`. Omitted or null preferences remain unchanged. `muted: false` is retained. An empty patch fails through native parameter validation. Notification levels derive from native model values, currently `NEVER`, `MENTION` and `ALWAYS`. Conditional pin state fields are nullable when native settings omit them.

Mark read verifies that the message belongs to the channel and prevents backward progress. Native mention updates and tracking publication remain authoritative. Bulk mark read updates the actor's native followed memberships and returns their update count without exposing the native channel identifier list. These admission weights are 1,000 for a single write and 4,000 for bulk read. Final workload benchmarks remain required.

Clients can reconcile acknowledged state through `chatChannel.currentUserMembership`. After group departure, loss of channel access is an expected result. Failed or lost responses do not guarantee rollback or safe retry. Native failure bodies without usable messages receive a generic typed operation error. Disabled Chat returns `FEATURE_DISABLED` and preserves permitted siblings. The installed capability is `chat.membershipAndReading`.

## Notification history and reading

`notifications(first: Int, after: String, filter: NotificationFilter)` reads only the current actor's native history. `filter` accepts `ALL`, `READ` or `UNREAD`. Omitted or null filters select all history. Omitted or null `first` uses 25, with minimum 1 and maximum 50. Native topic, reviewable and badge visibility checks run on every page. Anonymous requests return `UNAUTHENTICATED` at the nullable connection while permitted siblings remain available.

Nodes expose native scalar metadata: `id`, `notificationType`, `read`, `createdAt`, `topicId`, `postNumber`, `fancyTitle`, `slug`, `actingUserName` and `actingUserAvatarTemplate`. `notificationType` retains the native integer identifier. Optional native attributes remain nullable and preserve serializer inclusion rules. Generic notification data, external identity fields and provider payloads are not exposed. Structured notification variants remain incomplete.

The page exposes `seenNotificationId` and `pageInfo`. Its signed cursor binds offset, filter, page size, actor and site. Changed context or invalid bounds return `BAD_USER_INPUT`. The native count is evaluated before visibility filtering, so an empty page may still have `hasNextPage: true`. Follow the cursor until `hasNextPage` is false. Do not treat an empty page as completion.

History retains native ordering by creation time and does not establish a snapshot. Inserts, removals and permission changes can shift offset pages. After a mutation changes the selected filter, restart without `after`. For example, marking the first two unread entries read shrinks the unread list. Continuing at offset 2 can skip the next two unread entries. Reconcile repeated IDs when lists change.

`markNotificationRead(id: ID!)` and `markAllNotificationsRead` return `success` and typed `errors`. They invoke native notification reading, including actor isolation and state publication. A missing ID, an ID owned by another user or an already read ID receives the native successful acknowledgement without changing another actor's data. Success does not prove that the ID existed or changed. Marking all notifications read also retains native seen state updates and affects all native notification types. Base query costs are 1000 for one ID and 4000 for the bulk action. Outer credential, CSRF, GET and readonly protections remain applicable.

Recent menu prioritization, reviewable menu entries, totals, notification administration and typed plugin payloads remain required future coverage.

## Topic reading state and notifications

An authorized topic exposes nullable `currentUserState` with `lastReadPostNumber`, `notificationLevel` and `totalTimeViewedMs`. It returns the current actor's stored native state. Anonymous users and topics without a stored actor record return null. A null record does not infer the effective notification preference from site, category, tag or group defaults. State lookup batches through the native actor scoped lookup.

`updateTopicNotifications(topicId: ID!, level: TopicNotificationLevel!)` changes only the current actor's preference. Levels follow native topic levels, with `REGULAR` as the canonical name for the native normal alias. Native access restrictions, detailed missing topic behavior, notification reasons, events and publication remain authoritative.

`recordTopicTimings(input: TopicTimingsInput!)` accepts `topicId`, `topicTimeMs` and `timings`. Each timing has `postNumber` and `milliseconds`. Durations must be nonnegative, post numbers must be positive and unique, and a submission may contain at most 50 entries. Invalid shapes return `BAD_USER_INPUT` before native timing work. An empty timing list retains native topic time behavior and can initialize reading state at the first post.

Native processing retains timing caps, post read statistics, notification updates, automatic tracking and public or private tracking publication. It applies its native upper post range for members or staff. This does not promise an individual visibility check for every interior post number. Native first insertion leaves stored topic time at zero, while later updates accumulate it. For example, two accepted 500 ms submissions can report stored topic time as zero after the first and 500 after the second. Individual post timings still accumulate natively.

Timing processing runs synchronously within GraphQL. The nested native request cannot take over the outer response socket. The outer GraphQL request retains its transport callback, session and response ownership.

`resetTopicReading(topicId: ID!, lastPostOnly: Boolean)` defaults `lastPostOnly` to false, including when null. A full reset deletes native post timings and the stored topic state row, including an explicit notification preference. With `lastPostOnly: true`, native processing resets the final post instead. Both modes retain reopening the latest topic notification and applicable private message tracking publication. Reload authoritative state after success.

These mutations return `success` and typed `errors`, preserve current authorization and outer credential, CSRF, GET and readonly restrictions, and invalidate request loader caches around execution. Base costs are 1,000, with an additional 10 per submitted timing entry. A lost response does not establish rollback. Timing replay can accumulate time again, and reset replay can affect newer reading state. Reconcile authoritative state before deciding how to recover.
