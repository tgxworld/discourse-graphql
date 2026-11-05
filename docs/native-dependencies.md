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
