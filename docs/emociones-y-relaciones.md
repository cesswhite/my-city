# Emotions and relationships

Each resident stores their own relationship with each of the other five characters. César's trust in Lupita can differ from Lupita's trust in César. **Historia → Su relación contigo** (History → Their relationship with you) shows four values from 0 to 100 and a short mood description. Personality determines the starting point.

| Metric | Effect |
| --- | --- |
| Trust | How much of their history they are willing to share |
| Affection | The closeness they have built with that person |
| Tolerance | How much conversation they can sustain before needing a break |
| Frustration | Irritation accumulated through pressure or mistreatment |

Affection can represent fondness or friendship. There is no separate romance mechanic yet.

## Conversation and boundaries

A neighbor may not feel like talking even to a good friend. On a new invitation, willingness is decided locally: the base probability of wanting solitude is 18%, increased by a reserved personality or ongoing task and reduced by sociability. A poor relationship is not required for a refusal.

The refusal is short and polite, for example **Ahora prefiero un rato a solas. Luego hablamos.** (I would rather have some time alone now. We can talk later.) It lasts 45 game minutes, persists in saves, and also applies to automatic encounters. Each partner receives a first warning without losing trust, affection, or tolerance. Inspecting the profile or closing chat does not count as insistence. The NPC continues their route and life without being reserved or calling a provider.

Another invitation during this period receives **Te pedí un rato. Por favor, no insistas.** (I asked for a moment. Please do not insist.) Insistence adds 8 frustration, removes 6 tolerance, and maintains a personal cooldown of at least 30 minutes. This applies at most once per game minute to prevent duplicate UI events from multiplying the effect. Further insistence produces a firmer tone. After the break, a 60-minute window prevents another random refusal, provided no other frustration or fatigue limit applies. An accepted conversation does not reroll willingness with every reply.

Distinct completed conversations can increase trust and affection. Greetings, repeated thanks, and opening/closing the panel award no points. Each pair can gain at most twice per day, at least three game hours apart, so relationships grow through spaced encounters. Each gain grants four trust and three affection.

Ordinary conversation consumes some tolerance. A second identical consecutive question receives a warning; the third ends the conversation. Personality also sets duration and consecutive-question limits: eight to twelve exchanges or five to seven consecutive questions. These limits do not depend on connection speed. Incomplete, cancelled, or failed messages do not change the relationship.

Asking about a private topic before earning trust receives a short refusal with no first-question penalty. Continuing after that lowers tolerance and trust and increases frustration. Recognized insults cause immediate closure. Local rules use specific expressions, not an exhaustive natural-language classifier.

When fatigue or pressure ends the conversation, the neighbor leaves a final line, is released from chat, and walks toward their next destination or a free space. The interface offers **Cerrar** (Close), without questions forcing them to continue. Attempting contact during the break shows a short refusal without stopping them or querying a provider. Insistence in different minutes extends the irritation. A polite player farewell ends the conversation without harassment penalties.

Tolerance recovers and frustration declines over game time; resting at home or sleeping speeds recovery. Time alone grants no trust or affection. Cooldowns also apply to visits: a remote decision cannot force an irritated neighbor to admit the player.

## Discovering personal history

| Closeness | Available information |
| --- | --- |
| Public | Occupation and a general description, without family history or private goals |
| Personal | Trust at least 45 and frustration below 40; some background |
| Intimate | Trust at least 70, affection at least 50, and frustration below 25; full biography |

The profile and dialogue context use the same level. Relationship changes refresh the profile and remove information no longer permitted. The neighbor's **Memoria** (Memory) tab shows experiences shared with the player. Experiences already disclosed remain genuine memories. The character retains their complete identity when making decisions about their own life.

Models receive relationship state and a filtered biography. They should answer briefly without emotional scores, dates, or implementation details. Models neither assign points nor control chat reservations; the game applies changes after a complete exchange is confirmed.

## Encounters between neighbors

Two awake residents passing near each other on the street may stop to greet one another. The engine checks for walls or obstacles between them. One speaks for about two seconds, the other replies, and both resume their routes. Only one greeting of this kind runs at a time.

Their first daily encounter uses **Buenos días**, **Buenas tardes**, or **Buenas noches**, based on game time. Later encounters can use **Hola de nuevo**, then **Nos volvemos a encontrar** and **¿Qué tal va el día?** They must separate before greeting again, and at least one game hour must pass between the pair's greetings. Remaining together does not create a dialogue loop. Angry relationships respect their cooldown.

Both completed lines count as a shared encounter; an interrupted greeting invents no conversation. A normal chat also counts when its first exchange is confirmed, without recounting every later message. The next greeting therefore recognizes that they have met. Greetings grant no trust. They run locally without AI calls, including for the player in **Vivir solo** (autonomous living). Taking control cancels the player's pending greeting.

## Persistence and verification

The thirty directed relationships, metrics, cooldowns, and encounter counts persist in the save. Older saves receive personality-based starting values and slight familiarity from conversation days already present in their memories. No encounters or romances are fabricated. Closed-application time does not advance the simulation.

Temporary willingness is stored separately from relationships in each resident's `chat_availability`: expiry, refusal, warned partners, and phrase variant. Older saves without it load with willingness yet to be decided. Validation rejects invalid values without overwriting the previous file. Availability queries do not roll randomness or change metrics.

Implementation: `social_relationships.gd` computes state and permissions; `social_encounters.gd` directs physical greetings; `player_chat.gd` applies limits and withdrawal; `relationship_ui.gd` presents metrics. The Worker contract is in [backend relationships](../backend/docs/relationships.md).

Isolated tests, without personal saves or providers:

- `social_relationships_smoke.gd`: directionality, changes, limits, privacy, greetings, visits, migration, and persistence.
- `chat_willingness_smoke.gd`: temporary refusal, respect, insistence, NPC availability, expiry, persistence, and migration.
- `social_world_smoke.gd -- --ui-test`: actual chat flow, farewell, walking away, recontact, greetings, and interruption.
- `relationship_ui_smoke.gd -- --ui-test`: bars, dynamic privacy, and send limits.
- `player_chat_smoke.gd -- --ui-test`: mocked transport, retries, and cancellation without emotional changes.
- Worker tests: contract validation, context, and suggestions respecting a farewell.
