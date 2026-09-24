# From colony to living town

## Pre-change audit (September 24, 2026)

The audit inspected resident data, five blocks, interiors, sprites, navigation, and crossings; inventory/coins, three apprenticeships, coffee, energy, and sleep; routines, local conversations and streaming, relationships, privacy, and testimony; lighting, atmosphere, objects, and decorative crops; the Journal, HUD, menu, saves, and Worker contracts. Older documentation contains states that predate the code: code and tests are the reference. No personal save or keys were read or modified.

| Existing system | Assessment | Decision |
| --- | --- | --- |
| Paths and five areas | Physical routes, reciprocal crossings, blockage recovery | Keep; add access authorization and a connected forest |
| Houses and objects | Personal identity, permissions, bed, wardrobe, verifiable projects | Keep; add lots with fixed footprints and restoration states |
| Apprenticeships | Three one-time chains, no renewable income | Keep; unique rewards and access based on mentor presence |
| Inventory/coins | One local authority, validated prices and consumption | Extend the same ledger with materials; do not create a second wallet |
| Routines | Visible work that currently produces no goods | Keep as personal life; layer voluntary productive commitments over it |
| Energy | Player only, coffee +5, sleep and exhaustion | Keep; add NPC work stamina distinct from willingness to converse |
| Relationships/memory | Directed relationships, privacy, testimony, physical encounters | Connect cooperation and work events while respecting witnesses and sources |
| AI | Bounded context and validated proposals | Extend context; prohibit creating costs, resources, or unlocks through text |
| Reactive world | Day/night, wind, water; garden changes only at completion | Keep atmosphere; add planting, tending, maturation, and harvesting |
| Population | Six records and fixed IDs; no staged presence | Stable catalog with separate presence; preserve histories when unlocking |
| Persistence | Atomic writes and backups | Extend schema; existing saves retain streets, neighbors, and achievements |

## Loop and stages

Explore → gather → help → produce → earn → build → open land → welcome residents. Each opening adds actions: the garden enables farming, the workshop transforms materials and enables the bicycle through its existing apprenticeship, Alma's corner adds community projects, and the forest provides another limited source of materials.

A new game starts with the player, Lupita, and Inés, two streets, and a few facilities. César arrives when his home is ready; Mateo returns to the family workshop; Alma returns to her restored home, preserving her history of always having lived in the neighborhood. The remaining neighbors are registered but are not drawn, do not collide, converse, or act before arriving. Previous saves keep their five streets and five neighbors and gain access to new activities without losing progress.

Stages follow completed projects, not experience points. The Journal shows the next objective and its actual requirements. Lots and closed crossings exist physically; projects are paid for once and require work on site. There is no arbitrary placement editor: predefined lots preserve coherent paths and proportions.

## Authority and modules

`Progression.state` remains the only wallet and inventory. New `Settlement` state holds areas, buildings, presence, resource nodes, crops, projects, jobs, explorations, orders, and receipts. Declarative catalogs define prices, requirements, yields, and destinations. A job controller adapts existing movement and routines; it does not replace AStar or conversations.

Layouts remain immutable. Lots and buildings share solid footprints so navigation, drawing, and interaction stay consistent as the settlement grows. Views receive state per save; progress is not stored in global geometry caches. Connections are checked both when requesting a route and when crossing. Visiting a house also checks that it exists and is enabled.

Commitments move through acceptance → travel → work on site → delivery/result. Sleeping, talking, and resting interrupt work; they do not manufacture progress. Initial occupations and interests are declared as work capabilities without pretending an animation is a learned skill. Cooperation depends on preferences, relationships, rest, and responsibilities. An ordinary refusal does not harm friendship; repeated insistence can affect tolerance.

Explorations use existing destinations and outcomes, with deterministic variation by place, day, and explorer. Discoveries do not appear before arrival. NPCs carry their results to the community point when appropriate. Only the actor and nearby witnesses remember an event; later testimony remains information heard from someone else.

## Economy and progress protection

