# Information and social life in the town

## Pre-change audit

The game already preserves directed relationships, conversation boundaries, testimony with its speaker, and individual memories. Encounters are physical and incomplete conversations are not saved. Decisions and dialogue use bounded context and non-blocking transport. Town growth also creates memories only for actors and nearby witnesses.

Missing pieces include stable information identity, transmission chains, recipient-specific confidentiality, discrepancies between versions, and consequences of indiscretion. Old memories and `known_people.last_topic` can reintroduce private text into context even when the biography is filtered. Greetings, local dialogue, and remote dialogue need the same social rules.

## Adaptation

- Preserve existing episodic memories and relationships. Add a bounded knowledge registry with provenance and individual belief, separate from world facts.
- Distinguish direct experience, testimony, opinion, and secrets. Confidence in a claim is not its truth. A distorted version retains provenance and does not rewrite the original fact.
- Share only during a real, completed encounter. Preparing a response, showing a suggestion, receiving fragments, or canceling does not transmit information.
- Apply privacy to every context path: topics, relevant memories, recent exchanges, and known-person summaries. Never send characters the hidden global route so they can guess who is responsible.
- Recognize indiscretions through information the affected person actually hears. Their suspects come from their own confidences; a player's accusation remains testimony and may be disputed.
- Resolve admissions, denials, evasion, topic changes, and confrontations through local rules. Models phrase dialogue within that context; they cannot invent evidence or modify relationships or the economy.
- Seed a few explicit backstories consistent with the five existing neighbors. The player does not know them initially. New residents retain staged presence.

## Verification criteria

Check the chain confidence → disclosure → suspicion → response → later encounter; confidentiality in all outgoing fields; separate versions and sources; refusals without omniscience; absence, sleep, walls, and distance; cancellation and retries; persistence and migration. Run the core and backend alongside new isolated social tests. Do not use personal saves or real providers for these tests.

## Implemented system

`social_knowledge.gd` is the authority for social knowledge. Each topic has an origin, subjects, kind, and privacy; each person retains their own version, immediate source, certainty, confidence, and evidence. The technical chain remains in the save and is not given to the character as knowledge. Version differences reduce certainty instead of automatically deciding who is right.

`social_dialogue.gd` prepares utterances without mutating the world. It recognizes known topics, questions about third parties, and responses to suspicion. A question such as “¿Fue Inés?” (“Was it Inés?”) does not accuse Inés. A “sí” (“yes”) confirms a source only if the previous question named one. Admission, denial, evasion, topic change, and apology are processed after a complete exchange. If a case has already been addressed, the character does not rediscover the same indiscretion as new.

`social_encounters.gd` shows occasional exchanges between nearby neighbors. This controller, local dialogue, and connected dialogue use the same authority. Canceling, changing area, sleeping, or moving apart does not transmit the topic. Confrontation waits for a real encounter; it does not teleport anyone or invent an offscreen conversation. The accused consults what they personally shared, while the affected person distinguishes a received accusation from an admission.

`social_dynamics.gd` adds personal impressions after physical events. Proximity, friction, and help can produce opinions about friendship, distance, or collaboration. Feeling excluded requires a nearby, awake witness with unobstructed sight, strong friendship, and low tolerance; the effect is small and limited per day. Interest in another person is unilateral and explicitly uncertain, based on authored personal context, not an automatic inference from affection or a reciprocal romantic relationship.

The `social_content.json` catalog seeds eight personal topics. For example, only Lupita and Mateo know one specific historical confidence from Lupita. Typing a question does not grant access: sharing depends on trust, willingness, and privacy. An admitted indiscretion affects only the corresponding directed relationship and limits new confidences for three days. Existing knowledge is not erased.

Witnessed work, help, and exploration events feed the same registry. New testimony that the player explicitly presents as something heard or told in confidence is retained as an unverified literal statement. It does not change buildings, coins, tasks, or world facts. Rumors may vary through authored, bounded content versions; the model does not create evidence, people, or new rules.

## Persistence, performance, and scope

Saves add an optional `social_knowledge` block. Earlier saves retain memories, population, economy, and relationships. Old transcripts are not retroactively converted into verified facts. Loading validates types, IDs, permissions, sizes, sources, and times; the temporary-file and backup mechanism remains intact.

The registry has explicit limits for topics, knowledge, versions, cases, and receipts. Old public information may leave working memory to make room for new events; protected confidences are not deleted to free space. Existing episodic memories still preserve history. Social context occupies at most 2,400 characters within the previous 12,000-character total limit; no per-frame calls or extra AI request per sentence are added.

Connected conversation can phrase responses naturally within allowed context. Mechanical recognition uses known topics, distinctive details, names, and conversation references; it is not a universal semantic extractor for arbitrary free text. The local variant provides brief predefined responses with the same evidence and privacy controls.

## Trying it

You do not need to start a new save. Talk to neighbors, improve relationships, and ask about someone they know. If someone shares a detail, you can bring it up with the person involved and answer their questions with buttons or free text. Trust does not guarantee disclosure, and gossip does not appear in every encounter.

Isolated tests are in `social_knowledge_smoke.gd`, `social_story_smoke.gd`, `social_chat_smoke.gd`, `social_encounters_gossip_smoke.gd`, and `social_dynamics_smoke.gd`. Run them with Godot `--headless --path game --script tests/<file> -- --ui-test`. The backend adds contract tests and an integration that consumes real Godot context with simulated transport. Delivery logs are in `artifacts/social-system/`, `artifacts/social-knowledge/`, and `artifacts/social-gossip/`.

## Final results

| Test | Result |
| --- | --- |
| Knowledge, sources, versions, privacy, saturation, and persistence | 75/75 |
| Complete story, ambiguous responses, confrontations, and boundaries | 120/120 |
| Main chat, fragments, errors, retries, and new testimony | 24/24 |
| Encounters, turn order, cancellation, and geometry | 100/100 |
| Directed impressions, collaboration, inclusion, and daily limits | 33/33 |
| Existing core | 141/141 |
| Backend | 94/94; 2,691 assertions; TypeScript passed |
| Real Godot context → backend JSON/SSE/Jev | 12/12 routes; four contexts |

Player conversation (151), relationships (78), previous encounters (36), willingness to talk (55), activity context (13), town integrity (57), jobs (55), full growth progression (56), routines (45), area crossings (94), sleep (30), energy (51), and apprenticeships (134) also passed. These are deterministic tests with simulated transport, not an evaluation of real provider responses.

The historical core test placed the player inside a café table footprint. Its position was corrected to walkable ground to validate in-person conversation with the new obstacle check, preserving all 141 assertions.
