# Supervised Quick refuge outings

This opt-in LAB integration does not change standalone Quick, bare `quick`, normal Bigshot hunting, or normal eLoot.

A player configures an explicit refuge room and a reviewed Bigshot profile area. The refuge may be close to the hunt: no town-name or universally safe-room inference is made. An outing must begin at that room, standing, with native hand IDs observed, alive, and without the configured environmental/hostile danger. It walks to the profile start, runs the chosen Quick mode, restores any interrupted eLoot equipment, and walks back before reporting terminal handoff.

## Admission and authority

The private launch wire requires both `--supervised-start-v1 WORK,CLEANUP` and `--supervised-refuge-v1 ROOM,RETURN`. These are absolute monotonic deadlines, not persisted character settings or authority grants. WORK is strictly before CLEANUP; CLEANUP is before RETURN with a 10–120 second return reserve. Startup publishes the exact runtime but sends nothing until the original supervisor activates it. `REFUGE_START_PROTOCOL = 1` declares this integration for the trusted local-source compatibility check.

Outbound and directed return reachability are checked with Lich's existing map graph before activation. The refuge and intermediate travel rooms need not belong to the hunting area. Travel delegates to Bigshot's existing `go2` helper with an exact owned child; it does not call the full `rest` routine or implement another pathfinder. Hunting boundaries continue to govern seeking, combat and looting, not transit.

Each travel phase has a fixed absolute deadline and at most 256 guarded native sends. The child has its own execution guard installed before startup (`Script::START_EXECUTION_GUARD_PROTOCOL = 1`); a parent's guard alone is insufficient. Both route admission and the child opt into `allow_script_starts: false` (`Script::SCRIPT_START_RESTRICTION_PROTOCOL = 1`), rejecting native recursive/detached launches before startup. One-trip go2 options disable typeahead, dead-player stops, bank withdrawals and room-display changes without saving new settings. `--preserve-scripts` leaves roomnumbers/textsubs running instead of temporarily stopping/restarting them. The send policy permits ordinary movement and stand/unhide/open/close helpers, not spending, inventory handling or spellcasting. Unrecognized travel helpers fail visibly rather than silently receiving extra authority.

This uses trusted go2 and map code, including ordinary routing cost evaluation; it is not a sandbox for arbitrary Ruby callbacks or direct socket access. Routes requiring recursive go2, other scripts, or unsupported helpers are refused, not silently expanded. Review the intended routes and go2 configuration before approving a test. A map route is not a guarantee against hazards or changes in the world. Cancellation stops the exact owned child; successful child exit is insufficient without a fresh same-session observation of the requested destination. Normal Bigshot/go2 calls retain their existing behavior.

## Stop and handoff

Ordinary stop, hold, failed work, or a work deadline ends combat and proceeds to bounded equipment recovery and return while the original authority remains valid. Resume does not restart an outing that is already returning. Actions-off, revoked authority, session/owner replacement, native cancellation, and the hard deadline authorize no further sends—even if that prevents returning. No guard is reset to rescue a revoked run.

Recovery calls only eLoot's existing exact-owner equipment-restoration API. It does not start another loot pass, run a sell/rest trip, choose a replacement weapon, or infer an item's properties. Success requires the original hand IDs and standing, checked again during and after return. Unconfirmed equipment prevents return travel and reports an incomplete handoff.

The runtime remains nonterminal through outbound, working, recovering, and returning phases. `work_result` retains the original combat result separately. Final `refuge` contains `room_id`, `phase`, `returned`, and `equipment_restored`. Reaching refuge does not turn failed/stopped work into a passed test. LAB must independently verify fresh refuge state and exact-owner release, and block another automated outing after an unresolved failed handoff.

Synthetic production-class and native-guard regressions cover these contracts. They are not a claim that all modes have been live-tested.
