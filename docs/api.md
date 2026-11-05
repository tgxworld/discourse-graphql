# API contracts

These contracts define intended behavior. Implementation and runtime verification remain in progress. The capability ledger records delivery status.

## Transport and identity

The endpoint is `/discourse-graphql/graphql`. POST accepts a single JSON object containing `query`, optional `variables`, and optional `operationName`. Existing form requests and JSON strings for variables remain supported. Variables must decode to an object. Request arrays are rejected.

GET accepts query operations only, using the same parameters. A mutation sent through GET is rejected before execution. Anonymous queries use the same public access rules as Discourse. `currentUser` is nullable and returns null for an anonymous actor. A private site still requires authentication.

Browser sessions retain Discourse CSRF verification for POST. API credentials retain their existing exemption only when Discourse authenticates them. An invalid or revoked credential never falls back to anonymous access or a browser session. Credentials restricted to existing controller actions do not automatically gain GraphQL access. Existing read credentials may use GET where their existing method rules allow it. POST does not become permitted merely because the operation is a query.

Authenticated responses are private. A disabled GraphQL plugin returns HTTP 404. Invalid transport input returns HTTP 400. Authentication and CSRF failures return HTTP 403. Executed GraphQL operations return HTTP 200 with the standard `data` and `errors` envelope, including validation failures that prevent execution.

## Errors and partial results

