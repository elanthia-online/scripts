# Bigshot Quick Combat expansion

Status: implementation plan based on the player's approved use cases (2026-09-09).
Source baseline: EO scripts `2fc2aacb`. The player subsequently made completion
and submission of this PR the explicit goal. Installed script changes and live
combat testing still require a coordinated player-authorized deployment step.

Upstream coordination: Horibu identified the pending Bigshot stack
[#2414](https://github.com/elanthia-online/scripts/pull/2414) -> #2415 -> #2416 ->
#2417 -> [#2433](https://github.com/elanthia-online/scripts/pull/2433), currently
ending at `273fa778` (updated from `ddb0f26a`) and awaiting Lich 5.21.0. Integrate that stack with current
master for development, then rebase encounter-only changes onto the published
base when it lands. Do not deploy this development stack as a released dependency.

Maintainer direction (Horibu, 2026-09-09): this expands existing Bigshot Quick.
Public commands use `;bigshot quick ...` and the setup tab is **Quick Combat**.
"Encounter" remains an internal controller term, not a competing hunting engine.
This supersedes the earlier proposed `;bigshot encounter` namespace. The plan's
filename remains stable so shared links continue working.

Compatibility target confirmed by the maintainer: Bigshot 5.16.0 with Lich 5.21.0
Combat/Creature APIs. The maintainer's optional prerelease test command is
`;lich5-update --branch=release-please--branches--main`; this is recorded for a
later authorized installation, NOT executed by this work. Prepare user-facing
Quick Combat documentation alongside code for the maintainer's wiki pass.

Read-only prerelease inspection uses Lich commit
`f1e7021675b868522272a7c305623268bb224ea0`, fetched from the release-please
branch. This does not install the prerelease or prove live compatibility.

## Objective

Let Bigshot execute local combat without owning a full hunting session. Preserve
normal hunting, bare quick mode, and existing coordinated head/tail behavior. Reuse
combat profiles instead of maintaining a second combat engine. Human-led groups
must not require any other player to run Bigshot or share a coordination server.

## Interface and behavior

Proposed extended commands under `;bigshot quick` (not existing top-level `test`):

- `clear`: clear eligible targets in this room, optionally search/loot, then stop.
- `watch`: repeat local encounters as the player moves; never choose hunt routes.
- `assist --leader NAME` or `--trigger any-group`: wait for fresh observed group
  engagement in each room; strict assist or assist plus eligible room cleanup.
- `trial NAME --target ID`: bounded named sequence; no automatic kill routine
  after the sequence; structured completed/interrupted/uncertain results.
- `status`, `hold`, `resume`, `stop`, `retreat`: explicit lifecycle controls.
- `--profile NAME` and `--preset NAME`: run-local profile/policy selection.

Bare `;bigshot quick` retains its existing behavior during this development.
Extended subcommands must be parsed explicitly before the current broad quick
match; an unknown or malformed extended command must never silently start combat.

Profile supplies permitted creatures, exclusions, priorities, attack routines,
and applicable safety/loot/escape settings. Travel/rest/sell scripts do not run
implicitly. Runtime overrides must not change the selected hunting profile.

Engagement and target eligibility are separate. Explicit exclusions win.
Unmatched targets default to deny and may use a configured per-character fallback
only under explicit authorization or the configured group-engagement policy.
Unmatched does not imply hostile. Ambiguous creature identity must not authorize
an attack against another identically named creature.

Room changes invalidate target identity and group engagement. Clear/trial stop;
watch/assist re-evaluate or wait according to their mode. Never chase independently.
Hold retains local emergency checks; stop ends monitoring. Escape preempts combat
and loot, verifies displacement, uses only configured fallback destinations, and
ends the encounter. Already-issued commands and game roundtime cannot be cancelled.

## Setup UI

### Approved area-scope refinement

Supervised testing exposed that a single fixed LAB handoff room is too narrow
for ordinary hunting. Reuse the selected profile's starting room and boundary
rooms, resolved through Bigshot's existing area calculation, as the source of
truth. Do not introduce a separately maintained LAB room list or duplicate
pathfinding. Resolve room IDs/UIDs using native profile semantics.

Individual clear/trial runs retain exact starting-room and target pins. A
supervised test may start another run after the player moves within the approved
profile area. Watch/assist should validate area membership as they re-evaluate
new rooms. Crossing a boundary must revoke prior target permission, not chase
the target outside it. Movement and returning to refuge remain distinct from
simply ending a room-clear operation.

Automatic wandering remains deferred to a later explicit opt-in that reuses
Bigshot movement, not an implicit side effect of clear/watch/assist or a remote model reacting to each
monster. Preserve configured escape handling, finite run limits, and eLoot-only
cleanup. No rest/sell cycle is enabled by this refinement. Test boundary/UID
resolution, crossing, target departure, and cancellation offline before a
supervised multi-room run. Profile-area enforcement is implemented in the
development worktrees; live verification remains pending. No wandering mode is
implemented by this refinement.

### Approved bounded search-to-Quick addition

The player subsequently approved adding a bridge-driven find-target handoff.
Implement explicit `quick seek --area profile`: reuse native profile-area
resolution, Quick target policy, native guarded movement, and the existing
combat/eLoot controller. Do not invoke the full `bs_wander` upkeep/follower/loot
loop, a separate generic wander script, or an agent round trip per room.

Cap search at 12 ordinary mapped steps/30 seconds (or smaller preset limits),
with one direction send and verified arrival per step. Pin the first encounter
room and clear it once; never resume searching afterward. Existing modes gain
no movement authority. LAB uses the existing opt-in controller manifest and
`quick_area` proof, requires movement/combat ownership, and adds no listener or
arbitrary-script capability. Test cancellation, map callback denial, arrival
races, limits, and unchanged legacy modes before deployment/live testing.

## Setup controls

Add a Quick Combat tab/panel, preserving existing hunting tabs:

1. Combat profile/current profile and named encounter presets.
2. Mode, engagement trigger/member, strict assist versus room cleanup.
3. Unmatched-target policy, fallback routine, bounded failure handling.
4. Loot off/search/room loot, designated looter; no sell trips.
5. Inherited safety settings and explicit hold/retreat policy; warn on missing
   escape configuration rather than guessing a safe destination.
6. Named trial files with preview/selection; no visual programming framework.

## Ordered implementation and verification gates

### A. Source inspection and contracts

Verify initialization side effects, profile persistence, attack-loop interruption,
loot behavior, and Lich's actual group-attack evidence. Inspect LAB's existing
script-test interfaces. Record limitations before selecting implementation seams.

### B. Encounter foundation

Implement a self-contained Bigshot module for validated encounter policy and
lifecycle; extend the quick entry point and existing attack execution only where
command ownership and cancellation can be enforced. No new
network listener, scheduler service, unsafe thread termination, or source eval
to import another installed script. Normal hunt paths remain unchanged.

### C. Profiles and setup

Add validated settings and run-local profile selection, scoped GTK controls,
and documentation. Keep character/preset data private and defaults inert.

### D. Group assist and unknown targets

Recognize only verified current-room/current-member attack evidence. Reject stale
and ambiguous target references; reset on movement/group membership change.
Exercise duplicate names, dead targets, leader departure, and invasion fallback.

### E. Bounded trials and LAB

Reuse LAB's existing authorized script-control path. Define bounded requests,
results, timestamps, action observations, and stop reasons. Trial constraints
must apply at command dispatch, not merely between whole multi-command routines.
Do not claim a command was successful just because it was sent. No added authority.

### F. Verification, integration, then player smoke test

- Ruby syntax and existing Bigshot specs remain green.
- Offline tests execute production policy/controller methods against fake game
  state: target filtering, movement, hold/stop, exclusive ownership, deadlines,
  repeated failures, retreat, unknown targets, and no unexpected loot/travel.
- Setup settings round-trip, invalid settings fail visibly, selected normal
  profile remains unchanged, no automatic migration of personal profiles.
- Simulated human-led traversal issues no attacks until verified engagement.
- Trial action/time limits stop future dispatch; emergency interruption is not
  reported as test success.
- Main agent reviews each subagent change and runs integration tests.
- Deployment is a separate player-authorized step with a private backup. Begin
  with status/hold/no-target tests, then a supervised low-risk encounter.

## Source findings and first implementation gate

- Existing quick mode suppresses wound/flee/rest checks. Expanding it requires
  explicit policy-aware checks, not assuming current quick is already safe for
  bounded tests. Preserve bare quick semantics until that change is verified.
- Bigshot initialization has hunting side effects; encounter help/status must not
  initialize a hunt or reset a running controller's globals.
- Existing `attack`/`cmd` routines may invoke looting, travel/escape helpers,
  arbitrary scripts, nested attacks and retry loops. A bounded trial requires
  checked dispatch inside these paths, not a count of outer routine calls.
- The profile field `invalid_targets` means creatures ignored for swarm counting,
  NOT a never-attack list. Preserve it and use explicit encounter exclusions.
- Pending upstream `BigshotCreature`/`bs_targets` logic should supply native
  creature status where appropriate. Estimated HP is not proof of death.
- Target Lich prerelease supplies structured `Combat::Tracker.on(:attack)`
  callbacks with actor/target identity for supported human attacks. Reuse them,
  rather than adding a competing text parser. They lack receipt-time room/session
  binding; verified event-family fixtures and that binding remain required before
  automatic assist activation. See the LAB contract for exact source limitations.
- LAB's existing fixed-case test runner is non-combat and kills children at its
  deadline; use its registered controller transport, not that runner, for combat.

The first implementation therefore supplies an INACTIVE policy/controller and
configuration foundation plus offline tests. No user command may enter combat
until the emission-level adapter, ownership, bounded wait/cancellation behavior,
and group evidence gates have passed. The setup pane must say this plainly.

The foundation's narrowly validated command fixtures are an offline contract,
not a replacement combat language. Existing Bigshot profile routines (including
UAC, modifier checks, targeting and spell helpers) must remain the eventual
execution engine; do not ship a restricted second engine and claim full profile
compatibility. Trial restrictions may be narrower but must be explicit at admission.

## Progress checkpoint

- Implemented inactive policy/controller with injected snapshots and dispatch;
  exact target/member evidence, room epochs, exclusion/fallback policy, limits,
  hold/resume/stop, and verified retreat outcomes are covered offline.
- Implemented separate character preset storage and Quick Combat configuration
  preview. Invalid stored encounter data does not break normal hunting setup.
- Integrated pending stack with current master; preserved Creature targeting,
  command checks, help, YARD documentation and the looting pause-race fix.
- New Quick subcommands are classified before settings/global initialization.
  Strict startup parsing prevents accidental fall-through to legacy Quick.
- Strict Quick request parsing and detached profile/trial resolution implemented.
- Existing constructor supports detached Quick initialization without navigation,
  group commands, tracker activation, profile/cache writes or hunting cleanup.
- Pure configured safety observation implemented; evaluating arbitrary saved
  wound Ruby remains the owner's responsibility, never part of the pure query.
- Synchronous native-parser attack feed captures room/session provenance before
  admission; synthetic fixtures cover exact identities and rejected ambiguity.
- Instance-local Quick I/O guards exercise the existing `bs_put` send/retry loop,
  waits and `get?` polling. Deadline checks run after collecting observations too.
- Controller execution admission is injectable, so a production adapter can reuse
  Bigshot profile syntax. Actual send accounting is separate from routine position.
- The execution bridge now invokes the existing `cmd` on its original receiver
  inside the native Lich guard scope. Direct and Spell-receiver sends share one
  budget; local denials remain cancelled even if a helper rescues the exception.
  QuickRun now owns its controller, bounded control mailbox, fresh guard scopes,
  immutable cached status, sticky session binding and complete interruption send
  accounting. Extended CLI startup now attaches this loop after ownership,
  dependency and configuration admission; no installed script was changed.
- Scoped upstream controls handle commands before Lich's duplicate-script check;
  they queue controls rather than launching a second Bigshot. Cleanup removes the
  hook and closes the run. Optional deferred validity checks reject expired LAB
  controls, including a retreat that expires while combat is unwinding.
- Fresh observation reads native hostility, current room generation, cached boon
  exclusions and verified present group members without issuing probes. Parsed
  A-J routines are reused without modifying the saved profile/target mapping.
- Quick command scope bypasses hunt rest/loot checks and defers legacy escape
  helpers to the owner. Unowned child scripts are explicitly rejected. Native
  swing waiting now uses guarded owner reads, restores stream flags, and creates
  no child observer or shared-global target state.
- Named trials now have a selector, multiline command editor and optional limits
  in the settings pane, with validation and round-trip tests. No GUI render or
  live behavior claim is implied by the widget tests.
- Enabled development CLI startup uses detached profiles and exact native owner
  identity. It publishes a scoped `quick_combat_runtime` on that Script instance
  for optional external controllers, without importing LAB or a global run holder.
- Native synchronous human-group hooks now feed the owner loop, with receipt and
  drain-time room/session/member checks. Five optional regressions use actual
  native XML/Ox/Combat parser and hook implementations: normal attack accepted,
  non-main stream/speech/mixed movement rejected, and queued movement invalidated.
  Supervised human-group observations remain required before a live claim.
- Quick cleanup searches observed corpses and optionally takes room loot with
  guarded native commands. It supports an explicit designated looter, remembers
  attempted corpses/floor snapshots, and never starts a loot/sell/travel child.
  "Own kills" means targets this run engaged, not verified kill-credit ownership.
- Configured 130 and static-route walking retreat are implemented with native
  bounded casting/movement and fresh mapped destination/survival checks.
  Complete command-path admission (notably implicit-target/child/multi-target
  helpers) and live tests remain incomplete. Unsupported paths fail at startup.
- Actual GTK construction is verified under an isolated Xvfb display at 1080x800:
  no horizontal overflow, lower trial controls reachable by scrolling, Close
  round-trips settings, and native window close discards staging. Installed-client
  player verification remains pending.

Offline verification (2026-09-09): `rspec spec/scripts` passed all 761 examples;
Ruby syntax validation passed. Targeted RuboCop covers Bigshot and its new specs.
Whitespace validation passed with the repository's existing CRLF format allowed.
These checks cover the development startup and executor with synthetic game state,
not a deployed client, rendered GTK window, or live combat execution.

Execution checkpoint: 40 focused tests pass with the real companion guard and
native scope methods. Source-extracted production `cmd`, modifiers, `bs_put`,
`cmd_spell` and `cast_spell` verify exact target substitution, canonical Spell
routing, bounded retries/arrays and sticky interruption. Zero-send modifier
skips are reported as `skipped`, while still consuming a bounded routine attempt.
The production QuickRun/controller now also drives the extracted real command
engine in these checks: queued hold interrupts between prepare and cast, retains
the attempted-send count, and resume acquires a fresh scope. A changed session
between routine calls stops without issuing another command.
Remaining executor integration includes complete command-path admission (including
child scripts and multi-target actions) and live verification.
An additional 82 focused examples passed using the real companion guard; this
includes the scoped native loot wrapper and owner lifecycle tests.

LAB work is isolated in `lich-agent-bridge-quick` on
`feat/bigshot-quick-controls`, based on public LAB `6bf44da`. The private runtime
checkout is untouched. Typed exact-operation controls now use the existing broker
and authenticated HTTP/CLI path; native exact-child binding and an opt-in direct
trial registration are committed locally as `50bfa26`. They do
not waive LAB's one-active-operation rule or claim application/safe handoff merely
because a control was admitted.

Current integration follow-ups (source-backed, not scope expansions):

- Group startup now issues at most one bounded owner-thread GROUP query when
  needed. Runtime invalidation revokes assist/cleanup permission before the next
  send and holds with `group_membership_unverified`; GROUP, resume and a fresh
  attack restore engagement. No parser callback queries or clears group state.
- The `unknown: manual` preset policy now has `quick engage ID`: bounded owner
  mailbox, pinned room/epoch, three-second application expiry, and fresh final
  target validation. It does not override exclusions or unknown-ignore, retarget
  trials, survive movement/resume, or widen the LAB control schema. Source-backed
  tests cover a room change between admission and final target observation.
- The Bigshot stack remains open at `273fa778` (PR #2433) and the latest
  published Lich release remains 5.20.1 as checked through GitHub on 2026-09-09.
  Final rebasing/submission must keep those dependencies clear.
- Integrated the stack's subsequent Lich 5.21 minimum and negative-UID fix.
  Quick retreat resolves signed UIDs too, while resolved map room IDs must remain
  positive, known and unambiguous. A regression covers negative-UID destinations
  and profile fallback; this does not admit dynamic or unsafe retreat routes.

Review found the saved UAC flag means **do not mstrike**, not enable mstrike.
Quick now admits either profile value, keeps single-target UAC, and suppresses
only its automatic mstrike escalation. Production-handler tests preserve legacy
flag behavior and verify Quick does not enter the room sweep. Further profile
review is checking per-target UCS state and implicit-target spell helpers before
admitting those paths.

### Dependency decision: native spell interruption

Read-only inspection of Lich prerelease `f1e70216` establishes a missing seam:
`Spell#cast` in `lib/common/spell.rb` owns preparation/cast/stance sends and retries.
Its inherited helpers execute on the Spell receiver, not the Bigshot instance, so
Bigshot's local QuickIO cannot guard them. `Game.puts` writes through `_puts`;
`UpstreamHook` is client input and does not intercept these script sends.

Native script pausing cooperates with `Script.current`, but resuming a suspended
cast can continue against the old target. It provides no send-budget, deadline
or room-generation predicate. A before/after wrapper cannot claim those guarantees.
Duplicating Spell instances is not equivalent: `cast` updates canonical state
such as `last_cast`, and custom cast procs can call shared objects again.

Player-approved companion Lich change (2026-09-09): a per-script command
guard immediately before game writes, with cooperative cancellation checks in
native waits/retries. Cancellation must unwind existing ensure blocks, including
spell locks and downstream settings. No global monkeypatch or replacement cast
engine. Work is isolated in `lich-5-execution-guard` on
`feat/script-execution-guard`, based on Lich prerelease `f1e70216`. Do not enable
the new combat modes until this dependency and the Bigshot adapter are verified.
No installed Lich files have been changed by creating this worktree.

Companion checkpoint: `7750b1ee` implements opt-in per-script scopes, native
game-write checks, cooperative read/wait cancellation and documentation. Full
Lich regression run: 7,100 examples, zero failures (seed 50399), using the local
effect-list fixture and local-socket test permissions. Changed production and
test files pass RuboCop. Committed locally only; not pushed or installed.

An experimental guarded-child follow-up (`83ec0aa4`) was tested locally, then
removed from the proposed diff because the final walking adapter needs no child
process. The experiment and its test remain recoverable in local history. The
companion retains the original per-script scopes, cooperative native movement
waits, and opt-in static-edge pathfinding; it is not a Ruby sandbox.

After removing that experiment and adding cooperative movement waits, the full
native suite passes 7,110 examples (seed 50399) with isolated fixtures and local
test sockets. Changed native files pass RuboCop. This is still a local-only
dependency, not installed into a player session.

Walking-retreat integration decision: do not invoke all of Go2's session setup
from an emergency adapter. Existing Go2 unconditionally pauses unrelated
`roomnumbers`/`textsubs` workers and writes travel preferences; a socket guard
cannot isolate those Ruby effects. Reuse native Map Dijkstra with an opt-in
static-edge restriction, followed by native `move` for exact admitted edges.
The default pathfinder remains unchanged. Dynamic `timeto` and `wayto` procs
are not an admitted static route and must never execute during this planning.
Choose only among explicitly configured mapped destinations, verify each expected
transition and final refuge, and retain action/time/control checks throughout.
Unsupported movement recovery must fail visibly rather than call inventory,
spending, custom scripts, or alternative escape spells. The implemented adapter
has source-backed tests using real native Map, Script, movement and socket-write
methods with synthetic transport/room observations. These verify bounded retries,
stand/open recovery, interruption during waits and unexpected-room rejection;
they are not a live-verified recovery claim.

Combined regression checkpoint: 899 Bigshot examples passed with native Lich
integration and actual GTK construction enabled, without pending examples. The
shared native-command fixture was extracted into test support to avoid duplicate
example registration. No installed scripts or personal settings were modified.

### Review checkpoint and outcome-evidence integration

The two-axis review of `99b8c32d` found no hard documented standards violations
and two duplicated contracts: trial normalization and A-J routine resolution.
The requirements review reproduced three functional gaps: legacy whole-room
priority could veto an authorized assist target; verified roster changes could
leave room-cleanup permission alive; and the ineffective-action settings had no
native evidence producer. All three now have source-backed regression fixes.
Trial normalization and detached A-J routine resolution also share their existing
settings contracts rather than maintaining divergent validation paths.

Native `Combat::Parser.parse_outcome` and `Combat::Processor` already classify
misses, warding, hits and related facts. Reuse that evidence rather than inventing
a second parser or treating unchanged estimated HP as proof of failure. Current
attack callbacks lack ingestion room/session provenance, may run asynchronously,
and require shared `emit_attacks` settings. Callback-time room sampling and
Bigshot's first matching `get_res` line cannot establish command attribution.
The companion now preserves native ingestion provenance through delayed and held
events. Quick consumes a bounded owner-thread queue and distinguishes definitive
failure, observed positive evidence and uncertainty. Missing output never becomes
a fabricated failure or success. A temporary attack subscription requests native
events without changing persisted settings; disabled tracking refuses startup.
Complete native parser batches are required before classifying a root event.

Latest combined Bigshot checkpoint: 993 examples, zero failures, with native
integration and real GTK enabled. Twelve native replay cases exercise the installed
Tracker hook, XML/parser/processor/observer path and Quick classifier, including
pre-command queue timestamps, room changes, foreign attacks and miss-plus-flare
ambiguity. Separate production executor tests prove threshold-triggered hold and
retreat, bounded waiting, lost-tracking interruption and observer cleanup. These
are complementary offline proofs, not a claim that a single fixture executes the
entire live socket-to-game cycle. The full companion suite now passes 7,127
examples (seed 50399, local test sockets permitted). Its initial failures exposed
a Tracker test fixture loading the real DB_Store over a shared test double;
isolating that constant and restoring require-cache state fixes the cause, with
an after-example method-identity regression. No database production workaround
was needed. Live verification remains a release gate; use the coordinated
[smoke-test checklist](bigshot-quick-smoke-test.md) and record actual outcomes.

The native provenance checkpoint is `b3a43f8e` in the companion guard worktree.
LAB companion `f039081` was reverified with all 712 Python tests (Ruby explicitly
configured, no skips) and 107 focused Ruby bridge/controller tests, 636 assertions.
This verifies the development adapter, not an installed registration or live
combat operation. The shipped controller registry remains empty.

The same checkpoint adds native `resonance` rotation and `leech` through the
existing guarded incant/selector path. All resonance candidates are admitted
before selection; numeric travel exclusions match native integer conversion,
including leading zeros. Leech retains its existing no-op/resource/cooldown
behavior and legacy implicit casting outside Quick. Actual native Spell/Script/
socket fixtures cover selector changes, retries, budgets and cleanup.

Group attack evidence now also uses the original queue ingress timestamp on the
exact game parser thread. A reproduced bug had stamped queued old input with
the downstream hook's later clock, bypassing startup/resume cutoffs. Regression
fixtures reject old, missing, future and off-thread receipts and retain fresh
timestamps through native replay and controller admission. The main-stream/raw
chunk and roster-binding checks remain intact.

Bigshot bridge tests also run against the real companion guard and extracted
native Script scope methods with `LICH_EXECUTION_GUARD_ROOT` set to its checkout.
These offline tests are not a substitute for the remaining live-mode tests.

### Native command compilation and bounded reporting checkpoint

The follow-up requirements check found that fallback/trial text bypassed the
normal profile compiler and that retained trial reports omitted selected names,
effective limits and observation truncation. Both are now implemented through
the existing engine and controller: `clean_value('split_xx', ...)` compiles
fallbacks and trial lines before admission, preserving comma order, `and` groups
and repetition. Every expanded leaf is validated, and actual native sends inside
groups still consume the same action budget. Stored definitions are not changed.
The legacy compiler's eager repetition allocation is unchanged; this is not a
new untrusted-input parser or general macro compiler.

Status retains immutable preset/profile/sequence names, effective limits and
monotonic timing. Its bounded observation ring reports total/dropped counts,
sequence range and per-entry sends separately from reserved attempts. Unknown
send usage remains explicit rather than being reported as zero. Native `efury`
and plain `tether` now use an owner-thread completion wait instead of unowned
reader threads in expanded Quick; ordinary helper behavior is retained outside
Quick. Transfer-following `tether recast` is still refused.

Combined verification: **1,045 examples, zero failures**, with native integration
and real GTK enabled; **41 lint files clean**. The initial sandboxed GTK attempt
could not initialize its display; rerunning with isolated virtual-display access
passed. No live game commands or installed-file changes were made. Upstream
scripts PR #2433 is still open at `273fa778`, and the latest published Lich
release remains v5.20.1. Prerelease installation, supervised smoke tests and PR
submission remain unverified delivery gates.

LAB companion `446cde8` repairs a reproduced report-transport mismatch without
raising protocol budgets: native grouped commands become labeled display text,
overlong command text is explicitly shortened, and the oldest observations may
be omitted with separate transport counts/range. Runtime totals and control
identity are preserved. The unchanged server validator accepts actual Bigshot
controller reports for simple, grouped, oversized-group and long-text cases.
LAB verification passes 712 Python tests plus 111 focused Ruby tests with 675
assertions and no skips. These changes are checkpointed locally, not deployed.

### Historical implementation sequence: real `quick clear`

The following records the original implementation sequence, not a new backlog.

1. Add a per-run Quick context, retaining legacy `$bigshot_quick` semantics for
   bare Quick. Parse extended options exactly and read profiles without mutation.
2. Separate safety-reason observation from `ready_to_rest?`/`should_rest?` side
   effects. New Quick policies decide hold/retreat without invoking `rest`.
3. Branch `pre_hunt`/`do_hunt` completion to prevent travel, group reassembly,
   departure/restart, resting and unrequested hunting scripts.
4. Keep profile A-J target routines and current Creature adapters; do not let
   quick target discovery overwrite the run's configured creature mapping.
5. Introduce cooperative guards at actual command sends and retry/wait points:
   `bs_put`, direct `fput`, spell casting and force helpers, UAC, wand/ranged,
   `eachtarget`, and external child scripts. Audit helper-internal retries too.
6. Keep loot off until room/ownership checks and cancellation are verified.
7. Test real production routine paths (conditions, repeat/force, UCS) with fake
   transports. Only then enable `quick clear`; watch/assist/trial follow the same
   executor instead of adding another attack language.

## Scope exclusions

No new generic scripting language, automatic learned creature rules, autonomous
selling/restocking/navigation, required scripts on other players, LLM in the
combat timing loop, or changes to game action authority. If a required capability
cannot be verified, keep it disabled and document the remaining work explicitly.

## Approved eLoot integration update

The player requires all enabled Quick loot to use eLoot, and authorizes focused
eLoot changes to support it. This supersedes the earlier native-loot-only
restriction. Keep existing off/own-kills/room/designated-looter policies and idle
deduplication; reuse eLoot's ordinary room routines and settings. Add a narrow
definitions-only native loader and guarded owner-thread room entry point, not a
new child-execution framework. Scoped calls must not sell, travel, manage other
scripts or pause the parent indefinitely. Cancellation must propagate through
reachable retries without post-cancellation game-command cleanup.

Implementation and offline integration verification are complete: 1,085 examples
pass with the native companion and real GTK enabled; nine changed Ruby/script
files are lint-clean and CRLF-aware whitespace checks pass. The suite includes
real native child loading/teardown and guarded socket boundaries, plus full-file
eLoot loading and room-path fixtures for exclusions, missing profiles, partial
initialization, full bags, occupied hands and cancellation through retries.
These are offline fixtures, not verified game-server outcomes.

The player selected a supervised test character and confirmed all sessions closed.
The private rollback archive was verified against the installation before the
code-only update. The installed test library and Bigshot/eLoot match the source;
account/character data, profiles, Gemfile/lock, maps, logs and LAB symlinks were
not changed. The supervised game checklist has started; combat remains untested.

Before deployment, companion Lich merged upstream main `073d23a9` (including
frontend registry #1558 and HTTPS fallback #1570) into the tested development
base. Companion checkpoint `175893da` passes 7,248 examples, zero failures,
seed 50399. A test-only fixture reset prevents Authenticator's fake character
from leaking into SetupFiles examples; the two-example regression failed before
and passed after the reset. Production login code was not patched for that test
failure. Bigshot/eLoot's 1,085 native/GTK examples also pass against this merge.
The installed build reports 5.21.0 but remains a development build; the latest
published release at this verification was v5.20.1. Private rollback instructions
and exact installation paths are recorded outside the public source tree.

### Setup persistence regression

The first supervised setup test found that Close reported saving but the Quick
preset did not persist. The player used the saving button, not window close.
GTK callbacks run without `Script.current`, so implicit CharSettings reads and
writes lost the originating script namespace. Setup now captures a native
settings proxy on the owner thread before queuing GTK work, and detaches the
stored mapping for the staged editor.

A subprocess regression uses real GTK callbacks, native Script/Settings and a
temporary SQLite database with the application's script/scope uniqueness index.
It fails against the previously installed script and passes with this fix. It
verifies a cold-cache reopen under a new script owner, preset and trial reload,
runtime settings consumption, unrelated settings preservation and X-close
discard. The full native/GTK suite passes 1,086 examples with zero failures; all
five changed Ruby/script files pass lint. The player's persistence retest passed.
The next empty-room attempt correctly refused disabled native combat tracking;
after the player enabled it, admission rejected a child-script combat routine.
A separate private smoke profile uses a targeted native attack without changing
normal hunting profiles. Routine admission errors now name the rejected compiled
command; its regression failed before the message fix and passes afterward.
The updated suite passes 1,087 examples. Empty-room live completion and later
checklist stages remain unverified.

## Rollback and delivery

Worktree: `lich-scripts-encounters`, branch `feat/bigshot-encounters`. Only the
approved backed-up test installation was updated. Deliver source/tests/docs and report precisely
which modes are implemented, offline-verified, and live-tested; do not equate a
pure controller test with a safe in-game release. The active goal includes PR
submission after implementation and verification, plus the approved focused
Lich-core guard dependency; unrelated Lich changes remain excluded.
