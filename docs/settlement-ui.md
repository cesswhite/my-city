# Town journal

The **Diario** (Journal) button opens **Pueblo** (Town). **Aprendizajes** (Apprenticeships) retains personal assignments and offers a route back to Town. Data and requirements come from `Settlement` and `SettlementJobs`; opening a card, selecting a worker, or checking a refusal neither consumes resources nor records a request.

## UI changes

The interface labels below describe the existing Spanish game UI; this document does not localize it.

| Principle | Before | After |
| --- | --- | --- |
| Hierarchy | The Journal opened only apprenticeships. | Opens Town with navigation to Resources, Projects, Jobs, and Orders. Apprenticeships remains visible in the header. |
| Orientation | No first community step. | Town shows the stage, present neighbors, and the initial sequence: collect 2 wood and 2 stone, then prepare the table. |
| Progressive disclosure | No community requirements view. | Upcoming and completed projects appear first; later ones expand under “Más adelante” (Later). Each card explains materials, coins, dependencies, and exploration. |
| Confirmation | No collaborator selection. | The card allows only present residents to be selected and shows the result of a pure query. One action confirms the job or explains why it is disabled. |
| Status | No job tracking. | Jobs shows travel, execution, return, or pause, updated progress, and cancellation. Construction retains its investment and progress. |
| Physical trade | No access to sales or community orders. | Resources and the shop link to selling; Orders offers travel to the requester. The engine still validates proximity, inventory, and quota before sales or deliveries. |
| Integration | History contained conversation, learning, and schedule. | Adds “Pedir ayuda” (Ask for help), opening the neighbor's jobs. Apprenticeships with absent mentors are omitted; the Journal selects a present mentor. |
| Readability | No community panel. | Centered panel up to 840×480, text size 16, titles 20, Journal palette, actions 36, wrapping and scrolling content. The header reserves the full width of “Aprendizajes”. |
| Access | No community controls. | Buttons have accessible names, tooltips, and focus; Tab/Shift-Tab stay within the panel. Esc removes the panel and backdrop. Successful results close both without continuing to intercept world input. |

## Presentation contract

`SettlementUI(host)` exposes `panel`, `layout()`, `close()`, `show_overview(tab="town")`, `show_task(task_id)`, `show_person(id)`, and `show_market()`. Main initializes the instance and handles Escape, resizing, and input blocking while the panel exists. Confirmation calls `host.begin_settlement_task(task_id, worker)`; cancellation, selling, and delivery call their respective local transactions. Controls carry `settlement_action` metadata and, where relevant, `task_id`, `worker_id`, `item_id`, or `order_id`.

The panel does not call providers. Conversation does not execute these actions either. Backend context adds only the public stage, the character's own job, and collaboration availability; the contract and limits are in [backend/README.md](../backend/README.md).

## Isolated verification

- `settlement_ui_smoke.gd -- --ui-test --settlement-start`: **77/77**. Initial community of three, queries without mutations, selection of present workers, requirements, start/cancel, physical gathering, selling, one-time delivery, focus, and backdrop closure.
- Graphical variant with `--capture`: **90/90**, including **13 screenshots** at 768×432 and 960×540, in `artifacts/settlement/ui/`. All five sections, requirements, and active work were visually reviewed. The first render revealed an overly narrow header; the final screenshot includes its correction and a text-width assertion.
- `learning_world_smoke.gd -- --ui-test`: **35/35**, with 29,400 positions checked. Preserves the previous learning chain.
- Backend: **88/88**, 2,248 assertions; `bun run check` passed. Three new cases cover bounded context, rejection before networking, and collaboration selection without economic parameters. Streaming retains one request and its previous limits.

Fixtures use real Main with a synthetic save, saving disabled, and empty providers. They do not load the user's save or access external services. Results do not measure a real provider's quality.