Resources are limited by node and period; sales have daily demand; orders have settlement limits; recipes require materials and work; construction has fixed costs and one-time payment. Repeated clicks, loading, area changes, or late AI responses do not duplicate inputs or rewards. Materials from canceled production return to storage; contributions to construction remain invested in that project.

Economic recovery must be possible without starting coins: gather and deliver/sell renewable materials. A repaired bicycle cannot be sold, and apprenticeship kits cannot be consumed as generic materials. Coffee retains its price and +5 energy. Apprenticeships still require real practice and retain their unique outcomes.

## Implementation and verification order

1. Catalog, state, migration, shared wallet, and presence.
2. Voluntary jobs, production, orders, and physical exploration.
3. Progression gates, lots, forest, construction, and visible crops.
4. Journal and contextual actions, bounded AI context, and collaboration profiles.
5. Full journey from the small starting settlement to all residents, saving at each phase, abuse tests, social regressions, and visual review.

Existing system tests are preserved with an explicit developed-colony fixture mode when the scenario requires it. New tests must use the real smaller starting state; never open everything to hide a progression blocker. Validation uses neither providers nor the user's save.

## Delivered implementation

- `settlement_catalog.gd` loads immutable content; `settlement.gd` validates requirements, reservations, payments, presence, crops, projects, and receipts. Town state is saved within the same atomic save.
- `settlement_jobs.gd` preserves physical commitments and resumes travel/work/return. `resident_catalog.gd` shares identities and preferences without turning narrative occupations into demonstrated learning.
- Colony filters population, authorizes every crossing, and routes only through open areas. Routines targeting future locations adapt to the plaza; conversation scenes preserve the actual commitment.
- `settlement_world.gd` derives lots, objects, sprouts, and barriers per save. It does not change map caches. The grove adds gathering and a non-walkable pond.
- `settlement_ui.gd` integrates growth into the Journal and profiles. It adds no permanent bars. The map distinguishes crossings that are still closed.
- AI context adds only the stage, the character's own commitment, and one eligible collaboration offer. `colaborar` selects an engine-validated offer without economic parameters from the model.

The current version uses fixed lots and the five already authored neighbors. There is no free building placement or automatic character generation. Adding content requires stable IDs and catalog/layout/profile entries; a new save format requires explicit migration and tests without replacing the wallet, relationships, or navigation engine.

New games use `setup(false)`; regression scenarios that need the previous neighborhood explicitly use `setup(false,true)`. `--ui-test --settlement-start` tests the real smaller starting state. Test mode does not enable providers or overwrite a personal save.

## Delivery validation

The progression test completed all five stages, six areas, and six residents including the player without granting free materials or coins. It required 15 days of rest and resource renewal within the simulation. This demonstrates economic reachability; it is not an estimate of human playtime or a replacement for a later balancing session.

| Check | Result |
| --- | --- |
| Existing core (`smoke.gd`) | 141/141 |
| Settlement start, transactions, and migration | 39/39 |
| Complete economic progression | 56/56 |
| Integrity, retries, testimony, and saves | 57/57 |
| NPC commitments and physical travel | 55/55 |
| Real Main, input, and visible work | 17/17; 7,440 movement samples |
| Geometry and world states | 254/254; 14,327 route samples |
| Journal | 77/77 headless; 90/90 with 13 screenshots |
| Backend | 88/88; 2,248 assertions; TypeScript check passed |

Targeted suites also passed for apprenticeships, energy, sleep, daily life, relationships, willingness to talk, area crossings, blockage recovery, collisions, conversation, coffee, menu, and HUD. Logs are in `artifacts/settlement/`; world screenshots are in `artifacts/settlement-world/`. Tests used synthetic saves and disabled providers. Compatibility with previous saves was checked with fixtures without modifying a personal save.

To try the smaller starting state, choose **Nueva partida** (New game) and open **Diario → Pueblo** (Journal → Town). Continuing a previous save preserves its existing neighbors and areas; it does not turn it into an empty settlement. Economic and unlock rules are local and deterministic; these tests do not evaluate response quality from a real AI provider.
