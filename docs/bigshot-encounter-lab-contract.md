# Bigshot Quick Combat integration contract

Status: implemented in the Bigshot, companion Lich, and LAB development worktrees,
with offline tests. It depends on the unreleased execution-guard and provenance
APIs in Lich PR #1575; it must not be presented as compatible with an unmodified
Lich 5.21 installation. One supervised warm-start combat/eLoot pass and one
no-loot refuge-to-profile seek/combat/return acceptance run through LAB have passed;
see the smoke-test checklist for scope and remaining checks. LAB's shipped controller
registry remains empty. This document describes inspected interfaces, not
capabilities guaranteed by an installed version. See the
[user guide](bigshot-quick-combat.md) and [implementation plan](bigshot-encounters-plan.md).
The independently reviewable eLoot and go2 integration seams are proposed in
[EO Scripts #2457](https://github.com/elanthia-online/scripts/pull/2457) and
[EO Scripts #2458](https://github.com/elanthia-online/scripts/pull/2458).

## Public commands and registration boundary

Bigshot implements `;bigshot quick clear`, `watch`, `assist`, and
`trial NAME --target ID`, plus local `status`, `hold`, `resume`, `stop`, `retreat`,
and `engage ID`. Bare `quick`, `quick once`, and `quick single` retain legacy
behavior when no expanded Quick run owns Bigshot. Internal encounter names do
not establish another public command namespace.

The optional LAB example at `examples/controllers/bigshot-quick-trial.json`
launches Bigshot directly through native `Script.start_child`; no wrapper is
required. It supports a named trial within a bounded profile-area outing, with
explicit refuge admission and return. The encounter pins its target room.
Native children inherit a hidden supervisor's visibility. Quick ownership and
duplicate checks use `Script.list` (including hidden instances), not the
visible-only `Script.running` list; visibility never grants or removes ownership.
Its synthetic character, finite sequence-name enum, safe room, and approval
policy require explicit local review and private registration. Set the same
private `LAB_CONTROLLER_MANIFEST` for the sidecar and Lich. Capability discovery
does not grant authority, install the example, or start a trial.

Registered Quick tests require a `quick_refuge` handoff with an explicit refuge
and return reserve. Legacy `quick_area` entries remain readable for migration
but cannot launch tests. The fixed launch includes `--area profile`. Bigshot
builds the selected profile's native area and publishes immutable `area` status. LAB
consumes that exact-child proof; it does not duplicate map traversal or accept
a caller-provided room list. A moving watch/assist control still pins the fresh
current room and exact session/run; clear/trial keep their original room lock.
Crossing outside the profile stops ordinary combat/loot. Admitted retreat keeps
its separate configured destination and cancellation semantics.

Explicit `quick seek --area profile` registrations add a bounded local search
before the first encounter; they must claim movement and combat lanes. Seek
controls use the same current-area proof during search, with no model round trip
between steps and combat. Native Quick pins the encounter room once a target is
found. Search counts/limits are reported separately under `status.search`.
Only the reviewed registration grants this opt-in: a plain refuge-bound watch or
clear registration does not silently become a wandering operation.

An outing begins at the configured refuge, travels to the profile area through
the existing go2 helper, performs bounded work, restores equipment and returns.
The refuge and transit rooms need not belong to the hunting area. Successful
handoff requires fresh same-session refuge arrival, original hands, standing,
survival and exact-owner release, independently verified by LAB. A clear hunting
room or completed trial is not a safe handoff. Room-bound noncombat tests retain
their separate contract. See [refuge outings](bigshot-quick-refuge-outings.md).

Presets and trials resolve into detached immutable run snapshots without
overwriting the selected normal hunting profile. Current trial storage contains
`actions` (Bigshot command strings) and optional `max_actions` and `max_seconds`;
the exact target ID comes from the launch. This is not a new assertion or
resource-budget language. LAB does not hash-pin the named trial's local settings
file: review it before admission and do not edit it during the run.

## Existing authenticated transport

LAB retains its manifest, ActionBroker, independent Ruby validation, and
one-operation-per-character policy. There is no new listener, credential, model
combat loop, arbitrary Ruby control, or script-argument bypass.

An explicitly authorized, locally registered example uses:

```text
labctl perform Testmage controller.quick-trial --arg 'sequence="probe-sequence"' --arg 'target_id=12345' --expected-generation GENERATION --operation-timeout 90
labctl control Testmage status --operation-id OPERATION_ID --expected-generation GENERATION
labctl control Testmage hold --operation-id OPERATION_ID --expected-generation GENERATION
labctl control Testmage resume --operation-id OPERATION_ID --expected-generation GENERATION
labctl control Testmage retreat --operation-id OPERATION_ID --expected-generation GENERATION
```

Replace synthetic values only after reviewing current character, generation,
room, target, definition, and recovery authority. Use the operation ID returned
by `perform`; do not duplicate a launch because an acknowledgement was lost.

`POST /v1/session/operation/control` requires exactly `character`, `operation_id`,
`expected_generation`, and `control`. The corresponding
`CapabilityRunner.control_controller` submits to the existing operation through
ActionBroker. HTTP 202 and `applied: null` mean admission, not application.
Controls have at most five seconds of authority, never beyond the operation
deadline; pending controls are bounded to 32. No MCP control tool is added.

Matching Python/Ruby schemas accept `kind: control` for `status`, `hold`,
`resume`, and `retreat`. Each internal action carries the original launch's
16-lowercase-hex action ID as `run_id`, not the user-facing operation ID.
Control templates are intercepted by LAB; do not type their internal run-token
strings as Bigshot commands. `control_owner_scripts` must include the controlled
script and be drawn from the owner exclusion list. Excluding a competitor is
not permission to control it.

## Exact native owner and lifecycle

The bridge retains the exact Script returned by `Script.start_child`, original
launch action, character, generation, room, and operation deadline. It binds only
that instance's `quick_combat_runtime` using `LabControllerControls::Binding`.
Bigshot imports no LAB code and publishes no global controller registry.
The runtime provides `request(action, valid: Proc)` and immutable cached `status`.
A fast terminal run can supply the same instance's immutable
`quick_combat_result`. A script-name lookup cannot replace either identity.

| Control | Local Quick behavior | LAB behavior |
| --- | --- | --- |
| `status` | Read cached mode, state, room/target, actions, observations and reason. | Inspection on the exact active operation; not proof of effect. |
| `hold` | Standalone Quick holds; a supervised outing ends work and returns. | Broker-gated mutation queued on the bound owner. |
| `resume` | Recheck state and reacquire target/group permission. | Cannot restart an outing already returning or resume a successor. |
| `retreat` | Standalone Quick uses configured extraction; a supervised outing restores equipment and returns to its explicit refuge. | Same owner and original authority; cleanup remains observed. |
| `stop` | End local work; cannot retract commands. | Ordinary operation stop requests bounded return, retaining original authority. Actions-off/hard revocation denies all further sends, including return. |

Authority refresh uses authenticated action-status reads on a bridge worker,
not Bigshot's owner thread. The owner checks a cached/local predicate when
applying a queued control and before deferred retreat. Cache age is at most
250 milliseconds; expiry and observed revocation deny. A control's short
application expiry does not cancel an already-entered escape; original launch
authority governs that lifetime. Remote revocation still has polling latency.

Startup publication is bounded by three seconds and the operation deadline.
Failure before publication cancels only the exact native child via
`kill(async: true)`; its synchronous stopping flag is checked by Quick startup
and execution. Once bound, lost authority requests cooperative stop, including
during retreat. Cleanup is awaited for three seconds plus bounded in-flight
polling. Incomplete join retains exact-child exclusion; no successor is killed
or released by script name. Forced startup cancellation is not safe extraction.

## Results and safe handoff

LAB preserves `{ok, code, message, details}` results attributed to controller,
script, and launch action. Controlled terminal details include `run_id`, runtime
status, `cleanup_complete`, and `effects_verified: false`. Successful launch or
control admission is not a terminal result. `sequence_dispatched` means bounded
dispatch finished, not that intended game effects occurred.

Runtime status includes selected preset/profile/sequence names (unknown profile
names remain null), effective action/time limits and monotonic timestamps. The
recent observation ring reports its total entries, dropped entries and retained
sequence range. Each entry distinguishes transport sends from reserved budget
usage; absent verified usage is not a zero-send claim. These fields describe the
resolved run, not a new pinned-test format or an assertion of game effects.

LAB's presentation adapter keeps its existing result-size and event-depth limits.
Grouped commands are labeled JSON display text, not executable replay input.
Overlong command text is marked with omitted-character counts; additional removal
of oldest entries is disclosed separately in `observation_transport`. Original
runtime totals and ring ranges are preserved, as are control/result identities.

LAB `wiki/project/Safety.md` requires fresh survival, the explicitly registered
handoff condition, and released ownership before an authorized combat operation is successful.
Completion in a hostile room, a held controller, or a joined child alone cannot
satisfy that requirement. The local supervisor retains startup/recovery
responsibility, including unexpected exits. Bigshot supports explicit
refuge outings: completion and ordinary stop automatically enter bounded recovery
and return within the original operation, not a new launch. Review recovery
before launch; short trials may finish before a
remote control arrives. No control retracts commands already sent.

Pinned non-combat tests remain a different path: LAB `script_tests.py` and
`lab-test-runner.rb` verify registered fixed cases and dependency digests. Their
room lock, assertions, and kill-based cleanup do not provide dynamic combat
targeting or extraction. Do not represent a Quick trial as a pinned diagnostic.

## Human-group engagement

Quick's scoped synchronous downstream hook uses native `Combat::Parser` and
attack definitions after native XML parsing. It accepts supported complete
main-stream attacks with exact linked present group-member and hostile-creature
IDs. Receipt/drain checks bind session, room ID/epoch and verified membership.
The hook requires the exact native game parser thread and preserves the original
queue ingress timestamp. Delayed input is never relabeled with processing time;
startup and resume cutoffs reject attacks queued before their authority began.
The bounded queue cannot infer permission from dropdowns, facing, proximity,
damage alone, speech, incomplete fragments or ambiguous IDs. Exclusions win.
No commands run in the parser hook.

If membership is initially unverified, the owner may issue one guarded `GROUP`
query with a separate one-send/three-second budget. It does not join or reorganize
a group. Later unverified membership holds assist/group-fallback runs and revokes
engagement/cleanup permission. Verify `GROUP`, resume, then require a fresh
attack. There is no automatic rejoin/query loop.

Native XML-to-hook replay covers a supported complete player attack, speech and
non-main streams, mixed movement, and queued evidence invalidated before drain.
These are offline fixtures, not proof of every live attack family or client.

## Own-action outcome provenance

The companion Lich change supplies `Tracker.observation_context`, immutable
`event[:source]` (connection, game, character, room epoch, ingress sequence and
monotonic receipt time), and `event[:observation_batch]` (ID, index and size).
Receipt time comes from the socket-reader queue stamp via
`Game.current_ingress_time`, not a delayed callback's clock. Source survives
ordered async processing; mixed/unknown bindings and incomplete input remain
unavailable. A complete batch proves that parser emission set, not absence of
later output or unsupported effects.

Temporary `Tracker.on(:attack)` demand now requests native attack outcomes
without persisting `emit_attacks`. Quick requires tracking already enabled and
provenance available; it neither enables nor reconfigures tracking. Scoped
observers copy bounded data only and are removed after each routine.
`QuickOutcomeEvidence` requires matching exact target, own initiation, receipt
after the admitted attack window opens, and a complete batch. Definitive misses
and attacks warded off increment the ineffective counter; observed effects reset
it. Foreign attacks, stale receipts, missing output, ambiguous multi-attacks and mixed miss/flare results remain
uncertain. Command/time limits still apply to uncertainty.
Correlation is not proof that a particular command caused an observed effect.

Historical limitation: the previously inspected prerelease
`f1e7021675b868522272a7c305623268bb224ea0` did not provide this ingestion provenance
or transient outcome demand. Its ordinary worker callbacks and server prompt
timestamps alone cannot satisfy this contract. The companion changes supersede
that development limitation; they are not claims about deployed upstream Lich.

## Verification and source map

Offline tests cover strict schemas, authenticated HTTP/CLI admission, exact-child
binding, authority expiry/revocation, cleanup, native command guards, XML attack
hooks, and actual native tracker/parser/observer outcomes. Native outcome replay
includes misses, hits, warding, another actor/target, flares, stale queue receipts,
room transitions, disabled tracking, and a controller holding after two misses.
The real GTK save/discard handlers also have virtual-display coverage.

Supervised client/game verification is partial. On 2026-09-10, a player-authorized
run traveled 28 rooms from its refuge, produced four attributed attacks confirmed
as four kills, returned 28 rooms, and verified original hands, standing, health,
released ownership, and no alerts. A separate ordinary-stop run returned safely.
This does not validate other routes, profiles, assist/trial modes, or live eLoot.
Retain synthetic
or genuinely sanitized fixture text, native source revision, chunk boundaries,
exact IDs, membership and room/session/receipt context when adding replay
evidence. Never publish raw private logs or infer broad live compatibility from
passing fixtures. No script or registration was deployed by this work.

Source paths are relative to their repositories:

- Bigshot: `scripts/bigshot.lic`, `spec/scripts/bigshot_quick_*_spec.rb`, and
  [the current user guide](bigshot-quick-combat.md).
- Companion Lich: `lib/common/script_execution_guard.rb`, `lib/games.rb`,
  `lib/gemstone/combat/`, `docs/script-execution-guard.md`, and
  `docs/combat-observation-provenance.md`.
- LAB: `src/lich_agent_bridge/operations.py`, `lich/lab-bridge.lic`,
  `lich/lab-controller-controls.rb`, `wiki/project/Controller-Controls.md`,
  `wiki/project/Safety.md`, and `examples/controllers/README.md`.
