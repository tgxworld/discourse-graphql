# Native dependencies

Supported Discourse revision: `f5e1933dd40c57b886da02c45e5630020ceb99c2`.

## Anonymous Chat history after anchor deletion

Status: unresolved. This prevents complete Chat history acceptance.

With Chat enabled for anonymous public preview, the native message endpoint returns the latest public message successfully. After that message is deleted, requesting an older page with its ID as `target_message_id` returns HTTP 500. The exception is `NoMethodError: undefined method 'id' for nil` in `Chat::Channel::Policy::MessageExistence#call`, line 10.

The policy dereferences `guardian.user.id` for a deleted target, while an anonymous Guardian has no user. The smallest native correction must handle the anonymous actor explicitly while retaining native target recovery, channel authorization and moderator behavior. An author match must require an authenticated actor, because a deleted author ID and an anonymous actor ID can both be null. The GraphQL plugin must not copy or patch that permission policy.

Reproduced through real native HTTP requests with seed 23293:

1. Enable Chat for everyone and anonymous users.
2. Create a public category channel and two messages.
3. GET `/chat/api/channels/:id/messages?page_size=1`. It returns HTTP 200 and the newest message.
4. Delete that message through native model behavior.
5. GET `/chat/api/channels/:id/messages?page_size=1&direction=past&target_message_id=:deleted_id`. It returns HTTP 500 at the policy above.

The task reproduction is `tmp/discourse-task/native_chat_anchor_spec.rb` in the supported Discourse worktree. It fails at the second HTTP status assertion. It runs with:

```bash
tgx-dv test --name graphql-revival-01a1aaad --env LOAD_PLUGINS=1 --seed 23293 tmp/discourse-task/native_chat_anchor_spec.rb
```

GraphQL error containment does not resolve this dependency. Keep it incomplete until the native correction is present in the supported revision and the reproduction plus GraphQL recovery tests pass. Full application scope remains required.

## Malformed native timing entries

The native timing endpoint returns HTTP 500 for a negative post number at the end of its timing map. `PostTiming.process_timings` deletes the entry and then dereferences the removed slot at line 185. A real native HTTP reproduction is retained in `tmp/discourse-task/native_negative_timing_spec.rb`.

The GraphQL input contract requires positive post numbers and rejects nonpositive values before native execution. The malformed input is outside the typed API contract. The plugin preserves the native algorithm for accepted inputs and does not patch this native defect.

A separate native HTTP case in the same reproduction verifies that the first timing submission creates stored topic state with zero total viewed milliseconds. A second 500 ms submission adds 500. GraphQL exposes these stored native values rather than reconstructing a different total.

## Bookmark deletion after disabling Chat

Status: unresolved. This prevents complete disabled target deletion acceptance.

The native bookmark registration is filtered when Chat is disabled. Deleting an owned existing Chat bookmark removes the row, then `BookmarkManager#destroy` dereferences the missing registration at line 75. The native DELETE returns HTTP 500 with `NoMethodError` for `after_destroy`, and the bookmark row is already absent.

A real native HTTP reproduction is retained in `tmp/discourse-task/native_disabled_bookmark_spec.rb`. It enables Chat, creates a channel message bookmark through POST `/bookmarks.json`, disables Chat, then deletes the bookmark through DELETE `/bookmarks/:id.json`. The aggregate assertion confirms row removal while the expected successful status fails with 500.

The native correction must retain ownership checks and define callback behavior when the owning registration is unavailable before declaring success. The GraphQL plugin does not copy or patch that lifecycle. Error containment does not repair the partial outcome. The reproduction and disabled target GraphQL contract must pass the corrected behavior before this dependency can be accepted.


## Native draft listing after an array save

Status: unresolved legacy compatibility limitation.

The native POST `/drafts.json` accepts `data: "[]"` and returns HTTP 200. A subsequent GET `/drafts.json` returns HTTP 500. `Draft.preload_data` calls `Draft#post_id`, which indexes the parsed array using the string `postId`, raising `TypeError` at line 177.

The real native HTTP reproduction is `tmp/discourse-task/native_draft_array_spec.rb`. Typed GraphQL creation accepts an object of declared composer fields and cannot create that root shape. Explicit key lookup reports `$format`, and native deletion can remove a known malformed draft and restore listing. Error containment and that recovery path do not repair the native index. Keep legacy listing compatibility incomplete until the native owner handles its accepted data safely.


## Protected upload URL lookup query growth

At the pinned revision, `UploadsController#lookup_urls` loads matching uploads in one query but evaluates `Guardian#can_see_upload?` separately for each protected upload. Native post and topic loading and private message membership checks grow with distinct referenced posts. A batch of 50 permitted private message uploads returns all 50 expected URLs but does not meet the required query growth budget.

