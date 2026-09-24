# Interactive MVP environment

The environment uses the colony's clock and save. It does not query AI or create another economy: plots belong to `Settlement`, household objects reuse their public stories, actions resolve after physical arrival, and changes are presented with existing native sprites and five new pieces.

## Review of existing systems

The six connected areas, routines and travel, visit permissions, social memory, inventory, farming tasks, materials and rewards, collisions, compact house reader, and time-based lighting were preserved. The bed, wardrobe, learning stations, café, seats, shop, and construction projects retain their previous actions.

The two garden plots allow footsteps; their borders and fences remain solid. Raised planters remain furniture, not paths. Windows, plants, photographs, notebooks, bookshelves, and projects support household actions. Trees, pots, streetlights, banners, and water offer small contextual details where appropriate. Walls, fences, and every floor tile do not receive artificial buttons.

## Discovering interactions

- Hover over and click a highlighted object to approach it. **E** works beside usable objects; the nearest existing action retains priority over decoration.
- Walk across a planted plot. One pass does not destroy the plant; repeatedly entering the same cell leaves signs.
- In a house, select a plant to water it or a window to open or close its curtains. The window changes visually and stops casting its own daylight beam when closed.
- Open photographs or memories on display. Each house has two or three pages; arrow keys change pages when the album has focus. Tab and Enter navigate controls, and Escape closes the reader. Alma has three small scenes composed from game sprites.
- Inspect personal projects. The owner's current activity appears only if they are present, nearby, and visible. Inspecting furniture reveals no secrets or private memories.
- Walk over a fallen apple or select it to pick it up. It is consumed there; it does not become a sellable resource.

## Footsteps and regrowth

Each plot is divided into eight cells. Physical entries count whether made with the keyboard or a click route; standing still adds no footsteps. A two-pixel margin prevents jitter at an edge from counting as multiple entries. Area changes, loading, and position jumps are not footsteps.

Within a **30-minute game-time** window—about **24 real seconds at 1×**—the third entry bends the plant and the fifth removes it. Only that cell changes. Soil is drawn behind characters, and leaves are individually depth-sorted.

| Time since damage | Visible state | Real time at 1× |
| --- | --- | --- |
| 0–44 minutes | Empty soil | From damage |
| 45–119 minutes | Sprout | From 36 seconds |
| 120–359 minutes | Small plant | From 1 min 36 s |
| 360 minutes | Full recovery | 4 min 48 s |

Recovery respects the original planting and its tending requirements. Existing harvesting counts only recovered mature plants: its yield is the integer part of `normal yield × available plants / 8`. If no yield remains, the player must wait for regrowth. Neither damage nor watering provides extra materials. New planting clears damage only on that plot.

## Growing trees

Three suitable sites in the homes area and grove begin growing when their area opens. Existing mature trees remain.

| Game-time age | Stage | Real time at 1× |
| --- | --- | --- |
| 0 | Seed below the soil | Start |
| 45 minutes | Sprout | 36 seconds |
| 180 minutes | Small tree | 2 min 24 s |
| 720 minutes | Young tree | 9 min 36 s |
| 1,440 minutes | Medium canopy | 19 min 12 s |
| 2,880 minutes | Fully grown tree | 38 min 24 s |

Each stage has its own native canvas and the same root; sprites are not stretched. The trunk becomes solid at the young stage. If someone occupies the root during growth, collision activation waits until they leave: no one is displaced or trapped. This MVP has no tree cutting or stump system.

## Fruit and small discoveries

There are three eligible fruit trees, one each in the homes, garden, and grove areas. Each tree in an open area gets **one roll per game day**: 12% for a normal apple and 1 in 100,000 for a golden apple. A golden apple can appear at most once per save. These probabilities are local rules, not AI decisions.

The save's seed, tree, and day determine the result. Changing area, inspecting, saving, or loading does not reroll it. Results do not accumulate for skipped days. Uncollected fruit expires at the end of that day; returning to the tree does not extend its lifetime.

A normal apple restores **one percentage point of energy**, capped at 100. A golden apple restores full energy. Picking up the same fruit twice grants nothing; it generates no tradable items or coins. The fountain also has a narrated visual detail on some nights, without an economic reward.

## Homes and memory

The last watering time is saved per plant. For three game hours, watering again explains that the soil is still damp; there is no cost or reward to exploit. The moisture and droplet visual response is brief. Each curtain saves its own state.

Albums reuse information already publicly displayed in the house. The page actually read is recorded; opening an album does not teach every page, and rereading does not duplicate memories. Neighbors' wardrobes can be viewed from outside; their private drawers do not open. The compact camera and reader still keep the player visible.

## Shared state and compatibility

- `EnvironmentalCatalog`: geometry, sites, and stages; cached catalogs.
- `EnvironmentState`: seed, footsteps, growth dates, fruit, and household changes. `view()` is a pure, cached read.
- `EnvironmentInteractions`: physical destinations and actions using the object selector.
- `EnvironmentArt`: visual projection without modifying simulation.
- `HomeDetails` and `HomeUI`: public content and reading navigation.

`Colony` advances the environment with its own clock and saves it in the optional `environment` block. Older saves initialize it without losing progress. Validation rejects impossible states before loading. Leaving an area does not reset plants or windows; closing the game does not calculate offline growth. Pausing stops the clock. Sleeping and speed changes use the same simulated time and therefore also advance growth.

## Art and verification

Five new PNGs: small tree, young tree, apple, golden apple, and closed window. They were produced with the official imagegen CLI and the project's verified exact model; prompts, source, and reproducible import are documented in [environment-art.md](environment-art.md). The palette, scale, and 54 previous environmental sprites remain.

Targeted tests: state **91/91**, real world **20/20**, home UI **59/59**, art **40/40** headless and **42/42** rendered. Home rendering verified **68/68** checks and seven screenshots, including the immediate disappearance of each beam when curtains close without advancing simulation. Also passing: core **141/141**, progression **56/56**, integrity **57/57**, interiors **105/105**, interactions **156/156**, navigation **100/100**, visible jobs **17/17** with 7,440 actor samples, and service **94/94**, plus type checking. Tests use isolated saves and do not call providers.

Screenshots and logs: `artifacts/environment-mvp/`, `artifacts/environment-growth/`, and `artifacts/home-details/`.
