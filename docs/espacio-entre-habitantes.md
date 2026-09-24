# Space between residents

Neighbors can share the café, plaza, workshop, or garden but receive different standing positions. `shared_destinations.gd` chooses walkable positions with 18 pixels of separation, preferring horizontal rows. It considers both people already there and destinations assigned to those on the way. Positions stay within reach of the location's interactions and are chosen when activity changes, not every frame.

The garden has a passage with a single entrance. César has a work position at the back; visitors use outside positions, keeping access clear. Resting positions are not assigned at the passage opening.

`crowd_motion.gd` prevents routes from passing through another resident. Foot spacing uses an ellipse of 16 horizontal and 14 vertical pixels: it leaves space between characters while retaining natural perspective overlap at different depths. Doors and furniture keep their own collisions without inflating them to this social spacing.

Pathfinding and movement now check the entire segment against the same ellipse. This includes the connection from a fractional position to the first grid node and the final connection to the destination. A one-pixel planning margin prevents edges between free nodes from cutting through a neighbor's body. The shared grid is restored after each search.

When a route is blocked, it is recalculated using current positions. After 1.05 seconds of simulation without progress, an eligible character searches for a nearby passing place with at most twelve local queries. They walk there, briefly let the other person pass, and resume the original destination. Recalculating an identical route does not reset the timer; physical progress is required. Each movement is checked in one-pixel segments, including when time is accelerated or the player sleeps. Positions are never corrected by jumping. The manually controlled player, sleeping residents, and conversation participants are not moved out of an NPC's way.

When two neighbors walk in opposite directions, stable priority determines who yields. The pause ends when the other passes or after five seconds of simulation; a cooldown follows before yielding again. This prevents both from rerouting simultaneously and circling furniture. Detours and waits are discarded when room, target, intent, or routine changes, and do not complete tasks at the passing place.

Overlapping positions from older saves are resolved by walking to a nearby free point, with stable priority among neighbors. Rooms are considered separately. Reservations, temporary routes, and search geometry are local; they require no AI requests and add no artificial memories.

Before entering or leaving a house, the arrival point is checked for space. If one person wants to leave and another wants to enter through the same doorway, the departing person has priority: the outside NPC physically steps aside and then returns, preserving the intent to enter. A visit blocked by space retains its original permission and expiration; waiting neither grants nor renews an invitation. A crossing physically blocked by a reserved person continues waiting for real space without passing through them.

The player also respects occupied space when walking with keys or following a route. They can continue toward a free side, and others can walk around them. Approaching a mentor still leaves sufficient distance to converse and deliver items.

## Verification

The artifact paths below refer to historical local evidence excluded from the public repository; they are not downloadable repository files.

- `npc_unstuck_smoke.gd`: **52/52**. Fractional start and end connectors, nineteen door-adjacent blockages, head-on crossing, and simultaneous entry/exit. The measured crossing fell from **24.45 s and 1,277 px** to **7.3 s and 277 px** of combined travel. Preserves targets, spacing, speed, and held participants. Log (`artifacts/npc-unstuck/passing-priority-final.log`).
- `crowd_spacing_smoke.gd`: **56/56**, with **8,819** physical samples. Distribution across five and six residents, convergence, crossings, garden, gradual recovery, keyboard movement, stationary conversations, and blocked doors that clear. Log (`artifacts/npc-unstuck/crowd_spacing_smoke-final.log`).
- After the change, passing suites included core **141/141**, service **80/80**, controls **47/47**, navigation **99/99**, bicycle **27/27**, chat **133/133**, and sleep duration **58/58**. No script errors occurred in these runs.
- Previous permission and doorway checks remain: **21/21**, log `artifacts/crowd-spacing/portals.log`.
- Screenshots reviewed after walking to destinations: café (`artifacts/npc-separation/cafe-arrived.png`) and plaza (`artifacts/npc-separation/plaza-arrived.png`). All five arrived with a minimum final separation of 18 pixels, without jumps, and with every position walkable.
- Earlier simulation of two complete days: **57,600** NPC samples without overlaps, illegal steps, or blockages lasting more than one game hour. Every neighbor completed two cycles of entering, sleeping, waking, and leaving; the player remained still. The longest wait without progress outside the destination was five game minutes. Metrics: `artifacts/npc-separation/two-days.json`.

Tests and screenshots use isolated data without loading or saving the user's progress or querying providers.
