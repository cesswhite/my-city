# The vision for Mi Colonia

An everyday neighborhood where each person has a history, interprets events, and keeps what they learn. The player participates in relationships and projects that turn a small settlement into a livable town. Conversations should retain their intimate scale as the world grows.

## Current experience

The loop is to explore, gather, help, produce, earn coins, build, and open new possibilities. A new game begins with two neighbors, two accessible areas, and eight coins. Improvements restore homes and bring in other catalog residents; existing saves retain their development.

Neighbors have routines, interests, energy, and their own willingness. They can cooperate, physically travel between areas, talk to each other, share information, keep secrets, and react to player insistence. Knowing a story requires experiencing or hearing it; a claim does not become fact because a model says it.

Vegetation, household objects, and lighting participate in the simulation: persistent growth, plants damaged by footsteps, curtains, albums, occasional fruit, seating, and coffee. Concrete rules live in catalogs and modules rather than improvised model instructions.

## Residents

| Resident | Personal context | Place in the town |
| --- | --- | --- |
| César | Grew up in the countryside with his father and cares for plants. | Garden, cultivation, and outdoor life. |
| Lupita | Enjoys bringing people together and growing herbs. | Neighborly life and gatherings. |
| Mateo | Learned bicycle repair from his grandparents. | Workshop and passing on his trade. |
| Inés | Lived in different cities before opening the café. | Coffee, tea, and conversation. |
| Alma | Records the neighborhood's changes and stories. | Painting, memories, and gardening. |

The player is another resident. The current catalog is `game/data/residents.json`; editing it does not automatically replace saved identities. Biographies guide personalities without turning neighbors into interchangeable workers.

## Visual direction

The game uses PNG sprites, an oblique overhead perspective, readable façades, upper-left lighting, and a logical resolution of 768 × 432. The revised buildings, vegetation, furniture, and terrain share scale, palette, and anchors. The [pixel-art design system](pixel-art-design-system.md) is the current reference; do not mix perspectives or regenerate pieces without comparing nearby assets.

## Memory, learning, and authority

Each character distinguishes identity, personal experiences, relationships, and learned knowledge. Learning means retaining instructions and demonstrating their execution; it does not train model weights or replace knowledge with experience points.

Godot controls positions, feasible actions, costs, rewards, and persistence. Jev proposes structured choices among allowed actions; OpenAI writes dialogue from filtered context. The Worker keeps credentials outside the client. Live connections have been checked during development, but ordinary tests use mocks and do not guarantee access or latency for another account.

## Limits and evolution

The save is local and single-player, with no progress while the application is closed. There is no remote synchronization, multiplayer, or deployed public service. Catalogs support additional residents, buildings, jobs, and areas without replacing the architecture. In-game biography editing and remote memory remain potential extensions, not existing features.

Before expanding content, preserve save compatibility, navigation, clear objectives, and social privacy. Success remains observable: after talking, learning, saving, and returning, a resident recognizes the other person, remembers only what they could know, and applies their learning in a coherent persistent world.

See the [gameplay guide](gameplay.md) and [architecture](architecture.md) for detailed scope.
