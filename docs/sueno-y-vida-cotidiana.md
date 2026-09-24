# Sleep and daily life

## Sleeping and waking

At home, click the bed or press **E** beside it. The character walks to the bedside before opening the options: eight hours, a one-hour nap, or until 7:00. The last option is enabled when no more than fifteen hours remain. Choosing a duration does not grant energy: sleeping restores **0.25 points per simulated minute**, capped at 100.

Sleep advances at **60 game minutes per real second**: a one-hour nap takes one second, and eight hours take eight seconds. The panel shows the remaining seconds. All elapsed real time is consumed even during slow frames, dividing progress into the simulation's same five-minute ticks and physical routes. Acceleration stops on waking without carrying accelerated time into walking. Each rest starts with its own accumulator, without inheriting a fraction from the previous clock.

Neighbors continue working, talking locally, and sleeping according to their schedules. Pending requests are canceled, and no new Jev/OpenAI requests are started during this acceleration. Waking restores the session's normal speed; starting sleep from the panel begins at 1×.

"Despertar" (wake), **E**, or starting to walk interrupts bed sleep; rest ends automatically at its deadline. **Space** also pauses sleep, and **Esc** opens the menu without waking. Saves retain sleep start and end; closing the application simulates no additional time. Voluntary rest requires your own bed, and sleeping people do not accept conversations or visits. Older saves without a `sleep` field remain valid.

## Falling asleep from exhaustion

At **0% energy**, the player falls asleep wherever they are, outdoors or indoors. They appear lying down with closed eyes and a small **Zzz**, using their current sprites. A compact indicator shows "Sin energía" (no energy) and remaining seconds, without a wake button.

The wait lasts **8 real seconds**, whether the session was at 1× or 4×. The town continues at normal speed. It does not advance an entire night or apply bed recovery: energy stays at zero until the wait ends, then changes to exactly **5%**. On waking, manual walking is available again. Conversations, cycling, and pending routes are canceled so they do not resume unexpectedly.

Pause and the menu stop the timer. Saving preserves the remaining seconds, and closing the application does not count as rest. Exhaustion sleep cannot be interrupted by WASD, E, autonomy, objects, or the normal rest wake button.

## A neighbor's day

Each schedule block contains tasks lasting **10 to 25 simulated minutes** and ten-minute social breaks. César waters and checks soil; Mateo inspects repairs and organizes tools; Inés serves customers and arranges cups; Alma draws; Lupita prepares gatherings. They alternate accessible points at the location and try to keep destinations ten pixels apart. Routes respect existing obstacles. Gestures express the task without automatically producing materials, completing errands, or granting knowledge.

Spontaneous conversations require two awake, nearby, stationary, available people. Each participant has at least sixty simulated minutes between autonomous encounters. Local exchanges use predetermined lines about the environment or character history, are identified as local, and only participants save the memory. With AI enabled, the existing Jev/OpenAI transport is retained: one background dialogue at a time, with priority for a player-initiated conversation.

A conversation reserves both participants; afterward, they resume their routes. Jev-selected actions have temporary priority, then the schedule resumes. At night, each neighbor enters their home, walks to bed, sleeps, and leaves for the next activity. Daily life uses bounded temporary state per resident; it does not add a memory for every task or frame.

## Visual presentation

`game/scripts/activity_visuals.gd` represents the state returned by `colony.daily_state(id)`. Rendering does not decide activities, change positions, or create experiences or learning.

- **Sleeping:** appears only when state confirms `sleeping` and the person is in their own home. The character's head and hair are reused on the pillow, with the original quilt in front. The hat is hidden only during rendering. The physical bedside position is retained; visual depth and anchor are placed at the bed. No permanent label is added.
- **Exhaustion:** `sleeping` with `action: exhaustion` uses the body lying at its physical position, including inside the person's home. It is not replaced by a nearby-bed rendering and does not modify saved appearance.
- **Working:** feet stay still. Small arm and shirt movements come from existing frames, separated from the legs. The recommended cadence is one frame every 450 ms. This is an activity gesture, not an occupation-specific animation.
- **Drinking:** the existing 8 × 10-pixel cup moves three pixels toward the face during the gesture. No bitmap is generated or modified.
- **Conversing:** the actual reservation keeps participants in their encounter. Ambient thoughts are hidden while they talk.
- **Thoughts:** a single `Name: thought` line uses 16-pixel Pixel Operator and a faint borderless background. One appears at a time for four seconds, with an optional emoji and pauses between appearances. It replaces permanent action labels. Free space is sought, and the line is omitted if it does not fit. See [ambient thoughts](pensamientos-del-barrio.md).

All art used already exists in the project's atlas. This change generates no new images and attributes no new poses to the image model. Regions retain native scale and nearest-neighbor filtering. No fictional progress bar is shown: durations and progress belong to the simulation.

Integration: sort with `sort_y`, draw `draw_sleeping` before the usual actor, use `draw_active` for stationary activities, and position thoughts with `visual_anchor`/`draw_thought`. The controller hides thoughts on pause and retains normal routing while a person walks.
