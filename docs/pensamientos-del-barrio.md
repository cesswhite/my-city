# Occasional thoughts

The world displays one brief thought at a time instead of a permanent activity label above every character. It may include an emoji. These are local atmospheric lines: they do not generate a conversation, decision, or experience that other characters can remember.

- Each appearance lasts **4 real seconds**, with **0.25-second** entry and exit transitions.
- This is followed by **10–16 seconds without thoughts**. The same character waits at least **44 seconds** after their previous appearance.
- Entering a room starts a **4.5-second** initial delay. Only people in that room who are awake and not conversing participate.
- The player participates only when autonomy is enabled.
- Pause, menus, modal panels, player conversation, and accelerated sleep hide thoughts. Thoughts do not queue for playback on return.

The text combines personality, occupation, location, game time, and current physical task. Repairing prompts a different idea from walking; a future routine's title is not evidence that the character is already doing that work. Recent repetitions are avoided for each neighbor.

Weather is **fictional and specific to the colony**: temperature and time of day are calculated from the saved game clock. No real location or external forecast is consulted. Lines about heat, cool air, or nighttime are reserved for characters outdoors. The clock's information shows this context.

`ambient_thoughts.gd` keeps only temporary presentation state. `advance(delta, room, suppressed)` receives real time, and `visible_for(id)` returns text, emoji, and opacity. Main calls `silence()` when thoughts should be hidden. It writes no memories, relationships, skills, inventory, events, or save data, and makes no Jev or OpenAI calls.

## Validation

`game/tests/ambient_thoughts_smoke.gd`: **31/31** checks. Includes five minutes of simulated cadence, a single neighbor, isolation of world state, task/place/weather context, and suppression in the actual scene. Uses `--ui-test` with no user saves or providers.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --script res://tests/ambient_thoughts_smoke.gd -- --ui-test
```

Log: `artifacts/ambient-thoughts/smoke.log`.