The HTTP probe `script/measure_upload_lookup_spec.rb` clears query caches, measures one and 50 distinct permitted private message uploads and asserts every returned short URL. GraphQL records 14 and 158 SQL queries. Direct native POST `/uploads/lookup-urls.json` records 11 and 158. These are observed development test counts, not final latency benchmarks. The committed measurement spec prints counts and whether the required growth budget is met. A passing identity check does not establish that budget.

No access policy has been copied or bypassed. Native lookup performance remains incomplete. Resolution requires an existing native batch hook or the smallest upstream extraction that preserves post visibility, private message checks, plugin permission modifiers and revocation. Batching topic visibility alone is insufficient evidence of equivalent upload authorization. Keep the full lookup breadth and required performance criterion intact.


Reproduce the upload measurement with `tgx-dv test --name <owned-container> --env LOAD_PLUGINS=1 --seed 23293 plugins/discourse-graphql/script/measure_upload_lookup_spec.rb`. The measurement asserts complete permitted results and emits `growth_budget_met`. The current result is false.


## Exact direct storage download threshold

`ExternalUploadManager#promote_to_upload` downloads only when external size is below `DOWNLOAD_LIMIT`, while selecting its external filesize path only above that threshold. At exactly 104,857,600 bytes, native completion reaches `UploadCreator#filesize` with a nil file and logs nil.path at line602. The native helper returns HTTP422 with a generic upload failure. Native rescue cleanup removes both the ticket and temporary storage object.

The committed `script/measure_external_upload_threshold_spec.rb` drives POST `/uploads/complete-external-upload.json` with an owned ticket and a matching provider size. It uses the actual native manager and stubs only external storage. It prints `native_completion_succeeded: false` and records the partial state. Reproduce with `tgx-dv test --name <owned-container> --env LOAD_PLUGINS=1 --seed 23293 plugins/discourse-graphql/script/measure_external_upload_threshold_spec.rb`.

This remains an unmet compatibility requirement. The adapter neither changes the size nor supplies a replacement promotion policy. A native correction must make the two processing branches cover the equality case and preserve native validation, checksum, cleanup and large file semantics.

Native backup initiation uses multipart storage. The backup store does not implement the single PUT signing method. The supported backup multipart path is verified separately. No backup signer is added to this plugin.

## Site setting catalog allocation

Status: unresolved native performance dependency. Bounded metadata alias growth does not establish acceptable total catalog work.

`Admin::SiteSettingsController#index` invokes `SiteSetting.all_settings`. Name filtering occurs after constructing every definition. During construction, each definition calls `defaults.get`, which invokes `DefaultsProvider#all` and duplicates the complete default map through `all_clean`. Reusing the existing native name filter therefore does not avoid this repeated allocation.

The committed `script/measure_setting_metadata_spec.rb` profiles real native HTTP and GraphQL requests with every bundled plugin loaded. Its controlled fixture attaches200 choices totaling819890 bytes through the native result modifier. In the recorded isolated run, direct native index allocates209547576 bytes with21 SQL queries. GraphQL allocates211530914 bytes with24 queries for one selected metadata page, and212666976 bytes with24 queries for40 aliases. These are total allocations during requests, not retained or peak process memory. Approximately182.5MB is attributed to the default map duplication line in both paths.

The GraphQL metadata cache bounds additional alias allocation to about1.3MB when each alias selects its cursor in this workload. A control run without fingerprint reuse allocates about33.3MB more across40 aliases and fails its growth check. The cache is restored and the passing measurement is reproducible. It does not fix native catalog construction.

The native owner needs an efficient catalog or named definition boundary with explicit default snapshot semantics and preserved default and result modifiers. The existing catalog enumerator already obtains defaults before repeatedly looking them up, but the adapter must not replace those calls or bypass modifier behavior. Record and verify the smallest upstream improvement before claiming the full concurrent performance budgets are met.

## Unselected Chat reaction association loading

Status: unresolved native performance dependency. Selection aware serialization does not establish selection aware database loading.

`Chat::MessagesQuery.base_query` preloads reactions and their users before native message serialization. The GraphQL bridge can omit unselected attributes through native serializer options, but those options arrive after the query has loaded associations. Replacing that query or supplying partial association caches would duplicate native ownership and risk changing reaction counts, samples or actor state.

The committed `script/measure_chat_reaction_loading_spec.rb` drives native HTTP, an ID only GraphQL history read and a selected reaction summary read. With one message and 50 distinct reactors, all three requests instantiate 50 Chat::MessageReaction records and 52 User records. The selected summary retains the native count of 50 and sample of five. The ID only response contains only its requested ID while still loading the associations. The probe emits `unselected_loading_budget_met: false` and records model counts separately from SQL counts.

Reproduce with `tgx-dv test --name <owned-container> --env LOAD_PLUGINS=1 --seed 23293 plugins/discourse-graphql/script/measure_chat_reaction_loading_spec.rb`. This is a characterization of the remaining work, not a passing total work budget.

