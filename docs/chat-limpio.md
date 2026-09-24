# A conversation per encounter

The panel shows only the current encounter. Closing the conversation, walking away, returning to the menu, or loading the save discards its presentation: messages, draft, options, retry, and reading position. Complete exchanges remain in participants' memories and in the bounded context of their next conversation. Switching panels during the same encounter preserves the conversation.

The header retains the name and close control. Bubbles separate the two voices without repeating names, dates, provider, or turn states. Options show exactly what will be sent, using up to two lines; the editor and send button remain fixed below. Streaming updates only the pending bubble to preserve the player's text and cursor. Errors appear beside the conversation with a retry action.

Connected suggestions are generated in the same request as the response. `suggest_replies: true` enables structured output with `text` first and `suggestions` afterward; only spoken text travels as deltas. Options arrive in `done`, with up to two phrases, each limited to 45 characters and eight words. `reply_facts` allows literal player statements verified by the world, separate from the neighbor's knowledge. There is no second request to generate buttons.

The local fallback uses the last question, topic, neighbor's occupation, inventory, and verified learning. Choosing a reply never grants objects or completes errands. Generic options are replaced with specific questions or appropriate replies to the last statement.

Isolated verification: `chat_view_smoke.gd`, `player_chat_smoke.gd`, `chat_suggestions_smoke.gd`, `layout_smoke.gd`, `typography_smoke.gd`, `responsive_smoke.gd`, `interaction_smoke.gd`, `ui_smoke.gd`, `stream_smoke.gd`, and backend tests. The capture `artifacts/chat-suggestions/chat-after.png` uses test dialogue without external calls or access to the save.
