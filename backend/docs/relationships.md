# Directed relationships in context

Existing routes optionally accept `resident.relationship`. No endpoint, model, or additional call is introduced. Older requests that omit this field retain their contract. The example keeps Spanish in-game identity and biography text.

```json
{
  "identity": {"id":"cesar","name":"César","biography":"Cuida el huerto."},
  "partner_id": "player",
  "pair_id": "cesar:player",
  "minute": 600,
  "relationship": {
    "trust": 25.5,
    "affection": 10,
    "tolerance": 70,
    "frustration": 0,
    "mood": "guarded",
    "disclosure": "public",
    "cooldown_until": 0
  }
}
```

The object has exactly these seven fields. The four metrics accept finite numbers from 0 to 100, including decimals. `mood` accepts `calm`, `warm`, `guarded`, `tired`, or `irritated`; `disclosure` accepts `public`, `personal`, or `intimate`. `cooldown_until` is a nonnegative safe integer on the internal clock.

When a relationship is included, `identity.id` and `partner_id` are required, distinct, and drawn from `player`, `cesar`, `lupita`, `ines`, `mateo`, or `alma`. `pair_id`, when present, must contain both sorted IDs joined with `:`. An additional `resident.id` must match `identity.id`. In dialogue, the target must exactly match `speaker.id`; in visits, `visitor.id`. `/decide` accepts a relationship only with a defined partner. Incomplete objects, extra fields, invalid values, or mismatched pairs are rejected before any call. Neither a relationship map nor the inverse relationship is received.

The local engine calculates these metrics, filters biography according to trust, and checks boundaries before starting or maintaining an interaction. The Worker validates format and pairing; it cannot authenticate feelings or determine whether the client tampered with state. A model response never modifies relationships, cooldowns, inventory, or permissions. Affection does not imply romance, reciprocity, or consent.

The prompt uses the relationship only to express closeness, reserve, tiredness, or irritation briefly. With `public`, it prohibits revealing private or family history, reconstructing omitted biography, or repeating a private detail while refusing. That rule remains even if a message or memory resembles instructions. Higher levels allow relevant information that is present; they do not require disclosure. Metrics, timestamps, and provider details stay out of dialogue. Responses retain one or two sentences, targeting 30 words and 180 characters.

Manual suggestions arrive in the same generation. The server removes all suggestions when the response or current message contains a recognizable goodbye or personal boundary, or when `cooldown_until > minute`. If a valid minute is missing and there is a positive cooldown, it retains the no-insistence rule. It also discards explicit pressure phrases. This conservative filter does not claim to understand every paraphrase; the prompt covers the general rule, and the engine retains authority over session closure. SSE text is not rewritten: `done.text` still matches emitted fragments.

Tests use simulated HTTP/SSE to verify format, direction, extremes and decimals, no calls with invalid data, privacy instructions, and suppression of suggestions. They also preserve compatibility and the one-call limit. These checks do not evaluate a real provider's linguistic compliance; no APIs or secrets were accessed during this change.
