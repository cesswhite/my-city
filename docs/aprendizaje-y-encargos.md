# Learning, inventory, and errands

Character learning is represented by retained instructions and actions the character can successfully perform. Dialogue can explain a procedure, recall an experience, or propose the next step. The engine changes the world: talking does not deliver an object, create coins, or complete an errand.

## What knowing something means

| Record | What it demonstrates | What it does not demonstrate |
| --- | --- | --- |
| Conversation memory | The character heard or said something in a particular encounter | That the content is true or that they can perform it |
| Procedure with `instrucciones` | They retain the steps and their provenance | That they have practiced successfully |
| Procedure with `practicando` | They are performing the procedure and have verified steps | That every step is complete |
| Procedure with `demostrada` and `world_verified: true` | The engine confirmed the required execution | Mastery of other procedures or unrecorded rewards |

A statement such as “I already repaired the bicycle” remains testimony. It does not replace valid execution. Confidence returned by Jev describes its decision; it is neither evidence of a skill nor permission to change inventory.

## An errand's lifecycle

1. The mentor presents a need; the player accepts through a game interaction.
2. The player buys the requested material; the engine deducts coins and adds it to inventory.
3. The player delivers the material wherever they find the mentor. The engine verifies proximity and the same room, consumes the material, and records delivery exactly once. It does not require being at the workshop, garden, or café, or waiting for a particular time.
4. Delivery enables receipt of instructions and a practice kit. The errand changes to `learned`; the procedure remains at `instrucciones` and is not yet demonstrated.
5. The player returns home and practices step by step at the corresponding station. The first valid step consumes the kit; every step checks location and order. An invalid attempt leaves the previous state unchanged.
6. Only the last step accredits the procedure, produces the result, completes the errand, and enables its unlock. Delivering again or practicing a finished project does not duplicate the result.

The three current chains are:

| Errand | Procedure | Mentor |
| --- | --- | --- |
| `bicicleta_de_mateo` | `reparar_bicicleta` | Mateo |
| `jardin_de_alma` | `plantar_jardin` | Alma |
| `te_de_ines` | `preparar_te` | Inés |

Each chain is completed once per save. Specific steps, materials, kits, results, and unlocks belong to the engine's catalog. The repaired bicycle, planted garden, and prepared tea appear after the final step is verified, not when an explanation is received.

Delivery without a fixed station was verified for all three quests outdoors and inside a house: **134/134 progression checks**. The playable chain physically follows Mateo away from the workshop and delivers through the journal's actual button: **33/33**, with 29,400 walkable positions. Checks also covered inventory retention after refusal, repeated deliveries, pending lessons after reload, and kit persistence. Core and chat regressions passed **141/141** and **133/133**, respectively. The backend passed **80/80 tests** and type checking; its shared instructions describe the same rule, with no provider calls during validation.

## Context sent to models

Existing routes retain their contract. `resident.progression` is optional and summarizes the state known to that resident. Total context is limited to **12,000 JSON characters**, the progression summary to **4,000**, and the complete HTTP request to **32 KiB**.

```json
{
  "coins": 4,
  "inventory": {"kit_jardin": 1},
  "quests": {
    "jardin_de_alma": {
      "status": "learned",
      "next_hint": "Practica en tu casa: Preparar la tierra de la maceta."
    }
  },
  "procedures": {
    "plantar_jardin": {
      "status": "instrucciones",
      "next_step_id": "preparar_tierra",
      "executed_steps": [],
      "world_verified": false
    }
  },
  "unlocks": []
}
```

This example represents the moment after delivering seeds: the player has received the kit and instructions but has not started practicing. The Spanish runtime hint asks the player to practice at home by preparing the potting soil. `learned` describes this errand phase; it does not mean a demonstrated skill. The backend validates:

- Coins and quantities as nonnegative safe integers; up to 32 item types.
- Up to 8 errands with status `accepted`, `learned`, or `completed`, and a hint of up to 240 characters.
- Up to 8 procedures with status `instrucciones`, `practicando`, or `demostrada`; up to 16 completed steps without duplicates.
- `world_verified` is true **if and only if** the procedure has status `demostrada`.
- Up to 24 distinct unlocks. Identifiers and next-step identifiers have a maximum of 80 characters.

Identifiers are not restricted to these three errands, allowing new definitions. Validation checks the summary's shape and consistency; it does not execute recipes or independently certify that a client met the requirements. Godot is authoritative for the local save in this prototype. A future shared version will need that authority on the server.

The context builder gives the player their inventory and errands; NPCs know only what they observed or learned in their own interactions. A summary must not include another resident's private progress merely to make dialogue convenient.

## The roles of Jev and OpenAI

Jev may consider errands when choosing among already permitted actions. Its response remains a bounded choice; no model action grants inventory, coins, skills, or quest progress.

OpenAI receives the same instruction for complete and streamed dialogue: do not claim to have delivered objects, transferred coins, unlocked a skill, or accepted or completed an errand just by mentioning it. It may describe a result already confirmed by the world; without confirmation, it proposes the next step and directs the player to the game interaction. Coins in the summary do not prove that the mentor awarded them.

Text is returned only as `{text, source, model}`, plus timings when streaming completes. No inventory or quest change is returned or executed, even if the provider includes additional fields. Provisional chunks do not confirm an action; completed dialogue may be saved as an episode with its provenance.

These instructions reduce incorrect claims but do not guarantee the semantic truth of every generated sentence. The verifiable protection is that **text never changes game state by itself**. Tests use sample responses to check the contract, limits, context preservation, and absence of mutation commands; they are not an evaluation of linguistic compliance with a real provider.

## Adding new learning chains

The catalog supports content following the current structure: accept, buy material, deliver it to the mentor, receive instructions and a kit, practice at home, and obtain a result with an unlock. Each definition needs materials, recipient, kit, practice station, stable steps, and final result. The historical `place` field describes the location associated with the occupation; it does not restrict delivery. The journal shows what is missing; the save separately retains learning, execution, and delivery. Already accepted errands follow the updated rule without restarting the game.

Investigations, trust-gated errands, and quests with several different phases are future extensions. There is no general system for executing those variants yet; expanding the current catalog does not implement them by itself.

Before adding a chain, verify that repeating a step does not duplicate its effects; delivering far from the mentor or without materials does not change inventory; nearby delivery works outdoors and inside a house without a specific station; practicing far from the project does not consume the kit; reloading retains progress; delivering twice does not duplicate the kit; completing twice does not duplicate the result; and an invented conversation does not alter those records. These checks allow content to grow while preserving the boundary between narration and simulation.