GraphQL errors expose a human readable message and a stable `extensions.code`. Initial codes are `BAD_REQUEST`, `PAYLOAD_TOO_LARGE`, `GRAPHQL_PARSE_FAILED`, `GRAPHQL_VALIDATION_FAILED`, `BAD_USER_INPUT`, `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `FEATURE_DISABLED`, `QUERY_TOO_COMPLEX`, `QUERY_TOO_DEEP`, `RATE_LIMITED`, `CONFLICT`, `UNAVAILABLE`, and `INTERNAL_ERROR`. Error responses must not expose backtraces, exception class names, secrets or hidden resource details.

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

## Bookmarks

`bookmarks(first: Int, after: String, search: String)` reads the current actor's native bookmark list. Omitted or null `first` uses 20, with minimum 1 and maximum 20. Search uses native matching and accepts at most 200 characters. Native registered handlers own target visibility, search, preloads and ordering. Signed cursors bind the page, exact search, page size, actor and site. Invalid context returns `BAD_USER_INPUT`. Native continuation counts determine `hasNextPage`.

Nodes expose native scalar metadata, target identity and URL, and the current `autoDeletePreference`. Registered target serializers remain authoritative for their fields. The extra preference comes only from the native bookmark metadata serializer after list authorization, preserving existing scope, `only` and `except` restrictions. It cannot restore overlapping fields suppressed by a target serializer. A suppressed preference remains null and cannot be guessed safely when preserving it during an edit.

`createBookmark(input: CreateBookmarkInput!)` supports `POST` and `TOPIC`. Installed Chat adds `CHAT_MESSAGE`. Installed Data Explorer adds `DATA_EXPLORER_QUERY_GROUP`, whose target ID identifies the query and group association rather than the query itself. Native handlers preserve channel access, report group context, hidden report filtering and administrator access. Disabled plugins disappear from the native filtered registration. Their targets remain schema values when installed, while native creation rejects an unavailable target with `BAD_USER_INPUT`.

`updateBookmark(input: UpdateBookmarkInput!)` requires `id`, `name`, `reminderAt` and `autoDeletePreference`. The latter three must be present and may be null. Native update replaces values. Null clears the note or reminder, while a null automatic deletion preference selects the native user default. Read the current values before renaming a bookmark so they can be preserved. `reminderAt` uses the ISO8601 `ReminderTime` scalar, which retains native JSON timestamp precision through a read and replacement. Native creation and update can store null for `pinned`, so that output remains nullable.

`toggleBookmarkPin(id: ID!)` toggles the native state. `deleteBookmark(id: ID!)` returns the native `topicBookmarked` metadata when available. `bulkBookmarks(ids: [ID!]!, operation: BookmarkBulkOperation!)` accepts at most 50 IDs and the native `DELETE` or `CLEAR_REMINDER` operation. Its `changedIds` are the native result. Native ownership checks, rate allowance, validation, reminder behavior, events and target side effects remain authoritative. Base mutation costs are 1,000, with an additional 20 per bulk ID.

Mutations return `success` and typed `errors`. Required nullable input omissions return `GRAPHQL_VALIDATION_FAILED`. HTTP credential, CSRF, GET and readonly restrictions remain applicable, and loader state clears around writes. Native bulk processing can apply earlier changes before a later failure. Errors do not promise rollback. A lost toggle response must be reconciled by reading current state rather than automatically toggling again. Duplicate creation remains a native validation error. Restart pagination after changes to ordering or membership and reconcile repeated IDs.

The reminder journey saves through GraphQL, executes the native scheduled reminder job and retrieves the resulting notification through GraphQL. This preserves native reminder creation and clearing rather than introducing another scheduler.

Deleting an existing Chat bookmark after disabling Chat has an unresolved native failure: the row is deleted before native callback lookup raises. GraphQL returns a contained `INTERNAL_ERROR` without claiming rollback. See `docs/native-dependencies.md`. Full disabled target deletion acceptance remains incomplete.


## Drafts

`draft(key: String!, sequence: BigInt)` reads the current actor's native draft and current sequence. Missing content returns null with the native sequence. Supplying a stale sequence returns `CONFLICT` at the nullable field. `drafts(first: Int, after: String)` reads the native current actor stream, using default 25 and maximum 50. Its signed cursor binds native offset, page size, actor and site. Invalid context returns `BAD_USER_INPUT`. A full page offers continuation, so a final empty page can establish completion. Ordering follows native updated time and ID. Restart pagination after changes and reconcile repeated keys.

Draft content has explicit fields for core composer text, title, action, IDs, recipients, locale, timings, whisper, reply user and original values. Tag snapshots preserve native `NAME` strings versus `OBJECT` entries. Tag object integer identities remain numeric in native storage for edit conflict checks. Input tag format is explicit. Each tag collection accepts at most 100 entries. Sequence and embedded bigint output use lossless decimal strings through `BigInt`, and echoed decimal strings are accepted as input. For example, a current sequence of `"1099511627776"` can be sent back unchanged and the native update returns `"1099511627777"`.

`unmappedFields` reports unrepresented root or nested keys without returning arbitrary values. Reporting is bounded at 100 entries, with `$more` indicating additional names. A legacy nonobject or malformed JSON value reports `$format`. Oversize legacy tag collections become unavailable with an unmapped field marker rather than being truncated silently. A client must not replace a snapshot with unmapped fields using only its typed subset. Preserve local content and use the native composer or a complete typed extension. Plugin metadata remains incomplete where it is reported as unmapped.

Native list metadata remains separate from stored content. Current visibility controls resolved topic titles, categories and display users. An actor can retain their own saved reply while metadata for a referenced private post is suppressed. Draft supplied reply user data is a stored snapshot rather than a fresh profile lookup. Native display name settings apply to server resolved metadata and conflict users.

`saveDraft(input: SaveDraftInput!)` accepts a key, sequence, typed content, optional owner and optional `forceSave`. Keys must be nonblank and at most 40 characters, owners at most 200, and sequences within the nonnegative signed bigint range. Native serialized length and total draft quotas remain authoritative. Omitted fields replace the old snapshot according to native save behavior. `owner` is client correlation and provides neither locking nor idempotency.

A successful save returns the native sequence, which clients retain for their next write. Native missing row recovery can accept a stale supplied sequence using the current counter. A stale save against an existing row returns `success: false` with `CONFLICT` and native descriptive recovery text. Preserve local edits, reload the current draft and choose reconciliation before using explicit `forceSave`. A successful save can include `conflictUser` because the original post changed. Native access checks govern that identity. Save retains draft events, upload references and backup behavior.

`deleteDraft(key: String!, sequence: BigInt, username: String)` preserves native acknowledgement semantics. A stale sequence can receive success while leaving the row intact. Success alone does not prove deletion. `deleteDrafts(drafts: [DraftReferenceInput!]!, username: String)` accepts at most 30 unique references, validates supplied sequences through the native action and returns its `deletedCount`. An already stale batch is rejected before deletion. Native validation occurs before the deletion transaction and does not establish isolation from a concurrent writer after validation. Optional target usernames retain the native administrator and API checks. Browser administrator sessions cannot use that API targeting shortcut.

Draft mutation base costs are 1,000, with another 20 per bulk reference. Loader state clears around writes, and credential, CSRF, GET and readonly protections remain applicable. Native error descriptions are exposed as optional typed `description` values. Neither an error nor a lost response implies rollback. Native backup work can precede sequence rejection, and replaying deletion can affect a newer draft under the same key. Reconcile authoritative state before recovery.

Native listing currently fails for some legacy nonobject roots, including an accepted array draft. A known malformed key can still be looked up and explicitly deleted through native actions, after which listing recovers. Typed creation prevents those root shapes. This does not repair the native index dependency documented in `docs/native-dependencies.md`.


## Uploads

`createUpload(input: CreateUploadInput!)` invokes native upload creation and returns `success`, nullable `upload` and typed `errors`. The `UploadedFile` object exposes native scalar metadata, including `id`, `shortUrl`, `url`, filename, dimensions and byte size. Native upload type normalization, avatar restrictions, rate allowance, validation, processing, storage, deduplication and plugin events remain authoritative. Upload byte size uses the same lossless `BigInt` decimal string convention as draft sequences.

Inputs accept required `uploadType` and exactly one of `file` or `url`, plus optional `pasted`, `forPrivateMessage`, `forSiteSetting`, `siteSettingName` and `retainHours`. Boolean values retain false and are forwarded using native parameter representations. Remote URL import retains native API credential requirements and download protections. Supplied URLs have a 4096 byte bound.

File transfer uses multipart form fields `operations` and `map` plus file parts. `operations` contains one JSON operation object. For example, variables contain `{"input":{"uploadType":"composer","file":null}}`, and `map` contains `{"0":["variables.input.file"]}`. File part `0` carries the bytes. The input scalar is `Upload`. There is no base64 encoding. A mapped file may populate several distinct null variable placeholders. Repeated variable uses receive independent streamed copies because native image processing can rewrite or remove its input. Copies are removed after native success or failure. Native login callbacks run before the resolver copy.

The endpoint limits nonmultipart bodies to 1 MiB and raw multipart bodies to 101 MiB before parameter parsing. Multipart requests admit at most 10 file parts, 100 MiB total mapped file bytes and 1 MiB aggregate form text. Limits include unknown parts. Duplicate part names, unknown parts, repeated map destinations, missing files, nonnull destinations and invalid variable paths are rejected. Paths must reference existing placeholders below `variables`, with at most 12 segments. Request arrays remain unsupported. These are admission bounds, not measured concurrency or memory budgets.

Body overflow returns HTTP 413 with `PAYLOAD_TOO_LARGE`. Malformed multipart input returns HTTP 400 with `BAD_REQUEST`. Early rejection, parsing failure and response closure clean tracked source files. Browser CSRF, credential scopes, readonly mode and GET mutation rejection still apply. Upload creation carries base query cost 1000 before selected output.

Upload success establishes native upload creation, not post attachment. Retain `shortUrl` and use it in Markdown such as `![image](upload://...)`. If reply validation fails, reuse that reference in the corrected submission without uploading again. Native cooking and upload references establish the eventual attachment. If an upload response is lost before its reference arrives, completion remains unknown. Preserve local bytes and let the user explicitly choose a fresh upload with possible duplication. Native deduplication is conditional and does not establish safe automatic retries.

`uploadMetadata(url: String!)` returns native `originalFilename`, `width`, `height` and `humanFilesize` through the native access check. `lookupUploadUrls(shortUrls: [String!]!)` resolves at most 100 short URLs, each at most 4096 bytes, through native lookup and permission filtering. Unknown or inaccessible uploads are omitted. Returned fields are `shortUrl`, `url` and `shortPath`. These queries require native login and recheck current access. They introduce no arbitrary lookup by upload ID. Native download endpoints remain responsible for actual file delivery and current access checks.

Direct storage contracts follow below. Remaining upload metadata, rich relationships, complete client journeys and final performance budgets remain required coverage.


## Direct storage uploads

`createDirectUpload(input: CreateExternalUploadInput!)` and `createMultipartUpload(input: CreateExternalUploadInput!)` invoke fixed native ticket creation actions. Required input fields are `fileName`, `fileSizeBytes` and `uploadType`. File size is a positive `BigInt` within the signed 64 bit range. Native file size checks still apply. File names and upload types have byte bounds of 1024 and 100. Optional `sha1Checksum` maps only to native checksum metadata and has a 128 byte bound.

The payload exposes `success`, nullable `ticket` and typed `errors`. A ticket has `uniqueIdentifier`, `storageKey`, optional `externalUploadIdentifier`, optional `url` and `signedHeaders` as name/value pairs. Preserve the native headers exactly when sending bytes to the signed URL. A single PUT ticket supplies its URL. Multipart tickets supply the provider identifier for subsequent signing. Responses remain private and require native login, storage availability, direct upload enablement and current upload eligibility. Ticket creation is a mutation that consumes native rate allowance and creates native state.

`presignUploadParts(uniqueIdentifier: ID!, partNumbers: [Int!]!)` returns `success`, nullable `parts` and typed `errors`. Each part has `partNumber` and `url`. At most 100 unique numbers are accepted per call, within the native range 1 through 10,000. Request bounded batches for a larger upload. This mutation retains native ticket ownership, provider existence and rate checks. It mints access, not completion acknowledgement. Send each part to its returned provider URL through the native storage protocol.

`completeDirectUpload(input: CompleteUploadInput!)` and `completeMultipartUpload(input: CompleteMultipartUploadInput!)` invoke native completion. Inputs require `uniqueIdentifier` and optionally accept `pasted`, `forPrivateMessage`, `forSiteSetting` and `siteSettingName`. Multipart completion also requires 1 through 10,000 unique `partNumber` and nonblank `etag` pairs. ETags have a 2048 byte bound. Native sorting and provider completion remain authoritative. The maximum part count fits admission analysis with ordinary ETags, while the endpoint still enforces its aggregate JSON body bound.

Completion returns `success`, nullable `upload` and typed `errors`. Native transformation, checksum behavior, file validation, storage movement, failure cleanup, debug retention and size mismatch bans remain authoritative. The native large file path avoids server downloads above 100 MiB. Server checksum verification follows the native downloaded file path and is not promised for every size. A consumed ticket normally returns `NOT_FOUND` on subsequent completion. These acknowledgements do not create a new retry guarantee.

Backup uploads use native multipart initiation and completion with their existing administrator, enablement and storage restrictions. Completion can succeed without an `Upload` row, returning `upload: null` after moving the backup to its native destination. The native backup store has no single PUT signer. Do not use `createDirectUpload` for backup initiation. No replacement signer or backup policy is implemented here.

`abortMultipartUpload(externalUploadIdentifier: ID!)` invokes native abort with the provider identifier, not the ticket UUID. Native ownership checks remain authoritative. An unknown provider identifier receives the native successful acknowledgement without proving that an upload existed. Identifier inputs have a 4096 byte bound. There is no invented cancellation action for single PUT tickets.

Keep ticket identifiers and any acknowledged `shortUrl` in client state. A failed byte transfer can be retried only according to the provider protocol and URL expiry, using the exact signed headers. This is distinct from repeating a GraphQL initiation or completion. If a completion response is lost, completion remains unknown. Do not blindly repeat completion or automatically create another upload. Native APIs provide no general completion reconciliation lookup. Once a `shortUrl` is known, retain and reuse it after rejected post validation as described above.

Initiation and abort cost 1000. Part signing costs 1000 plus 20 per requested number, before selected response fields. Completion costs 2000, with multipart completion adding one per 10 parts rounded up. The native 10,000 part completion remains admissible. These are work admission bounds, not measured latency or memory budgets.

At the pinned revision, native completion at exactly 100 MiB returns a generic failure and removes the ticket and temporary object because neither native file processing path accepts the equality case. The adapter retains that result. This is an unresolved dependency in [native dependencies](native-dependencies.md), so complete large transfer compatibility remains unmet.


## Checklist updates

When Checklist is loaded, `updateChecklist(input: ChecklistUpdateInput!)` invokes its fixed native toggle action through PUT semantics. The native controller and service retain edit permission, source matching, permanent marker rules, state conflicts, revision creation, publication and the shared toggle allowance. The installed capability is `checklist.checkboxChanges`. Disabled Checklist returns `FEATURE_DISABLED` at the nullable payload. An absent plugin contributes no Checklist mutation or reachable types.

Inputs require `postId`, `expectedRaw`, `expectedUpdatedAt`, `mutationId` and `toggles`. Each toggle requires `checkboxIndex` and `checked`, plus optional `checkboxSource` or `checkboxCount`. Index zero and `checked: false` are retained. Source hints take native precedence over the legacy count form. At most 50 toggles are accepted, using the native batch bound. Native validation owns source format, uniqueness, permanent targets and content limits.

Read existing `Post.raw`, `Post.cooked` and the new nullable `Post.updatedAt` to obtain state. The timestamp is selected through native `PostSerializer` inclusion rules and JSON precision. It is an opaque String, so echo it exactly rather than rounding it through a client date formatter. Native cooked markup supplies `data-chk-src` target hints on `span.chcklst-box` elements. Target discovery and rendering continue to use the native protocol. No copied Markdown parser or quote exclusion policy is introduced.

The payload exposes `success`, typed `errors` and native nullable `raw`, `cooked`, `updatedAt`, `lastEditorId`, `version`, `revised` and `retryable`. A matching desired state can acknowledge success with `revised: false` and no revision. Native conflict responses use `CONFLICT`, current raw and timestamp, and native retry guidance. Those details follow the native edit permission check, including after access revocation.

On success, retain returned state. On conflict, retain local intent. For a checkbox state conflict, refetch current state before deciding whether to reapply desired checked values to the current target. For content or target changes, refresh and let the user reconcile. The server does not retry automatically. A lost response remains ambiguous and requires refetching. Neither `retryable` nor `mutationId` provides an idempotency guarantee. The mutation ID preserves native cooked update correlation.

The mutation clears request loaders before and after processing. Its cost is 1000 plus 20 per requested toggle before selected output fields. Native GET rejection, readonly mode, CSRF, credential scopes and rate limiting remain applicable. The shared native allowance is 60 requests per minute at the pinned revision.

A native structured read boundary remains an assessment item before complete plugin coverage. Current clients use native cooked target hints with the typed mutation. Native setting administration, complete client journeys and final concurrent workload budgets remain required.

## Site setting administration

`adminSiteSettings(first: 25, after:, names:, categories:, plugin:)` returns native setting definitions in native order. Pages contain at most 100 definitions. Name and category filters accept at most 100 entries. Names and filter entries must be nonblank strings of at most 128 bytes. Cursors bind the administrator, site, filters and page size. Native index construction still evaluates the complete setting catalog before name filtering, so a small page does not imply proportionally small native work.

`adminSiteSetting(name:)` returns the exact visible setting or null for an unknown or hidden setting. The native list can include its default locale entry even when a name filter is supplied. Exact lookup excludes this unrelated entry.

Definitions expose `name`, `displayName`, `type`, `category`, `primaryArea`, `plugin`, `description`, `valueWire`, `defaultWire`, `secret` and `themeable`. Optional native metadata remains nullable. Native modifiers can remove values without a model fallback. Rich editor and choice metadata remain incomplete.

`updateSiteSettings(changes:)` accepts between one and 50 uniquely named changes. Each `SiteSettingChangeInput` requires `name` and `valueWire`. Optional `backfill` defaults to false. Values use the native String wire protocol for every setting type. Boolean values are strings such as `"false"`, list values use the native separator, and object values contain native JSON text. Native parsing and validation remain authoritative. For example:

```graphql
mutation {
  updateSiteSettings(changes: [
    { name: "title", valueWire: "Our community" }
    { name: "allow_user_locale", valueWire: "false" }
  ]) {
    success
    errors { code message }
  }
}
```

The native controller performs the update through `SiteSetting::Update`, retaining visibility, configurability, dependency ordering, validation, transaction handling, staff logs, events, cache changes and explicit preference backfill. Success acknowledges the native response without manufacturing current values. Query definitions again to obtain current state. A lost response requires reconciliation before deciding whether to repeat the operation.

`siteSettingAffectedUserCount(name:, valueWire:)` retains the native affected preference count action and returns a nullable BigInt. It uses native PUT semantics despite being a GraphQL query, so credential scopes, CSRF and readonly protections remain applicable. Unsupported default preference families can return null.

All three native actions retain administrator checks and both native router constraint hooks. Hooks receive logical native paths, methods, route parameters, bodies, sessions and headers, including a mounted site subfolder. Native authentication evaluates the reconstructed request rather than accepting the outer request identity cache. For example, a key limited to GET requests can read definitions but cannot invoke the native PUT count action through a GraphQL GET query. Native archived site recovery is available through `updateSiteSettings`. The controller remains responsible for which settings can change while archived. A mutation mixing recovery with any root action lacking native archived permission is rejected before writes execute. Skipped root fields do not participate in admission. The root walk deduplicates fragments and does not descend into payload selections.

GraphQL documents, variable objects, legacy variable strings and multipart operation documents are filtered from request parameters before the native request logger. Logical native administration parameters are filtered too. Existing parameter filters remain in effect, and unrelated endpoints retain their own query logging behavior. This protection covers request logs and controller request payload notifications. It does not claim to filter database bind logging.

List and single definition reads cost at least 4000 each. Affected count costs 1000. Bulk changes cost 2000 plus 20 per requested setting and selected output fields. These bounds acknowledge native catalog construction rather than claiming it has been optimized. Final concurrent performance budgets remain required.