The native owner needs a supported service or controller selection hook that chooses required preloads before loading messages, with native summary preparation retaining emoji filtering, full counts, actor state and sampled users. Existing native defaults and callers must keep their behavior. The plugin must consume that boundary before claiming that omitted reaction fields avoid their associated loading. Native total allocation, memory and concurrent budgets remain required.

## Unselected thread original message preparation

Status: unresolved native performance dependency. Root projection does not select native lookup preparation.

`Chat::LookupThread` preloads original message mentions, their users and user options before serialization, and prepares participants independently of selected output. The adapter retains the native query rather than replacing its preparation or supplying partial association caches.

`script/measure_thread_lookup_loading_spec.rb` characterizes a stored fixture of50 mentions with the current native serialized limit set to its supported maximum10. Both the ID only GraphQL lookup and the selected mention page load50 Chat::UserMention,52 User and52 UserOption records. The selected mention response contains the native first10 actors. The ID only response contains only its requested ID. Both GraphQL selections use19 SQL queries in the recorded run. Native HTTP also loads all50 mentions. These are record loading observations, not a fair latency comparison or a completed total work budget.

The native owner needs a supported preparation boundary that accepts requested thread components before loading original message associations and participants, while retaining native defaults, policies and serializer behavior. The plugin must consume that boundary before claiming that omitted mentions avoid their associated loading. Reproduce with `tgx-dv test --name <owned-container> --env LOAD_PLUGINS=1 --seed 23293 plugins/discourse-graphql/script/measure_thread_lookup_loading_spec.rb`.


The thread message history adapter also exercises the corresponding `Chat::Thread::Policy::MessageExistence` defect. An anonymous public thread page succeeds, but continuation after deletion of its anchor dereferences the absent actor. The HTTP regression in `chat_thread_history_spec.rb` requires a generic INTERNAL_ERROR and excludes diagnostics and protected content. Both native policies require an upstream correction. This remains part of the existing anonymous anchor recovery dependency.


## Count only Chat draft reads prepare and copy complete saved content

With twenty drafts containing 1000000 bytes of native serialized state, a GraphQL selection containing only windowSize returns 33 bytes but allocates 5551156 bytes. Eight aliases return 194 bytes and allocate 5844931 bytes. Both execute 7 SQL queries and one native draft read. The native full current user response allocates 4904553 bytes, executes 51 SQL queries and returns 1006107 bytes. These endpoints select different fields, so this is a preparation reference rather than a latency comparison.

The largest GraphQL allocations are about 2002032 bytes in HTTP response copies, 1004580 bytes in native response JSON parsing, 1001900 bytes in ActiveRecord String casting and 1001175 bytes in native JSON encoding. CurrentUserSerializer chat_drafts always plucks complete data before the adapter receives the native response.

The native owner needs a projection aware draft window reader used by CurrentUserSerializer inside its controller lifecycle. Eligibility, recent twenty ordering, serializer options and row filtering must remain native. A filter depending on draft data still needs that data, requiring declared dependencies or a complete data fallback. A separate count query cannot preserve those filters. Capturing an earlier Ruby value or discarding the final native response would weaken the boundary and is not a solution.

`spec/performance/measure_chat_draft_window_spec.rb` reproduces native and GraphQL allocations. Alias growth is bounded, but this does not satisfy the required total preparation and concurrency budgets. No safe existing owner projection hook was identified. This dependency remains unresolved.


## Chat attachment thumbnail query growth

Status: unresolved native performance dependency. Typed media output does not satisfy the required complete query growth budget.

Chat::MessagesQuery preloads uploads and optimized videos. UploadSerializer obtains each thumbnail through Upload#thumbnail, which calls optimized_images.find_by with the native dimensions. The native association is rendered even when the GraphQL upload selection requests only its ID. Loading the complete optimized_images association alone does not make that relation find_by consume the loaded array. Replacing the model lookup or copying serializer association dispatch into this plugin would duplicate native behavior.

The committed spec/performance/measure_chat_message_media_spec.rb drives real native and GraphQL HTTP with 50 distinct uploads and thumbnails. Native history uses 29 and 78 SQL queries at 1 and 50 messages. GraphQL selected upload ID and selected thumbnail each use 29 and 78, including 1 and 50 optimized_images queries. GraphQL message ID alone uses 28 and 28 with no thumbnail queries or instantiated OptimizedImage records. Native query preparation still loads uploads for that selection.

The owner needs a supported batch thumbnail preparation and lookup boundary that preserves native dimension matching, association output and serializer restrictions. A supported child serializer selection boundary would additionally skip unselected thumbnail work. Existing callers must retain their defaults. Neither partial association caches nor discarding the final native response is an acceptable substitute. Reproduce with tgx-dv test --name <owned-container> --seed 23293 plugins/discourse-graphql/spec/performance/measure_chat_message_media_spec.rb. The probe reports total_performance_budgets_verified:false and must not be counted as a passing performance budget.
