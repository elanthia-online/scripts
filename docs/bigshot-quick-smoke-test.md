# Supervised Quick Combat smoke test

Status: **in progress**. Preset persistence, empty-room clear, watch/hold/resume/
stop, duplicate-start refusal, and single-target no-loot combat are player-verified.
The first own-kills eLoot attempt failed to finish after skinning and entered a
held state; manual stop exited successfully. A subsequent supervised remote run
on the finish-current-pass build completed kill, skin, knife stow, stand, search,
coin collection, and owner release (1 combat send, 9 loot sends; about 14 seconds
including roundtime). This verifies one warm-start own-kills pass, not cold-start
cleanup, new arrivals during cleanup, all equipment configurations, or room loot.
The first remote launch exposed hidden-child ownership rejection before any
combat sends. A native parent/child regression now covers admission and hidden
duplicate exclusion. The corrected remote launch completed a supervised clear
with no eligible targets: zero sends, immutable terminal report received, and
safe owner release verified by LAB. A later remote run sent one attack and the
target died, but bridge startup revoked the run before cleanup because declared
inventory ownership was not recognized. That omission has a failing-then-passing
bridge regression and the successful remote cycle described above.
The later cold-start/deadline follow-up below supersedes earlier recovery-status
notes; it does not turn an interrupted loot operation into a successful pass.
Offline test results do not satisfy this checklist.
Coordinate each live stage with the player; this document grants no permission to
install a prerelease, start combat, move a character, or change personal settings.

## Before logging in

Record exact Bigshot, companion Lich and LAB commits. Back up the installed files
and the selected character's Bigshot settings privately, with a tested restoration
path. Never publish credentials, character profiles or raw private transcripts.
Use the agreed Lich 5.21 development base only with explicit player approval;
the companion execution guard and combat provenance changes are also required.

Select one character and a familiar low-risk target area, with the player present.
Record a reachable safe destination and which retreat adapter will be tested.
Do not manufacture dangerous wounds or a swarm to test safety. Use offline tests
for those fault injections. Stop immediately on unexpected commands, identity
changes, uncontrolled movement, or failure to accept a lifecycle control.

Create a disposable Quick preset in `;bigshot setup`: use an existing known-good
combat profile, loot off, unknown creatures ignored, conservative action/time
limits, and hold on failed actions. Keep the original hunting profile selected.
Use a second explicitly configured preset for each later loot/group/retreat test.

Native combat tracking must also be enabled for the selected character. It is
off by default; with the player's approval, enable once using
`;e Lich::Gemstone::Combat::Tracker.enable!`. This observes combat and persists
the preference; it does not initiate combat. Missing provenance support still
requires the companion Lich build, not a bypass of the admission check.

Check the selected profile's actual A-J routines before the live test. Profiles
that delegate attacks to `script ...`, or use other unsupported command paths,
must not be silently rewritten. Create a separate disposable profile with
supported targeted commands and select it in the Quick preset's Combat profile
field. Do not replace the character's normal hunting profile.

## Ordered cases

Record the command, starting room, exact target ID if applicable, observed sends,
final state/reason, and pass/fail evidence for each case. A printed startup or
`sequence_dispatched` message is not proof of combat effects or safe extraction.

1. **Setup and no owner.** Open the Quick tab at normal window size, save the
   disposable preset, reopen and verify it. Cancel another edit via window close
   and verify it was discarded. Run `;bigshot quick status` without a run: no hunt
   or movement should start. A malformed command must also refuse without a hunt.
2. **Empty-room clear.** In a verified empty room, run
   `;bigshot quick clear --preset "Smoke"`. It should finish without attacks,
   looting, travel, rest/sell scripts, or changes to the normal selected profile.
3. **Watch controls.** Run `;bigshot quick watch --preset "Smoke"` in a safe room.
   Check status, hold, resume and stop. Held mode must not issue normal combat or
   loot commands. A stopped run must leave no active owner or temporary hooks.
   While another watch owns Bigshot, a second start must refuse.
4. **One known target.** With fresh player approval, clear one eligible creature.
   Confirm the original profile routine and exact target are used, output updates,
   and clear ends after room completion. Loot remains off. Verify ineffective
   observations only if genuine misses/warding occur; missing evidence is unknown.
5. **Movement and priority.** Repeat watch while the player changes rooms. No old
   target permission may survive. For clear/trial, movement must terminate the
   run instead of following. In a room with multiple targets, verify the selected
   eligible priority; do not add extra danger merely to create this condition.
