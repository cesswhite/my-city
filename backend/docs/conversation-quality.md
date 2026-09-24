# Natural conversation evaluation

The problem was answering a question about the day's activity with the temporary “Conversando con…” (“Talking with…”) state and filling the rest with hobbies or biography. The prompt now distinguishes the activity before the pause, occupation, wishes, and plans. Recent context remains limited to four exchanges between the pair.

`resident.conversation_scene` contains eight strings (`activity_before_chat`, `routine`, `place`, `place_label`, `intent`, `ongoing_action`, `phase`, `next_plan`) and `paused_for_chat: boolean`. The client captures that scene before reserving the character for conversation. The backend validates types, fields, and sizes; the whole context remains subject to the resident's 12,000-character total budget.

The scene takes precedence over the temporary `resident.activity` label when asking what the neighbor was doing. A pause or journey does not become a repair because of the character's occupation. `identity.role` describes an explicit role; `identity.goal` represents a wish, not a habit, hobby, history, or achievement. An ongoing task and a plan do not establish completed work.

Suggestions are generated in the same request. Questions identical to the current question or recent exchanges are removed, along with generic phrases such as “¿Qué estás haciendo hoy?” (“What are you doing today?”) and references to “hablando contigo” (“talking to you”). A contextual filter removes completion questions when the response itself already says the task is ongoing or finished. Neutral responses and verified `reply_facts` phrases remain; no option executes a world action.

## Eight isolated samples with a real provider

The existing Worker at `http://127.0.0.1:8787` was used with `gpt-6-luna`, streaming, `reasoning: none`, fictional context, and structured suggestions. The health endpoint was checked before making **eight calls**, without retries. No save was read or modified. Secrets remained in configuration and headers, outside output and artifacts.

Every case included the current “Conversando con Alex” (“Talking with Alex”) state, a different prior scene, and the goal of repairing César's bicycle. The tester name is anonymized as Alex in this public record. The second case also included the earlier defective response in history to check that it was not reused as an explanation of the activity. The exact Spanish responses below preserve the language evaluated.

| Scenario | Actual response | Review |
|---|---|---|
| Greeting | «Hola, Alex. Estoy bien, gracias; estaba ordenando las herramientas en el taller.» | Natural, brief, and consistent; adds an activity present in context. Does not drift into a mission. |
| Today's activity with defective history | «Estaba ordenando herramientas aquí en el taller.» | Resolves the reported failure. Does not recite the chat state, goal, or a hobby. |
| Rest, without repair | «Estaba tomando un descanso en la plaza.» | Respects the pause; does not invent work because the character is a mechanic. |
| Traveling to the café | «Iba al café a tomar un descanso.» | Distinguishes the destination from an arrival or purchase already completed. |
| Later plan | «Después pensaba dar una vuelta por el huerto.» | Keeps the plan in the future; does not assume the place was already visited. |
| Follow-up with an already answered question | «Después pensaba dar una vuelta por el huerto, aunque todavía estoy ordenando las herramientas.» | Returns to the plan without repeating where tools are stored. Room for improvement: uses present tense for the paused task and proposes “¿Ya terminaste de ordenar?” (“Have you finished tidying?”), redundant with its own response. |
| Unknown past activity | «No recuerdo qué hice esta mañana; ahora estoy descansando un rato en la plaza.» | Does not invent the past. Room for improvement: interprets `idle` as rest even though `activity_before_chat` is empty. |
| Repair without a verified result | «Todavía la estoy revisando; no he terminado de arreglarla.» | Does not invent a completed repair or award a skill. |

All eight responses met the 180-character and 30-word limits, used a single paragraph and no em dash, and exactly matched deltas to completion. None answered “estoy conversando contigo” (“I'm talking to you”) or turned the goal into a hobby. Qualitative review found six clear cases and two with the nuances noted above; it is not an exhaustive evaluation of language or personalities.

First text arrived in **555–1,641 ms** (median 896.5 ms); completion arrived in **790–2,235 ms** (median 1,214 ms). These are eight samples from this session, not a benchmark or latency guarantee. Generation retains one request per exchange.

## Targeted correction of the two findings

After reviewing the samples, the prompt was strengthened: `idle` alone does not establish rest, walking, or work; suggestions must check what has already been answered in the current text and recent responses. The completion-question filter covers explicit expressions such as “todavía estoy”, “sigo revisando”, “aún no he terminado”, “ya terminé”, and “está listo” (“I'm still”, “I'm still checking”, “I haven't finished yet”, “I finished”, and “it's ready”).

**Two additional calls** were authorized and executed, exclusively for the cases that showed these problems. The original evaluation was preserved unchanged. The total was **ten real calls**, without automatic retries or a second corrective request inside the game.

| Repeated case | Actual response after adjustment | Suggestions | First text / completion |
|---|---|---|---|
| Resolved follow-up | «Luego quiero dar una vuelta por el huerto.» | «¿Qué vas a hacer en el huerto?» | 1,084 / 1,334 ms |
| Unknown activity | «No recuerdo qué hice esta mañana; ahora estoy en la plaza, pero no sé qué estaba haciendo antes.» | None | 582 / 788 ms |

In these two checks, task status was no longer repeated and no unobserved rest was added. Both retained brevity, a single paragraph, and exact correspondence between deltas and completion. The results demonstrate the correction of those examples, not a guarantee for all possible conversations.

## Evidence and controlled repetition

The artifact paths below refer to historical local evidence excluded from the public repository; they are not downloadable repository files.

- Eight original results (`artifacts/natural-chat/evaluation.json`): scenarios, questions, responses, suggestions, timings, and checks.
- Two targeted results after adjustment (`artifacts/natural-chat/evaluation-targeted.json`), with separate output (`artifacts/natural-chat/live-targeted.log`).
- Evaluation output (`artifacts/natural-chat/live.log`).
- Final backend tests (`artifacts/natural-chat/backend.log`): **73/73**, 894 assertions and a passing TypeScript check, run after the final contextual filter.
- [Runner](../scripts/evaluate-dialogue.ts): `bun scripts/evaluate-dialogue.ts --health` checks only the local endpoint; `--live` explicitly enables eight paid calls with fictional fixtures. `--live --cases=seguimiento_resuelto,actividad_desconocida` limits execution to those two cases and writes a separate artifact. Do not run it automatically in tests or when starting the game.

Unit tests validate the contract, complete scene transfer, context isolation, rejection of invalid fields, and filters for repetition and redundant completion questions. They use simulated responses and do not establish generation quality on their own; that evidence is in the ten real samples above.

The model and parameters were preserved. The [official OpenAI documentation](https://developers.openai.com/api/docs/guides/latest-model) recommends specifying style and structure and evaluating instructions with the chosen model and workload; this game's tone and semantic decisions were checked with the scenarios described here.
