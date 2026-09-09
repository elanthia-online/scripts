# Bigshot Quick Combat

Development documentation: selected supervised smoke tests have passed locally;
see the checklist for their scope. Profile-area seek and refuge return have passed
one player-authorized live acceptance run. Expanded Quick requires the cooperative
script execution guards and combat provenance currently proposed in Lich PR #1575,
in addition to the Bigshot 5.16 / Lich 5.21 APIs. Do not deploy it as merely
Lich-5.21-compatible; after that prerequisite is released, this document and the
script metadata must name the assigned minimum version. Startup checks the APIs before
issuing commands. Ordinary `;bigshot quick`, `quick once` and `quick single`
retain their existing behavior when no expanded Quick run owns Bigshot.

Room cleanup and supervised travel also depend on the separately scoped
[eLoot PR #2457](https://github.com/elanthia-online/scripts/pull/2457) and
[go2 PR #2458](https://github.com/elanthia-online/scripts/pull/2458).

Registered supervisors may use the private `--supervised-start-v1 WORK,CLEANUP`
launch selector after verifying the script's `SUPERVISED_START_PROTOCOL = 1`
declaration. Those absolute monotonic deadlines restrict this run only. Quick
publishes its exact runtime and waits without game commands for the supervisor's
one-time activation; the wait is capped at three seconds and the work deadline.
Initial GROUP queries happen only after activation and honor the same cached
authority and work deadline as ordinary execution. No activation, changed owner,
session/room, or expired work time refuses startup without combat or loot.
Ordinary player commands and saved presets do not use this handshake. The
declaration is a trusted-code compatibility contract, not sandboxing or proof
against concurrent local source replacement.

Player-side verification follows the [supervised smoke-test checklist](bigshot-quick-smoke-test.md).

## Local combat commands

```text
;bigshot quick clear
;bigshot quick watch --profile "Combat profile"
;bigshot quick watch --profile "Combat profile" --area profile
;bigshot quick seek --profile "Combat profile" --area profile
;bigshot quick assist --leader Friend --preset "Group hunt"
;bigshot quick assist --trigger any-group
;bigshot quick trial "Opening sequence" --target 123456
```

`clear` handles eligible targets in the current room, performs configured cleanup,
then ends. Moving rooms stops the run. `watch` keeps monitoring as you move, but
does not choose a hunting route. Each new room invalidates old target permissions.

`--area profile` restricts the run to the selected hunting profile's starting room
and boundary rooms. You may start anywhere inside that area. Bigshot builds the
area once using its existing room calculation and native UID resolution; missing
rooms, an empty boundary list, a starting room on a boundary, or an area reaching
200 rooms refuse startup. Conditional map exits may be evaluated, but cannot send
game commands during this calculation. Boundary rooms themselves are excluded.

In-area player/group movement lets `watch` and `assist` continue with fresh target
permission. `clear` and `trial` still stop on any room change. Leaving the area or
losing the current map-room identity stops combat and looting, including the next
send of an in-flight routine. Returning does not resume a stopped run. Clear,
watch, assist, and trial never automatically wander or pursue targets. Explicit retreat remains governed by
its separately configured destination, which may be outside the hunting area.

### Find one encounter locally

`seek --area profile` is an explicit movement opt-in, not a continuous hunt. It
uses the same profile area and Quick target eligibility/routines. If a target is
already eligible, combat begins without movement. Otherwise, it prefers the
least-visited mapped in-area destination until it finds an eligible encounter.
Search takes at most 12 steps and 30 seconds, further reduced by the preset's
`max_actions` and `max_seconds`. Each movement has a three-second observation
limit and only one direction send; uncertain movement is never retried.

Only ordinary compass/up/down exits are supported. Scripted `wayto` callbacks,
portals, climbing commands, helper equipment repairs, and command chains are
not executed. Conditional travel-time checks run without command authority.
Unknown rooms, area exits, unsafe state, changed sessions/ownership, unexpected
displacement, missing exits, and exhausted search limits stop further search.
The existing hold/stop/retreat controls remain available during native waits.

On finding an encounter, the arrival room is pinned for combat and configured
eLoot cleanup, then the run ends. It never resumes search or chases a departing
target. No upkeep/follower/rest/sell loop is added. Status includes `search`
step/send counts and limits, separately from combat and loot usage. A clean
field handoff does not prove a kill, loot award, or safe-town arrival.

This requires the development seek-capable Bigshot build. A player-authorized
acceptance run on 2026-09-10 ICT (2026-09-09 UTC) traversed 28 rooms to the
configured profile area, made four
game-confirmed attributed kills, and returned 28 rooms to its refuge. That proves
the tested route/profile only; other seek paths and failure modes remain pending.

The preset's **Enforce profile starting room / boundaries** field stores this
choice (`off` or `profile`); existing presets default to `off`. A CLI override is
run-local. The frozen area is not recomputed if you edit the profile mid-run.
Structured status includes compact `area` provenance and current membership;
it does not expose a second route planner or claim that the area is safe.

`assist` waits for a supported, observed attack by the selected group member or
any current group member. Other players need no script or coordination server.
The strict setting attacks only engaged targets; assist-then-cleanup can handle
other eligible room targets after engagement. If Lich has not verified membership,
startup sends one owner-guarded `GROUP` query and waits up to three seconds. This
read-only setup query has a separate one-command budget; it does not join, clear,
or reorganize the group. No verified members here, a missing selected leader, or
a timeout refuses startup with instructions. Ambiguous, unsupported or stale
attack evidence does not start combat.

If membership becomes unverified during assist (or with the `group` unfamiliar-
creature policy), Quick holds with `group_membership_unverified` and revokes prior
group engagement and room-cleanup permission. Run `GROUP`, verify your membership,
then `;bigshot quick resume`. A fresh group attack must authorize assistance again.
There is no automatic polling/rejoin loop, and parser hooks never query `GROUP`.

`trial` executes the named sequence against its exact target, within the configured
command/time limits. It does not switch to a kill routine or loot afterward.
`sequence_dispatched` reports command dispatch, not proof that every action had
the expected game effect or that a test passed.

Existing target patterns and A-J routines come from the selected profile.
`--profile` and `--preset` are run-local: they do not replace the selected normal
hunting profile. Configured native spells retain their normal game semantics,
including any inherent area effects; target selection is not a collateral-damage
sandbox. Excluded targets are not selected by Quick.

Existing `incant N` routines use their native spell implementation. Quick first
confirms the exact game selector (or explicitly clears it for an existing self-
cast spell) and rechecks it at every guarded preparation/cast/retry send. A
selector change interrupts the routine instead of casting at its replacement.
Selection, release, preparation and retry commands consume the same budget.
Cancellation restores Ruby spell settings, but sends no game-state restoration
commands and cannot undo a spell already accepted by the game.

`resonance N N ...` retains native spell rotation and delegates through that same
guarded incant path. Every candidate is validated before selection, so including
a travel spell in the list refuses the routine before any command is sent.
`leech` preserves its native known-spell, cooldown and affordability checks, then
uses confirmed target selection for its native cast. A skipped leech does not
change the game selector or send commands.

`efury` (optionally `fire` or `cold`) and plain `tether` also retain native
eligibility and casting behavior. Quick waits for their completion on its owning
thread, with cancellation and deadlines still active; it does not start a second
reader that could consume later responses. `tether recast` remains unsupported
because following a transferred tether would need new target authorization.

## Controls

```text
;bigshot quick status
;bigshot quick hold
;bigshot quick resume
;bigshot quick stop
;bigshot quick retreat
;bigshot quick engage 123456
```

These commands address the existing owning run; they do not start another Bigshot.
Hold interrupts future sends while retaining safety monitoring. Resume uses fresh
target/group permission and a fresh execution scope. Stop ends local monitoring;
it does not teleport you or cancel commands already accepted by the game.

`engage ID` explicitly selects a current hostile creature for a non-trial run.
For an unfamiliar creature, select the `manual` unknown-creature policy and
configure its fallback routine first. Exclusions, hostility, safety and all
execution limits still apply. Selection is queued, pinned to the observed room,
and expires after three seconds if not applied. Movement and resume clear manual
permissions. It cannot retarget a trial or override the `ignore` policy.

Retreat supports explicitly configured `130` or `walk` adapters. Set safe destination
room IDs (or unambiguous `uUID`s), comma separated; blank uses the profile's
resting room. Native Spirit Guide casting is bounded by the configured action
and time limits. Confirmation requires fresh survival, stable arrival at one of
those destinations, and no observed hostile or configured environmental danger.
An accepted spell command is not successful escape. `escape_sends` and
`escape_reason` report this separately from combat actions. Unconfigured retreat
holds with `retreat_unconfigured`.

`walk` chooses the nearest reachable configured destination using native map
pathfinding restricted to static edges, then reuses native movement. It validates
the whole route before sending and verifies each room transition. Dynamic map
scripts, arbitrary commands and unsupported recovery actions are refused; it does
not start Go2, change travel preferences or manage unrelated scripts. Standing,
unhiding, opening an admitted obstacle and movement retries share the escape
budget. Unexpected displacement stops the route instead of silently rerouting.
Being already at a freshly verified refuge reports `already_at_refuge` with zero
sends; it does not claim travel occurred. Both adapters still require supervised
in-game verification.

Only one Bigshot owner is allowed. Starting another Bigshot while the expanded
Quick runtime is active is refused before shared hunt state is reset.

## Setup

The **Quick Combat** tab holds separate character presets: profile, mode, area, group
trigger, exclusions, unmatched-creature policy and fallback commands, action/time
limits, loot policy and safety policy. Named trials have a multiline command
editor and optional per-trial limits. Close saves; the window-manager close
discards pending changes. The production GTK construction and save/discard
handlers pass an isolated virtual-display test at 1080x800; lower controls are
reachable through vertical scrolling without horizontal overflow. Player-side
testing in the installed client remains pending.

Fallback commands and trial editor lines use the same command normalization as
normal profiles, including comma ordering, `and` groups and `(xN)` repetition.
The expanded commands are checked before startup; their grouping does not bypass
per-send limits. Saved definitions and the normal selected profile are untouched.

Limits count outgoing support/preparation/retry commands too, not just attacks.
Skipped command conditions still consume a bounded routine attempt. Clear/watch/
assist budgets apply per target; trial budgets cover its complete sequence.

The ineffective-action limit counts definitive failures in correlated native
attack observations, such as misses or attacks warded off. Positive observed
effects reset that counter. Nearby players' attacks, missing output, incomplete
parser batches, multi-attack ambiguity and mixed miss/flare results do neither.
They remain unconfirmed, with action/time limits still applying. Observing a hit
does not establish that a whole command sequence achieved its intended effect.
Status observations include `evidence_reason` for these distinctions.

Structured status and retained results identify the selected preset, profile
(when known), and trial sequence, alongside effective limits and monotonic timing.
`actions` counts reserved budget usage, including skipped attempts; `sends` counts
reported transport attempts, not confirmed game effects. Unverified usage is
identified separately. The observation list retains the latest 100 entries;
total/dropped counts and the retained sequence range disclose any truncation.

Quick briefly waits for the native parser (at most half a second, still subject
to controls and the run deadline). It neither enables combat tracking nor changes
its saved settings. Temporary observers are removed when each routine finishes
or is interrupted. A disabled tracker or missing provenance support refuses
startup with an explanatory message.

Loot choices:

- `off`: no cleanup.
- `own-kills`: use eLoot to process corpses of targets this run engaged. It does not prove that
  this character received the kill credit, and does not take floor loot.
- `room`: use eLoot to process NPC corpses, then collect eligible floor loot when
  items are observed. Unchanged corpse/floor snapshots are not retried every tick.

The designated looter field is an exact character name, case-insensitive; blank
means this character. Other members do not loot. Cleanup does not start while
hostiles are present. Once an eLoot pass starts, ordinary arrivals allow that
bounded pass to finish its equipment handling before combat is reconsidered.
Movement, lost ownership, unsafe state, lifecycle controls, and command/time
limits still interrupt it; forced interruption cannot guarantee equipment restoration.
When only the work command/time budget or supervisor work deadline expires, Quick allows one eLoot-owned
equipment recovery, capped at 12 additional sends and 10 seconds. It can stow
only a recorded borrowed skinning tool, restore the original hands and stand.
It does not resume skinning, searching, pickup or combat. A fresh native guard
still checks identity, room, health and current controls: stop, hold, revoked
permission or unsafe state prevents further recovery sends. The outer LAB
deadline also remains authoritative. Recovery is best-effort, not a rollback
guarantee. The run ends as a failure with `loot_recovery` reporting completion
or unconfirmed restoration; inspect equipment before restarting a failed run.
Loot has independent preset fields `loot_max_actions` and `loot_max_seconds`,
each defaulting to 60, also editable in the Quick Combat setup tab. Existing
presets acquire those defaults without changing combat or trial limits. The
work budget is per room and includes cold eLoot initialization and retries;
it is not reset between corpses. The equipment recovery reserve above is separate.
These limits do not extend an enclosing LAB operation deadline, so that deadline
may end a run sooner. Sends are reported separately as `loot_sends`; those counts
do not establish which items the game awarded.
`loot_sends` includes recovery sends, while `loot_recovery.sends` identifies that
subset. Successful normal cleanup now also verifies original hand identities
and standing before reporting completion.

If a skinning-tool stow was interrupted while waiting for its response,
eLoot recovery observes the original hand update for up to two seconds within
the existing guarded cleanup window. It does not replay that uncertain stow.
A missing acknowledgement reports unconfirmed recovery and requires checking
the equipment; movement or revocation stops the observation wait as well.

An optional supervisor can bind this exact runtime once using
`bind_execution_window(work_deadline:, cleanup_deadline:)`, with absolute
monotonic times and at most ten seconds between them. Ordinary combat, seeking
and loot sends stop at the work deadline (`operation_work_deadline`). No new
corpse pass starts afterward; an interrupted pass may use only the existing
equipment recovery reserve until the cleanup deadline. The window cannot be
renewed, and explicit controls, safety and authority checks still take priority.
LAB reserves twelve seconds before its hard cutoff: ten for equipment recovery
and two for joining/reporting. A short run can finish with unprocessed corpses;
this is a failed/incomplete operation, not successful looting. Standalone Quick
runs without a supervisor window keep their preset limits.

All enabled Quick cleanup uses eLoot's room API and existing eLoot settings for
skinning, searching, filtering and storage. The profile's `loot_script` may be
blank or `eloot` without arguments; other scripts and argument modes are refused.
The updated eLoot room API is required. Its definitions loader performs no game
actions; cleanup runs on Bigshot's guarded owner so support commands and retries
count toward the cleanup budget. Full storage must report a cleanup failure,
not pause Bigshot indefinitely or start a sell trip. No automatic sell or rest
trip occurs. Offline and live verification status is recorded in the smoke-test
checklist; this description is not evidence of an in-game pass.

## Current integration limits

Startup explicitly rejects unowned child scripts, travel/group changes inside
combat routines, explicit multi-target enumeration and helper paths that rely on
implicit targets or unowned reader threads. Numeric equivalents of targeted spell
helpers remain available through the existing command engine. These are remaining
integration work, not a claim of complete profile compatibility.

LAB integration uses the exact Script instance's temporary `quick_combat_runtime`
interface (`request` and immutable `status`), not a character-name global. The
authenticated broker route and exact-child runtime binding are implemented in the
companion LAB worktree. Its optional registration example launches a named trial
within a refuge-to-profile-area-to-refuge outing, without a wrapper or new service.
The encounter itself remains room-pinned. Shipped registration
remains empty. Retained `quick_combat_result` distinguishes terminal failures from
normal completion, but still does not establish game effects. Supervised
end-to-end coverage is not complete. One no-loot seek/combat/return outing and
one ordinary-stop return have passed; assist, trial, and live room-scoped eLoot
combinations remain pending.

Agent-supervised outings now have a separate explicit
[refuge contract](bigshot-quick-refuge-outings.md): native bounded outbound/work/
equipment recovery/return, with retained work results and independently verified
handoff. This is opt-in; standalone Quick controls are unchanged. Live acceptance
verified the 28-room outbound/return outing above, original hands, standing,
released ownership, full health, and a separate ordinary-stop return.