6. **Human assist.** With a consenting friend, use
   `;bigshot quick assist --leader FRIEND --preset "Group smoke"`. Neither player
   needs a head/tail setup. Before a supported observed attack, Quick must wait.
   After the friend attacks, verify assistance against that exact target. Hold,
   movement, leader departure and roster changes must revoke old authorization.
   Strict assist must not clear unrelated targets. Test any-group and configured
   assist-then-cleanup separately. Retain sanitized native attack evidence for the
   families tested; do not generalize one weapon-family result to all attacks.
7. **Unknown/manual selection.** Use an explicitly configured manual fallback
   preset and `;bigshot quick engage ID` on a player-approved hostile target absent
   from its patterns. Verify the fallback routine. An excluded target must still
   refuse; no target may be chosen merely because its name is unfamiliar.
8. **Loot opt-in.** Test own-kills and room loot separately on expendable loot with
   a designated looter. Verify no sell trip, no repeated idle-room looting, and
   completion of the admitted eLoot pass and equipment restoration before combat
   resumes when an ordinary hostile arrives. Emergency and explicit controls must
   still interrupt cleanup. Do not use valuable possessions for
   this test. Verify the same eLoot filtering/storage settings used outside Quick.
   Test blank and exact `eloot` profile settings; unsupported scripts/arguments
   must refuse. Full storage must not launch a sell trip or leave Bigshot paused.
   Hold/stop during cleanup must prevent subsequent game commands, including
   cleanup retries. Missing room-API support must fail visibly, with no surviving
   definitions-loader child. Include helper/initialization sends in the budget.
9. **Retreat.** In safe conditions, explicitly request `;bigshot quick retreat`
   using each approved adapter (130 and static walk). Verify actual arrival,
   fresh safe-room confirmation, terminal result and released ownership. Already
   at refuge must report that fact with zero escape sends, not claim a journey.
   A spell acknowledgement without arrival is not a pass.
10. **Local bounded trial.** Configure a short named sequence and run
    `;bigshot quick trial NAME --target ID`. Verify its target, actual-send budget
    (including support/retries), time limit, no automatic follow-up kill routine
    and no loot. Hold/stop must interrupt future sends. Record observed game
    effects separately from dispatch completion. Check retained configuration
    names, effective limits and timestamps. Include a short `and` group/repetition
    case to verify native ordering and per-send accounting; use offline tests for
    observation-ring overflow rather than adding unnecessary live attacks.
11. **LAB trial.** Register the opt-in example only for the approved character,
    named sequence and safe destination. Use the existing authorized controller
    transport with a fresh session generation. Confirm exact-child ownership and
    status/hold/resume/retreat controls; stale or foreign operation IDs must refuse.
    After terminal dispatch, the supervising player retains extraction duty until
    safe handoff is actually confirmed. Do not report a successful test merely
    because the broker accepted the launch.
12. **Legacy and cleanup.** In a separate, explicitly approved session, verify
    bare Quick and the player's normal profile still behave as before. Restore
    disposable settings, confirm no lingering Quick observers/owner, and record
    which installed versions remain. Preserve private rollback copies until the
    player accepts the build.

If a prerequisite or expected observation is unavailable, mark the case **not
verified**, not passed. Fix and rerun the affected stage before PR submission.

## Bounded seek follow-up (partial live verification)

Supervised verification on 2026-09-09 confirmed one in-area movement, immediate
combat in the arrival room, a game-reported kill, and terminal owner release with
health and equipment intact. The initial live failure was a saved wound expression
rejecting the seek guard as unrelated to the combat scope. An explicit exact-owner
seek wrapper fixes that without bypassing fresh wound checks. Its regression
reproduces the original failure using the native execution guard and saved wound
reader, checks unsafe observations still prevent movement, and checks ownership
cleanup on exceptions. The updated full suite passed 1,161 examples with native
guards and real GTK enabled.

The separate cold-start eLoot test **did not pass**: initialization consumed much
of the configured 20-send allowance, and the guard interrupted after skinning,
before restoring the skinning tool. The outer operation later stopped the held
run at its deadline. No terminal controller evidence was observed by LAB; a
subsequent snapshot showed the tool still held. Do not interpret owner release
alone as equipment restoration. Resolve cold-start budgeting and bounded tool
restoration, then repeat the supervised loot test before claiming readiness.

Follow-up: bounded one-shot equipment recovery is implemented and covered
offline. The full suite passed 1,170 examples, including original cancelled-guard
preservation, saved-tool restoration, room/owner mismatch refusal, unrelated-item
refusal, stop revalidation, and recovery send/time caps. Recovery is limited to
12 additional sends / 10 seconds and cannot resume loot or combat. A normal pass
also verifies original hand identities and standing before reporting completion.
The deployed live retry held before any command on the profile's encumbrance
check, so live recovery and complete post-fix looting remain **not verified**.
Cold-start setup still consumes the configured work budget; this change makes
budget exhaustion recoverable when authority and safety permit, not an unlimited
first-pass allowance. The outer LAB deadline can still revoke recovery.

### Later cold-start and deadline follow-up (2026-09-09)

Separate loot work limits and fixed supervised work/cleanup deadlines are now
implemented. The external operation deadline is unchanged: work ends twelve
seconds before it, with ten seconds reserved for equipment-only recovery and
two seconds for terminal publication. This reserve does not grant more loot or
combat work, override revocation, or promise that cold initialization will fit.

A supervised retry verified a kill, skinning, tool stow, standing, and search.
The run stopped with `operation_work_deadline`, not successful room completion.
The game acknowledged the search after terminal publication. Fresh observations
confirmed the original weapon held, the other hand empty, survival, and released
owners. This establishes equipment handoff for that attempt, not a completed
cold-start loot operation or confirmation of every sent command.

A previous attempt exposed delayed acknowledgement of a tool-stow command.
The recovery path now journals an attempted stow and waits boundedly for hand
state rather than duplicating an uncertain command. A production eLoot harness
reproduces the duplicate before the repair and covers delayed acknowledgement,
already-observed completion, missing acknowledgement, revocation and movement.
The last live retry did **not** reproduce this exact timing race; live validation
of that race remains unverified. The post-repair offline scripts suite passed
1,187 examples with native integration and real GTK enabled.

Compatibility review subsequently identified in-flight group-loot revocation
and supervised-start ordering issues. Their repairs require offline regression
checks before further live testing. Human assist, configured retreat, bounded
trial and ordinary legacy-mode live checks above remain outstanding. Do not
claim the whole submission checklist has passed.

Unexpected seek failures now retain their phase and exception class/location
without exception messages or full local paths, making callback failures visible
even when the native guard deliberately suppresses exception payloads.

Earlier offline verification: 1,157 Bigshot examples passed with the companion native
execution guards and real GTK tests enabled. LAB's full Python run passed 719
tests; the expanded seek/area subset then passed all 9 tests. The focused Ruby
bridge, registry, controls and inventory suites passed 139 tests / 754 assertions
in separate processes (their fake Lich globals must not be combined).

Use a reviewed low-risk profile area, target policy, and exact-character LAB
registration. Start with loot disabled and intact equipment. Run one
`quick seek --area profile` operation: confirm in-area movement, target discovery,
combat in the arrival room, then terminal cleanup and owner release. Inspect
search sends separately from attributed combat effects. A no-target timeout or
empty clear is not a combat pass. Repeat with eLoot only after the first pass.

Exercise hold/stop during search and confirm no later movement/combat send.
Do not deliberately cross into an unsafe room to test a boundary. Verify rejected
boundary exits and unexpected displacement offline, then observe that every
actual live destination remains in the approved set. A restart is a new approved
operation; it must not silently resume a failed or exhausted search.

## Profile-area follow-up (partially live verified)

Offline validation for the area integration: 1,134 Bigshot examples passed,
including native execution guards and real GTK save/load/layout checks. The
matching LAB development worktree passed 718 Python tests and 132 focused Ruby
tests (789 assertions). These results do not establish a live area pass.

Player-authorized acceptance on 2026-09-10 ICT (2026-09-09 UTC) completed one
no-loot seek outing:
28 rooms outbound, four attributed attacks confirmed as four kills, 28 rooms
back to the configured refuge, original equipment and standing restored, owners
released, full health, and no alerts. A separate ordinary-stop outing returned
safely. This is evidence for those exact runs, not every route or mode; live eLoot,
assist, and trial combinations remain pending.

The earlier field-only test plan is superseded: `quick_area` cannot launch an
agent test. Register `quick_refuge`, review its return reserve and the disposable
profile's starting room/boundaries, and use a fixed `--area profile` launch.
Boundary rooms remain excluded from hunting; refuge transit is separate.

1. Begin at the player-designated refuge with fresh equipment and session proof.
2. Run bounded clear/seek without loot first; verify actual outbound travel,
   exact target evidence, return, original hands, standing and owner release.
3. Repeat with eLoot only after the first pass; verify equipment recovery as
   well as the independent work result and refuge handoff.
4. Exercise ordinary stop in a separately authorized outing; verify work stops
   and bounded return completes. Hold also ends supervised work and returns;
   resume must not restart that returning outing.

Keep boundary-displacement, blocked-return and hard-revocation fault injection
offline rather than leaving a character in danger. Standalone manual Quick's
room-lock and moving watch/assist behavior remains separately covered.

Do not add danger to reproduce cached-status timing races: the offline monitor
test verifies that publication lag denies stale controls without cancelling an
otherwise valid moving watch/assist run.
